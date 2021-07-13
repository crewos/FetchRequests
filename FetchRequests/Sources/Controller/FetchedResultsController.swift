//
//  FetchedResultsController.swift
//  Crew
//
//  Created by Adam Lickel on 2/1/16.
//  Copyright © 2016 Speramus Inc. All rights reserved.
//

import Foundation
import Combine

#if canImport(UIKit)
import UIKit
#endif
#if canImport(WatchKit)
import WatchKit
#endif

// MARK: - Delegate

public enum FetchedResultsChange<Location: Equatable>: Equatable {
    case insert(location: Location)
    case delete(location: Location)
    case update(location: Location)

    case move(from: Location, to: Location)

    public static func == (lhs: FetchedResultsChange<Location>, rhs: FetchedResultsChange<Location>) -> Bool {
        switch (lhs, rhs) {
        case let (.insert(left), .insert(right)):
            return left == right

        case let (.delete(left), .delete(right)):
            return left == right

        case let (.update(left), .update(right)):
            return left == right

        case let (.move(leftFrom, leftTo), .move(rightFrom, rightTo)):
            return leftFrom == rightFrom && leftTo == rightTo

        case (.insert, _), (.update, _), (.delete, _), (.move, _):
            return false
        }
    }
}

public protocol FetchedResultsControllerDelegate: AnyObject {
    associatedtype FetchedObject: FetchableObject

    func controllerWillChangeContent(_ controller: FetchedResultsController<FetchedObject>)
    func controllerDidChangeContent(_ controller: FetchedResultsController<FetchedObject>)

    func controller(
        _ controller: FetchedResultsController<FetchedObject>,
        didChange object: FetchedObject,
        for change: FetchedResultsChange<IndexPath>
    )
    func controller(
        _ controller: FetchedResultsController<FetchedObject>,
        didChange section: FetchedResultsSection<FetchedObject>,
        for change: FetchedResultsChange<Int>
    )
}

public extension FetchedResultsControllerDelegate {
    func controllerWillChangeContent(_ controller: FetchedResultsController<FetchedObject>) {}
    func controllerDidChangeContent(_ controller: FetchedResultsController<FetchedObject>) {}

    func controller(
        _ controller: FetchedResultsController<FetchedObject>,
        didChange object: FetchedObject,
        for change: FetchedResultsChange<IndexPath>
    ) {
    }

    func controller(
        _ controller: FetchedResultsController<FetchedObject>,
        didChange section: FetchedResultsSection<FetchedObject>,
        for change: FetchedResultsChange<Int>
    ) {
    }
}

internal class FetchResultsDelegate<FetchedObject: FetchableObject>: FetchedResultsControllerDelegate {
    typealias Controller = FetchedResultsController<FetchedObject>
    typealias Section = FetchedResultsSection<FetchedObject>

    private let willChange: (_ controller: Controller) -> Void
    private let didChange: (_ controller: Controller) -> Void

    private let changeObject: (_ controller: Controller, _ object: FetchedObject, _ change: FetchedResultsChange<IndexPath>) -> Void
    private let changeSection: (_ controller: Controller, _ section: Section, _ change: FetchedResultsChange<Int>) -> Void

    init<Parent: FetchedResultsControllerDelegate>(
        _ parent: Parent
    ) where Parent.FetchedObject == FetchedObject {
        willChange = { [weak parent] controller in
            parent?.controllerWillChangeContent(controller)
        }
        didChange = { [weak parent] controller in
            parent?.controllerDidChangeContent(controller)
        }

        changeObject = { [weak parent] controller, object, change in
            parent?.controller(controller, didChange: object, for: change)
        }
        changeSection = { [weak parent] controller, section, change in
            parent?.controller(controller, didChange: section, for: change)
        }
    }

    func controllerWillChangeContent(_ controller: Controller) {
        self.willChange(controller)
    }

    func controllerDidChangeContent(_ controller: Controller) {
        self.didChange(controller)
    }

    func controller(
        _ controller: Controller,
        didChange object: FetchedObject,
        for change: FetchedResultsChange<IndexPath>
    ) {
        self.changeObject(controller, object, change)
    }

    func controller(
        _ controller: Controller,
        didChange section: Section,
        for change: FetchedResultsChange<Int>
    ) {
        self.changeSection(controller, section, change)
    }
}

// MARK: - Errors

public enum FetchedResultsError: Error {
    case objectNotFound
}

// MARK: - Sections

public struct FetchedResultsSection<FetchedObject: FetchableObject>: Equatable, Identifiable {
    public let name: String
    public fileprivate(set) var objects: [FetchedObject]

    public var id: String {
        return name
    }

    public var numberOfObjects: Int {
        return objects.count
    }

    public init(name: String, objects: [FetchedObject] = []) {
        self.name = name
        self.objects = objects
    }
}

// MARK: - FetchedResultsController

public class FetchedResultsController<FetchedObject: FetchableObject>: NSObject, FetchedResultsControllerProtocol {
    public typealias Section = FetchedResultsSection<FetchedObject>
    public typealias SectionNameKeyPath = KeyPath<FetchedObject, String>

    public let request: FetchRequest<FetchedObject>
    public private(set) var sortDescriptors: [NSSortDescriptor]
    public let sectionNameKeyPath: SectionNameKeyPath?

    private var observationTokens: [ObjectIdentifier: [InvalidatableToken]] = [:]

    private var associatedValues: [AssociatedValueKey<FetchedObject>: AssociatedValueReference] = [:]

    private let memoryPressureToken: FetchRequestObservableToken<Notification>? = {
        #if canImport(UIKit) && !os(watchOS)
        return FetchRequestObservableToken(
            token: ObservableNotificationCenterToken(name: UIApplication.didReceiveMemoryWarningNotification)
        )
        #else
        return nil
        #endif
    }()

    // swiftlint:disable:next weak_delegate
    private var delegate: FetchResultsDelegate<FetchedObject>?

    public var associatedFetchSize: Int = 10

    public private(set) var hasFetchedObjects: Bool = false
    public private(set) var fetchedObjects: [FetchedObject] = []
    private var fetchedObjectIDs: Set<FetchedObject.ID> = []
    private var _indexPathsTable: [FetchedObject: IndexPath]?
    private var indexPathsTable: [FetchedObject: IndexPath] {
        if let existing = _indexPathsTable {
            return existing
        }

        let new = generateIndexPathsTable()
        _indexPathsTable = new
        return new
    }

    private let debounceInsertsAndReloads: Bool
    private var objectsToReload: Set<FetchedObject> = []
    private var objectsToInsert: Set<FetchedObject> = []

    private let objectWillChangeSubject = PassthroughSubject<Void, Never>()
    private let objectDidChangeSubject = PassthroughSubject<Void, Never>()

    public private(set) lazy var objectWillChange = objectWillChangeSubject.eraseToAnyPublisher()
    public private(set) lazy var objectDidChange = objectDidChangeSubject.eraseToAnyPublisher()

    public private(set) var sections: [Section] = [] {
        didSet {
            _indexPathsTable = nil
        }
    }

    private lazy var context: Context<FetchedObject> = {
        return Context { [weak self] keyPath, objectID in
            guard let `self` = self else {
                throw FetchedResultsError.objectNotFound
            }

            return try self.associatedValue(with: keyPath, forObjectID: objectID)
        }
    }()

    public init(
        request: FetchRequest<FetchedObject>,
        sortDescriptors: [NSSortDescriptor] = [],
        sectionNameKeyPath: SectionNameKeyPath? = nil,
        debounceInsertsAndReloads: Bool = true
    ) {
        self.request = request
        self.sortDescriptors = sortDescriptors.finalize(with: sectionNameKeyPath)
        self.sectionNameKeyPath = sectionNameKeyPath
        self.debounceInsertsAndReloads = debounceInsertsAndReloads
    }

    deinit {
        if Thread.isMainThread {
            reset(emitChanges: false)
        } else {
            DispatchQueue.main.sync {
                reset(emitChanges: false)
            }
        }
    }

    public func setDelegate<Delegate: FetchedResultsControllerDelegate>(_ delegate: Delegate?) where Delegate.FetchedObject == FetchedObject {
        self.delegate = delegate.flatMap {
            FetchResultsDelegate($0)
        }
    }

    public func clearDelegate() {
        self.delegate = nil
    }

    // MARK: - Actions

    @objc
    private func debouncedReload() {
        assert(Thread.isMainThread)

        guard !objectsToReload.isEmpty else {
            return
        }
        reload(objectsToReload)
        objectsToReload.removeAll()
    }

    @objc
    private func debouncedInsert() {
        assert(Thread.isMainThread)

        guard !objectsToInsert.isEmpty else {
            return
        }
        insert(objectsToInsert)
        objectsToInsert.removeAll()
    }

    @objc
    private func debouncedFetch() {
        assert(Thread.isMainThread)

        performFetch()
    }
}

// MARK: Fetches

public extension FetchedResultsController {
    func performFetch(completion: @escaping () -> Void) {
        startObservingNotificationsIfNeeded()

        request.request { [weak self] objects in
            self?.assign(fetchedObjects: objects, completion: completion)
        }
    }

    func resort(using newSortDescriptors: [NSSortDescriptor], completion: @escaping () -> Void) {
        assert(Thread.isMainThread)

        sortDescriptors = newSortDescriptors.finalize(with: sectionNameKeyPath)
        guard hasFetchedObjects else {
            completion()
            return
        }
        assign(fetchedObjects: fetchedObjects, dropObjectsToInsert: false, completion: completion)
    }

    func indexPath(for object: FetchedObject) -> IndexPath? {
        return indexPathsTable[object]
    }

    func reset() {
        reset(emitChanges: true)
    }

    private func reset(emitChanges: Bool) {
        stopObservingNotifications()
        removeAll(emitChanges: emitChanges)
    }
}

// MARK: Associated Values

private extension FetchedResultsController {
    func associatedValue(
        with keyPath: PartialKeyPath<FetchedObject>,
        forObjectID objectID: FetchedObject.ID
    ) throws -> Any? {
        let key = AssociatedValueKey(id: objectID, keyPath: keyPath)

        if let holder = associatedValues[key] {
            return holder.value
        }

        guard let index = fetchedObjects.firstIndex(where: { $0.id == objectID }) else {
            throw FetchedResultsError.objectNotFound
        }

        guard let association = request.associationsByKeyPath[keyPath] else {
            throw FetchedResultsError.objectNotFound
        }

        let objects: [FetchedObject]
        if associatedFetchSize == 0 {
            objects = fetchedObjects
        } else {
            let difference = associatedFetchSize / 2
            let smallIndex = max(0, index - difference)
            let largeIndex = min(fetchedObjects.endIndex - 1, index + difference)

            objects = Array(fetchedObjects[smallIndex...largeIndex])
        }
        let fetchableObjects = objects.filter {
            let objectID = $0.id
            let key = AssociatedValueKey(id: objectID, keyPath: keyPath)
            return associatedValues[key] == nil
        }

        var valueReferences: [AssociatedValueKey<FetchedObject>: AssociatedValueReference] = [:]

        for object in fetchableObjects {
            // Mark fetchable objects as visited
            let objectID = object.id
            let key = AssociatedValueKey(id: objectID, keyPath: keyPath)
            let reference = association.referenceGenerator(object)

            valueReferences[key] = reference
            associatedValues[key] = reference
        }

        association.request(fetchableObjects) { [weak self] values in
            let assign: () -> Void = {
                self?.assignAssociatedValues(
                    values,
                    with: keyPath,
                    for: fetchableObjects,
                    references: valueReferences
                )
            }

            if !Thread.isMainThread {
                DispatchQueue.main.async(execute: assign)
            } else {
                assign()
            }
        }

        // On the off chance that the fetch is synchronous, return the new hash value
        let holder = associatedValues[key]
        return holder?.value
    }
}

// MARK: Contents

private extension FetchedResultsController {
    func assignAssociatedValues(
        _ values: [FetchedObject.ID: Any],
        with keyPath: PartialKeyPath<FetchedObject>,
        for objects: [FetchedObject],
        references: [AssociatedValueKey<FetchedObject>: AssociatedValueReference],
        emitChanges: Bool = true
    ) {
        assert(Thread.isMainThread)

        performChanges(emitChanges: emitChanges) {
            for object in objects {
                guard let indexPath = indexPath(for: object) else {
                    continue
                }

                let objectID = object.id
                guard let value = values[objectID] else {
                    continue
                }

                let key = AssociatedValueKey(id: objectID, keyPath: keyPath)
                let reference = references[key]

                reference?.stopObservingAndUpdateValue(to: value)

                notifyUpdating(object, at: indexPath, emitChanges: emitChanges)
            }
        }

        for object in objects {
            let objectID = object.id
            let key = AssociatedValueKey(id: objectID, keyPath: keyPath)
            let reference = references[key]

            reference?.observeChanges { [weak self, weak object] invalid in
                assert(Thread.isMainThread)

                guard let object = object else {
                    return
                }

                if invalid {
                    self?.associatedValues[key] = nil
                }

                self?.enqueueReload(of: object)
            }
        }
    }

    func removeAssociatedValue(
        for object: FetchedObject,
        keyPath: PartialKeyPath<FetchedObject>,
        emitChanges: Bool = true
    ) {
        let objectID = object.id
        guard let indexPath = indexPath(for: object) else {
            return
        }

        performChanges(emitChanges: emitChanges) {
            let key = AssociatedValueKey(id: objectID, keyPath: keyPath)
            associatedValues[key] = nil

            notifyUpdating(object, at: indexPath, emitChanges: emitChanges)
        }
    }

    func assign(
        fetchedObjects objects: [FetchedObject],
        emitChanges: Bool = true,
        dropObjectsToInsert: Bool = true,
        completion: @escaping () -> Void
    ) {
        guard objects.count <= 100 || !Thread.isMainThread else {
            // Bounce ourself off of the main queue
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.assign(fetchedObjects: objects, emitChanges: emitChanges, completion: completion)
            }
            return
        }

        let sorted = objects.sorted(by: sortDescriptors)

        func performAssign() {
            assign(
                sortedFetchedObjects: sorted,
                emitChanges: emitChanges,
                dropObjectsToInsert: dropObjectsToInsert
            )
            completion()
        }

        if !Thread.isMainThread {
            DispatchQueue.main.async(execute: performAssign)
        } else {
            performAssign()
        }
    }

    func assign(
        sortedFetchedObjects objects: [FetchedObject],
        emitChanges: Bool,
        dropObjectsToInsert: Bool
    ) {
        assert(Thread.isMainThread)

        if dropObjectsToInsert {
            objectsToInsert.removeAll()
        }
        performChanges(emitChanges: emitChanges) {
            let operations = objects.difference(from: fetchedObjects)

            for operation in operations {
                switch operation {
                case let .remove(index, element, _):
                    remove(element, atIndex: index, emitChanges: emitChanges)

                case let .insert(index, element, _):
                    insert(element, atIndex: index, emitChanges: emitChanges)
                }
            }
        }
    }

    func delete(_ object: FetchedObject, emitChanges: Bool = true) throws {
        guard let indexPath = indexPath(for: object), let fetchIndex = fetchIndex(for: indexPath) else {
            throw FetchedResultsError.objectNotFound
        }

        performChanges(emitChanges: emitChanges) {
            stopObserving(object)

            sections[indexPath.section].objects.remove(at: indexPath.item)
            fetchedObjects.remove(at: fetchIndex)
            fetchedObjectIDs.remove(object.id)

            notifyDeleting(object, at: indexPath, emitChanges: emitChanges)

            if sections[indexPath.section].numberOfObjects == 0 {
                let section = sections.remove(at: indexPath.section)

                notifyDeleting(section, at: indexPath.section, emitChanges: emitChanges)
            }
        }
    }

    func insert<C: Collection>(_ objects: C, emitChanges: Bool = true) where C.Iterator.Element == FetchedObject {
        let fetchedObjectIDs = self.fetchedObjectIDs

        guard objects.count <= 100 || !Thread.isMainThread else {
            // Bounce ourself off of the main queue
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.insert(objects, fetchedObjectIDs: fetchedObjectIDs, emitChanges: emitChanges)
            }
            return
        }
        insert(objects, fetchedObjectIDs: fetchedObjectIDs, emitChanges: emitChanges)
    }

    private func insert<C: Collection>(
        _ objects: C,
        fetchedObjectIDs: Set<FetchedObject.ID>,
        emitChanges: Bool = true
    ) where C.Iterator.Element == FetchedObject {
        let objects = objects.filter { object in
            guard !object.isDeleted else {
                return false
            }
            return !fetchedObjectIDs.contains(object.id)
        }.sorted(by: sortDescriptors)

        guard !objects.isEmpty else {
            return
        }

        func performInsert() {
            insert(sortedObjects: objects, emitChanges: emitChanges)
        }

        if !Thread.isMainThread {
            DispatchQueue.main.async(execute: performInsert)
        } else {
            performInsert()
        }
    }

    private func insert<C: Collection>(sortedObjects objects: C, emitChanges: Bool = true) where C.Iterator.Element == FetchedObject {
        assert(Thread.isMainThread)

        performChanges(emitChanges: emitChanges) {
            for object in objects {
                guard !object.isDeleted else {
                    continue
                }
                let newFetchIndex = idealObjectIndex(for: object, inArray: fetchedObjects)

                if newFetchIndex != fetchedObjects.count {
                    guard fetchedObjects[newFetchIndex] != object else {
                        continue
                    }
                }
                insert(object, atIndex: newFetchIndex, emitChanges: emitChanges)
            }
        }

        CWLogVerbose("Inserted \(objects.count) objects")
    }

    func reload(_ object: FetchedObject, emitChanges: Bool = true) throws {
        guard let indexPath = indexPath(for: object) else {
            throw FetchedResultsError.objectNotFound
        }

        performChanges(emitChanges: emitChanges) {
            notifyUpdating(object, at: indexPath, emitChanges: emitChanges)
        }
    }

    func reload<C: Collection>(_ objects: C, emitChanges: Bool = true) where C.Iterator.Element == FetchedObject {
        var objectPaths: [FetchedObject: IndexPath] = [:]
        for object in objects {
            guard let indexPath = indexPath(for: object) else {
                continue
            }
            objectPaths[object] = indexPath
        }

        guard !objectPaths.isEmpty else {
            return
        }

        performChanges(emitChanges: emitChanges) {
            for (object, indexPath) in objectPaths {
                notifyUpdating(object, at: indexPath, emitChanges: emitChanges)
            }
        }

        CWLogVerbose("Reloaded \(objects.count) objects")
    }

    func move(_ object: FetchedObject, emitChanges: Bool = true) throws {
        guard let indexPath = indexPath(for: object) else {
            throw FetchedResultsError.objectNotFound
        }

        try move(object, from: indexPath, emitChanges: emitChanges)
    }

    func move(_ object: FetchedObject, fromSectionName sectionName: String, emitChanges: Bool = true) throws {
        guard !sections.isEmpty else {
            throw FetchedResultsError.objectNotFound
        }

        let sectionIndex = idealSectionIndex(forSectionName: sectionName)
        guard sectionIndex < sections.count else {
            throw FetchedResultsError.objectNotFound
        }
        guard let itemIndex = sections[sectionIndex].objects.firstIndex(of: object) else {
            throw FetchedResultsError.objectNotFound
        }

        let indexPath = IndexPath(item: itemIndex, section: sectionIndex)
        try move(object, from: indexPath, emitChanges: emitChanges)
    }

    func move(_ object: FetchedObject, from fromIndexPath: IndexPath, emitChanges: Bool = true) throws {
        guard let oldFetchIndex = fetchIndex(for: fromIndexPath), object == self.object(at: fromIndexPath) else {
            throw FetchedResultsError.objectNotFound
        }

        performChanges(emitChanges: emitChanges) {
            let newSectionName = object.sectionName(forKeyPath: sectionNameKeyPath)
            var newSectionIndex = idealSectionIndex(forSectionName: newSectionName)

            let addedSection: Bool
            let changedSection: Bool
            if sections.endIndex <= newSectionIndex || sections[newSectionIndex].name != newSectionName {
                addedSection = true
                changedSection = true
            } else if fromIndexPath.section != newSectionIndex {
                addedSection = false
                changedSection = true
            } else {
                addedSection = false
                changedSection = false
            }

            let removedSection: Bool
            if changedSection {
                let oldSection = sections[fromIndexPath.section]
                removedSection = oldSection.numberOfObjects == 1
            } else {
                removedSection = false
            }

            // Remove our entry
            sections[fromIndexPath.section].objects.remove(at: fromIndexPath.item)

            if removedSection || addedSection {
                // Moves don't work if we made a section change
                notifyDeleting(object, at: fromIndexPath, emitChanges: emitChanges)
            }

            if removedSection {
                // Remove our old section
                let oldSection = sections.remove(at: fromIndexPath.section)

                notifyDeleting(oldSection, at: fromIndexPath.section, emitChanges: emitChanges)

                newSectionIndex = idealSectionIndex(forSectionName: newSectionName)
            }

            if addedSection {
                // Insert our new section

                let newSection = Section(name: newSectionName)
                sections.insert(newSection, at: newSectionIndex)

                notifyInserting(newSection, at: newSectionIndex, emitChanges: emitChanges)
            }

            let newObjectIndex = idealObjectIndex(for: object, inArray: sections[newSectionIndex].objects)

            sections[newSectionIndex].objects.insert(object, at: newObjectIndex)

            fetchedObjects.remove(at: oldFetchIndex)
            let newFetchIndex = idealObjectIndex(for: object, inArray: fetchedObjects)
            fetchedObjects.insert(object, at: newFetchIndex)

            let toIndexPath = IndexPath(item: newObjectIndex, section: newSectionIndex)

            if removedSection || addedSection {
                notifyInserting(object, at: toIndexPath, emitChanges: emitChanges)
            } else {
                notifyMoving(object, from: fromIndexPath, to: toIndexPath, emitChanges: emitChanges)
            }
        }
    }

    func removeAll(emitChanges: Bool = true) {
        performChanges(emitChanges: emitChanges) {
            if let delegate = delegate, emitChanges {
                for (sectionIndex, section) in sections.enumerated() {
                    for (objectIndex, object) in section.objects.enumerated() {
                        let indexPath = IndexPath(item: objectIndex, section: sectionIndex)

                        delegate.controller(self, didChange: object, for: .delete(location: indexPath))
                    }

                    delegate.controller(self, didChange: section, for: .delete(location: sectionIndex))
                }
            }

            for object in fetchedObjects {
                stopObserving(object)
            }

            rawRemoveAll()
        }
    }

    private func rawRemoveAll() {
        hasFetchedObjects = false
        fetchedObjects = []
        sections = []
        fetchedObjectIDs = []
        associatedValues = [:]
    }

    func removeAllAssociatedValues(emitChanges: Bool = true) {
        performChanges(emitChanges: emitChanges) {
            for (sectionIndex, section) in sections.enumerated() {
                for (objectIndex, object) in section.objects.enumerated() {
                    let indexPath = IndexPath(item: objectIndex, section: sectionIndex)

                    notifyUpdating(object, at: indexPath, emitChanges: emitChanges)
                }
            }
            associatedValues = [:]
        }
    }

    func remove(_ object: FetchedObject, atIndex index: Int, emitChanges: Bool = true) {
        guard let indexPath = self.indexPath(forFetchIndex: index) else {
            return
        }

        stopObserving(object)

        fetchedObjects.remove(at: index)
        sections[indexPath.section].objects.remove(at: indexPath.item)
        fetchedObjectIDs.remove(object.id)

        notifyDeleting(object, at: indexPath, emitChanges: emitChanges)

        if sections[indexPath.section].objects.isEmpty {
            let section = sections.remove(at: indexPath.section)
            notifyDeleting(section, at: indexPath.section, emitChanges: emitChanges)
        }
    }

    func insert(_ object: FetchedObject, atIndex index: Int, emitChanges: Bool = true) {
        let sectionName = object.sectionName(forKeyPath: sectionNameKeyPath)
        let sectionIndex = idealSectionIndex(forSectionName: sectionName)

        let sectionPrefix = sections[0..<sectionIndex].reduce(0) { $0 + $1.numberOfObjects }
        let sectionObjectIndex = index - sectionPrefix

        if sections.endIndex <= sectionIndex || sections[sectionIndex].name != sectionName {
            assert(sectionObjectIndex == 0, "For some reason a section wasn't deleted")
            let section = Section(name: sectionName)
            sections.insert(section, at: sectionIndex)

            notifyInserting(section, at: sectionIndex, emitChanges: emitChanges)
        }

        fetchedObjects.insert(object, at: index)
        sections[sectionIndex].objects.insert(object, at: sectionObjectIndex)
        fetchedObjectIDs.insert(object.id)

        let indexPath = IndexPath(item: sectionObjectIndex, section: sectionIndex)
        notifyInserting(object, at: indexPath, emitChanges: emitChanges)

        startObserving(object)
    }

    func startObserving(_ object: FetchedObject) {
        assert(Thread.isMainThread)

        var observations: [InvalidatableToken] = []

        for association in request.associations {
            let keyPath = association.keyPath
            let observer = association.observeKeyPath(object) { [weak self] object, oldValue, newValue in
                // Nil out associated value and send change event
                self?.removeAssociatedValue(for: object, keyPath: keyPath)
            }

            observations.append(observer)
        }

        let handleChange: (FetchedObject) -> Void = { [weak self] object in
            guard let `self` = self else {
                return
            }
            do {
                if object.isDeleted {
                    try self.delete(object)
                } else {
                    self.enqueueReload(of: object)
                }
            } catch {
                CWLogInfo("Failed to reload object \(object)?!")
            }
        }

        let dataObserver = object.observeDataChanges { [weak object] in
            guard let object = object else {
                return
            }
            handleChange(object)
        }

        let isDeletedObserver = object.observeIsDeletedChanges { [weak object] in
            guard let object = object else {
                return
            }
            handleChange(object)
        }

        observations += [dataObserver, isDeletedObserver]

        let handleSort: (FetchedObject, Bool, Any?, Any?) -> Void = { [weak self] object, isSection, old, new in
            guard let `self` = self else {
                return
            }
            if let old = old as? NSObject, let new = new as? NSObject {
                guard old != new else {
                    return
                }
            }

            do {
                if isSection, let oldName = old as? String {
                    try self.move(object, fromSectionName: oldName)
                } else {
                    try self.move(object)
                }
            } catch {
                CWLogInfo("Failed to move object \(object)?!")
            }
        }

        for (index, sort) in sortDescriptors.enumerated() {
            guard let keyPath = sort.key, keyPath != "self" else {
                continue
            }
            let isSectionNameKeyPath: Bool
            if sectionNameKeyPath != nil, index == 0 {
                isSectionNameKeyPath = true
            } else {
                isSectionNameKeyPath = false
            }

            let observation = LegacyKeyValueObserving(
                object: object,
                keyPath: keyPath,
                type: Any.self
            ) { object, oldValue, newValue in
                handleSort(object, isSectionNameKeyPath, oldValue, newValue)
            }
            observations.append(observation)
        }

        object.listenForUpdates()
        object.context = context

        observationTokens[ObjectIdentifier(object)] = observations
    }

    func stopObserving(_ object: FetchedObject) {
        assert(Thread.isMainThread)

        object.context = nil
        observationTokens[ObjectIdentifier(object)] = nil
    }

    func startObservingNotificationsIfNeeded() {
        assert(Thread.isMainThread)

        memoryPressureToken?.observeIfNeeded { [ weak self] notification in
            self?.removeAllAssociatedValues()
        }
        request.objectCreationToken.observeIfNeeded { [weak self] data in
            self?.observedObjectUpdate(data)
        }

        for dataResetToken in request.dataResetTokens {
            dataResetToken.observeIfNeeded { [weak self] _ in
                self?.handleDatabaseClear()
            }
        }
    }

    func stopObservingNotifications() {
        assert(Thread.isMainThread)

        memoryPressureToken?.invalidateIfNeeded()
        request.objectCreationToken.invalidateIfNeeded()

        for dataResetToken in request.dataResetTokens {
            dataResetToken.invalidateIfNeeded()
        }
    }
}

// MARK: - Object Updates

private extension FetchedResultsController {
    func observedObjectUpdate(_ data: FetchedObject.RawData) {
        guard let id = FetchedObject.entityID(from: data) else {
            return
        }

        guard !fetchedObjectIDs.contains(id) else {
            return
        }

        guard request.creationInclusionCheck(data) else {
            return
        }

        enqueueInsert(of: data)
    }
}

// MARK: - Debouncing

private extension FetchedResultsController {
    func enqueueReload(of object: FetchedObject, emitChanges: Bool = true) {
        assert(Thread.isMainThread)

        guard debounceInsertsAndReloads else {
            do {
                try reload(object, emitChanges: emitChanges)
            } catch {
                CWLogError("Failed to reload object: \(error)")
            }
            return
        }

        objectsToReload.insert(object)

        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(debouncedReload), object: nil)
        perform(#selector(debouncedReload), with: nil, afterDelay: 0)
    }

    func enqueueInsert(of object: FetchedObject.RawData, emitChanges: Bool = true) {
        guard let insertedObject = FetchedObject(data: object) else {
            return
        }
        manuallyInsert(objects: [insertedObject], emitChanges: emitChanges)
    }

    func handleDatabaseClear() {
        assert(Thread.isMainThread)

        guard debounceInsertsAndReloads else {
            performFetch()
            return
        }

        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(debouncedFetch), object: nil)
        perform(#selector(debouncedFetch), with: nil, afterDelay: 0)
    }
}

internal extension FetchedResultsController {
    var listeningForInserts: Bool {
        return request.objectCreationToken.isObserving
    }
}

// MARK: - InternalFetchResultsControllerProtocol

extension FetchedResultsController: InternalFetchResultsControllerProtocol {
    internal func manuallyInsert(objects: [FetchedObject], emitChanges: Bool = true) {
        assert(Thread.isMainThread)

        guard listeningForInserts, !objects.isEmpty else {
            return
        }

        objects.forEach { $0.listenForUpdates() }

        guard debounceInsertsAndReloads else {
            insert(objects, emitChanges: emitChanges)
            return
        }

        objectsToInsert.formUnion(objects)

        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(debouncedInsert), object: nil)
        perform(#selector(debouncedInsert), with: nil, afterDelay: 0)
    }
}

// MARK: Delegate Change Events

private extension FetchedResultsController {
    func performChanges(emitChanges: Bool = true, changes: () -> Void) {
        assert(Thread.isMainThread)
        let delegate = self.delegate

        if emitChanges {
            objectWillChangeSubject.send()
            delegate?.controllerWillChangeContent(self)
        }

        changes()

        hasFetchedObjects = true
        if emitChanges {
            delegate?.controllerDidChangeContent(self)
            objectDidChangeSubject.send()
        }
    }

    func generateIndexPathsTable() -> [FetchedObject: IndexPath] {
        var updatedIndexPaths: [FetchedObject: IndexPath] = [:]
        for (sectionIndex, section) in sections.enumerated() {
            for (itemIndex, object) in section.objects.enumerated() {
                updatedIndexPaths[object] = IndexPath(item: itemIndex, section: sectionIndex)
            }
        }

        return updatedIndexPaths
    }

    func notifyInserting(_ object: FetchedObject, at indexPath: IndexPath, emitChanges: Bool) {
        assert(Thread.isMainThread)
        guard let delegate = delegate, emitChanges else {
            return
        }

        delegate.controller(self, didChange: object, for: .insert(location: indexPath))
    }

    func notifyMoving(_ object: FetchedObject, from fromIndexPath: IndexPath, to toIndexPath: IndexPath, emitChanges: Bool) {
        assert(Thread.isMainThread)
        guard let delegate = delegate, emitChanges else {
            return
        }

        delegate.controller(self, didChange: object, for: .move(from: fromIndexPath, to: toIndexPath))
    }

    func notifyUpdating(_ object: FetchedObject, at indexPath: IndexPath, emitChanges: Bool) {
        assert(Thread.isMainThread)
        guard let delegate = delegate, emitChanges else {
            return
        }

        delegate.controller(self, didChange: object, for: .update(location: indexPath))
    }

    func notifyDeleting(_ object: FetchedObject, at indexPath: IndexPath, emitChanges: Bool) {
        assert(Thread.isMainThread)
        guard let delegate = delegate, emitChanges else {
            return
        }

        delegate.controller(self, didChange: object, for: .delete(location: indexPath))
    }

    func notifyInserting(_ section: Section, at sectionIndex: Int, emitChanges: Bool) {
        assert(Thread.isMainThread)
        guard let delegate = delegate, emitChanges else {
            return
        }

        delegate.controller(self, didChange: section, for: .insert(location: sectionIndex))
    }

    func notifyDeleting(_ section: Section, at sectionIndex: Int, emitChanges: Bool) {
        assert(Thread.isMainThread)
        guard let delegate = delegate, emitChanges else {
            return
        }

        delegate.controller(self, didChange: section, for: .delete(location: sectionIndex))
    }
}

// MARK: - Associated Values Extensions

private class Context<FetchedObject: FetchableObject>: NSObject {
    typealias Wrapped = (_ keyPath: PartialKeyPath<FetchedObject>, _ objectID: FetchedObject.ID) throws -> Any?

    let wrapped: Wrapped

    func associatedValue(with keyPath: PartialKeyPath<FetchedObject>, forObjectID objectID: FetchedObject.ID) throws -> Any? {
        return try wrapped(keyPath, objectID)
    }

    init(wrapped: @escaping Wrapped) {
        self.wrapped = wrapped
    }
}

private class Weak<Element: AnyObject>: NSObject {
    private(set) weak var value: Element?

    init(_ value: Element) {
        self.value = value
    }
}

private struct AssociatedKeys {
    static var context = "context"
}

private extension FetchableObjectProtocol where Self: NSObject {
    weak var context: Context<Self>? {
        get {
            let weakContainer = objc_getAssociatedObject(self, &AssociatedKeys.context) as? Weak<Context<Self>>

            return weakContainer?.value
        }
        set {
            if let newValue = newValue {
                objc_setAssociatedObject(self, &AssociatedKeys.context, Weak(newValue), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            } else {
                objc_setAssociatedObject(self, &AssociatedKeys.context, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
        }
    }

    func getAssociatedValue<Value>(with keyPath: PartialKeyPath<Self>) throws -> Value? {
        guard let context = context else {
            throw FetchedResultsError.objectNotFound
        }

        if let rawValue = try context.associatedValue(with: keyPath, forObjectID: id) {
            return rawValue as? Value
        } else {
            return nil
        }
    }
}

// MARK: Fetchable Entity IDs

public extension FetchableObjectProtocol where Self: NSObject {
    func performFault<EntityID: FetchableEntityID>(
        on keyPath: KeyPath<Self, EntityID>,
        performFetchIfNeeded: Bool = true
    ) -> EntityID.FetchableEntity? {
        let fallback: (EntityID) -> EntityID.FetchableEntity? = { entityID in
            guard performFetchIfNeeded else {
                return nil
            }
            return EntityID.fetch(byID: entityID)
        }

        return performFault(on: keyPath, fallback: fallback)
    }

    func performFault<EntityID: FetchableEntityID>(
        on keyPath: KeyPath<Self, EntityID?>,
        performFetchIfNeeded: Bool = true
    ) -> EntityID.FetchableEntity? {
        let fallback: (EntityID) -> EntityID.FetchableEntity? = { entityID in
            guard performFetchIfNeeded else {
                return nil
            }
            return EntityID.fetch(byID: entityID)
        }

        return performFault(on: keyPath, fallback: fallback)
    }
}

// MARK: Fetchable Entity ID Arrays

public extension FetchableObjectProtocol where Self: NSObject {
    func performFault<EntityID: FetchableEntityID>(
        on keyPath: KeyPath<Self, [EntityID]>,
        performFetchIfNeeded: Bool = true
    ) -> [EntityID.FetchableEntity]? {
        let fallback: ([EntityID]) -> [EntityID.FetchableEntity]? = { entityIDs in
            guard performFetchIfNeeded else {
                return nil
            }
            return EntityID.fetch(byIDs: entityIDs)
        }

        return performFault(on: keyPath, fallback: fallback)
    }

    func performFault<EntityID: FetchableEntityID>(
        on keyPath: KeyPath<Self, [EntityID]?>,
        performFetchIfNeeded: Bool = true
    ) -> [EntityID.FetchableEntity]? {
        let fallback: ([EntityID]) -> [EntityID.FetchableEntity]? = { entityIDs in
            guard performFetchIfNeeded else {
                return nil
            }
            return EntityID.fetch(byIDs: entityIDs)
        }

        return performFault(on: keyPath, fallback: fallback)
    }
}

// MARK: Raw Entity IDs

public extension FetchableObjectProtocol where Self: NSObject {
    func performFault<EntityID: Equatable, Entity>(
        on keyPath: KeyPath<Self, EntityID>,
        fallback: (EntityID) -> Entity?
    ) -> Entity? {
        let entityID = self[keyPath: keyPath]

        do {
            return try getAssociatedValue(with: keyPath)
        } catch {
            CWLogInfo("Failed to fetch \(keyPath) in batch")
        }

        return fallback(entityID)
    }

    func performFault<EntityID: Equatable, Entity>(
        on keyPath: KeyPath<Self, EntityID?>,
        fallback: (EntityID) -> Entity?
    ) -> Entity? {
        guard let entityID = self[keyPath: keyPath] else {
            return nil
        }

        do {
            return try getAssociatedValue(with: keyPath)
        } catch {
            CWLogInfo("Failed to fetch \(keyPath) in batch")
        }

        return fallback(entityID)
    }
}

// MARK: - Raw Entity ID Arrays

public extension FetchableObjectProtocol where Self: NSObject {
    func performFault<EntityID: Equatable, Entity>(
        on keyPath: KeyPath<Self, [EntityID]>,
        fallback: ([EntityID]) -> [Entity]?
    ) -> [Entity]? {
        let entityID = self[keyPath: keyPath]
        guard !entityID.isEmpty else {
            return []
        }

        do {
            return try getAssociatedValue(with: keyPath)
        } catch {
            CWLogInfo("Failed to fetch \(keyPath) in batch")
        }

        return fallback(entityID)
    }

    func performFault<EntityID: Equatable, Entity>(
        on keyPath: KeyPath<Self, [EntityID]?>,
        fallback: ([EntityID]) -> [Entity]?
    ) -> [Entity]? {
        guard let entityID = self[keyPath: keyPath] else {
            return nil
        }

        guard !entityID.isEmpty else {
            return []
        }

        do {
            return try getAssociatedValue(with: keyPath)
        } catch {
            CWLogInfo("Failed to fetch \(keyPath) in batch")
        }

        return fallback(entityID)
    }
}

private extension Array where Element == NSSortDescriptor {
    func finalize<FetchedObject: FetchableObject>(
        with sectionNameKeyPath: KeyPath<FetchedObject, String>?
    ) -> Self {
        var sortDescriptors = self

        if let sectionNameKeyPath = sectionNameKeyPath {
            assert(sectionNameKeyPath._kvcKeyPathString != nil, "\(sectionNameKeyPath) is not KVC compliant?")

            // Make sure we have our section name included if appropriate
            let sectionNameDescriptor = NSSortDescriptor(
                keyPath: sectionNameKeyPath,
                ascending: true,
                comparator: { lhs, rhs in
                    let lhs = lhs as? String ?? ""
                    let rhs = rhs as? String ?? ""
                    return lhs.localizedStandardCompare(rhs)
                }
            )
            sortDescriptors.insert(sectionNameDescriptor, at: 0)
        }

        if FetchedObject.instancesRespond(to: Selector(("id"))) {
            let idDescriptor = NSSortDescriptor(key: "id", ascending: true)
            sortDescriptors.append(idDescriptor)
        } else {
            let idDescriptor = NSSortDescriptor(key: "self", ascending: true) { lhs, rhs in
                guard let lhs = lhs as? FetchedObject, let rhs = rhs as? FetchedObject else {
                    return .orderedSame
                }
                if lhs.id < rhs.id {
                    return .orderedAscending
                } else if lhs.id > rhs.id {
                    return .orderedDescending
                } else {
                    return .orderedSame
                }
            }
            sortDescriptors.append(idDescriptor)
        }

        return sortDescriptors
    }
}
