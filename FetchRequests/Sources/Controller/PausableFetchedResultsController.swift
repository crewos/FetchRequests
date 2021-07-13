//
//  PausableFetchedResultsController.swift
//  Crew
//
//  Created by Adam Lickel on 4/5/17.
//  Copyright © 2017 Speramus Inc. All rights reserved.
//

import Foundation
import Combine

public protocol PausableFetchedResultsControllerDelegate: AnyObject {
    associatedtype FetchedObject: FetchableObject

    func controllerWillChangeContent(_ controller: PausableFetchedResultsController<FetchedObject>)
    func controllerDidChangeContent(_ controller: PausableFetchedResultsController<FetchedObject>)

    func controller(
        _ controller: PausableFetchedResultsController<FetchedObject>,
        didChange object: FetchedObject,
        for change: FetchedResultsChange<IndexPath>
    )
    func controller(
        _ controller: PausableFetchedResultsController<FetchedObject>,
        didChange section: FetchedResultsSection<FetchedObject>,
        for change: FetchedResultsChange<Int>
    )
}

public extension PausableFetchedResultsControllerDelegate {
    func controllerWillChangeContent(_ controller: PausableFetchedResultsController<FetchedObject>) {}
    func controllerDidChangeContent(_ controller: PausableFetchedResultsController<FetchedObject>) {}

    func controller(
        _ controller: PausableFetchedResultsController<FetchedObject>,
        didChange object: FetchedObject,
        for change: FetchedResultsChange<IndexPath>
    ) {
    }

    func controller(
        _ controller: PausableFetchedResultsController<FetchedObject>,
        didChange section: FetchedResultsSection<FetchedObject>,
        for change: FetchedResultsChange<Int>
    ) {
    }
}

public class PausableFetchedResultsController<FetchedObject: FetchableObject> {
    private let controller: FetchedResultsController<FetchedObject>

    public typealias Section = FetchedResultsSection<FetchedObject>
    public typealias SectionNameKeyPath = KeyPath<FetchedObject, String>

    private var hasFetchedObjectsSnapshot: Bool?
    private var fetchedObjectsSnapshot: [FetchedObject]?
    private var sectionsSnapshot: [Section]?

    fileprivate let objectWillChangeSubject = PassthroughSubject<Void, Never>()
    fileprivate let objectDidChangeSubject = PassthroughSubject<Void, Never>()

    public private(set) lazy var objectWillChange = objectWillChangeSubject.eraseToAnyPublisher()
    public private(set) lazy var objectDidChange = objectDidChangeSubject.eraseToAnyPublisher()

    /// Pause all eventing and return a snapshot of the value
    ///
    /// Pausing and unpausing will never trigger the delegate. While paused, the delegate will not fire for any reason.
    /// If you depend upon your delegate for eventing, you will need to reload any dependencies manually.
    /// The Publishers will trigger whenever the value of isPaused changes.
    public var isPaused: Bool = false {
        didSet {
            guard oldValue != isPaused else {
                return
            }

            objectWillChangeSubject.send()

            if isPaused {
                hasFetchedObjectsSnapshot = controller.hasFetchedObjects
                sectionsSnapshot = controller.sections
                fetchedObjectsSnapshot = controller.fetchedObjects
            } else {
                hasFetchedObjectsSnapshot = nil
                sectionsSnapshot = nil
                fetchedObjectsSnapshot = nil
            }

            objectDidChangeSubject.send()
        }
    }

    // swiftlint:disable:next weak_delegate
    private var delegate: PausableFetchResultsDelegate<FetchedObject>?

    public init(
        request: FetchRequest<FetchedObject>,
        sortDescriptors: [NSSortDescriptor] = [],
        sectionNameKeyPath: SectionNameKeyPath? = nil,
        debounceInsertsAndReloads: Bool = true
    ) {
        controller = FetchedResultsController(
            request: request,
            sortDescriptors: sortDescriptors,
            sectionNameKeyPath: sectionNameKeyPath,
            debounceInsertsAndReloads: debounceInsertsAndReloads
        )
    }
}

// MARK: - Wrapper Functions

extension PausableFetchedResultsController: FetchedResultsControllerProtocol {
    public func performFetch(completion: @escaping () -> Void) {
        controller.performFetch(completion: completion)
    }

    public func resort(using newSortDescriptors: [NSSortDescriptor], completion: @escaping () -> Void) {
        controller.resort(using: newSortDescriptors, completion: completion)
    }

    public func reset() {
        controller.reset()
        isPaused = false
    }

    public var request: FetchRequest<FetchedObject> {
        return controller.request
    }

    public var sortDescriptors: [NSSortDescriptor] {
        return controller.sortDescriptors
    }

    public var sectionNameKeyPath: SectionNameKeyPath? {
        return controller.sectionNameKeyPath
    }

    public var associatedFetchSize: Int {
        get {
            return controller.associatedFetchSize
        }
        set {
            controller.associatedFetchSize = newValue
        }
    }

    public var hasFetchedObjects: Bool {
        return hasFetchedObjectsSnapshot ?? controller.hasFetchedObjects
    }

    public var fetchedObjects: [FetchedObject] {
        return fetchedObjectsSnapshot ?? controller.fetchedObjects
    }

    public var sections: [Section] {
        return sectionsSnapshot ?? controller.sections
    }

    public func setDelegate<Delegate: PausableFetchedResultsControllerDelegate>(_ delegate: Delegate?) where Delegate.FetchedObject == FetchedObject {
        self.delegate = delegate.flatMap {
            PausableFetchResultsDelegate($0, pausableController: self)
        }
        controller.setDelegate(self.delegate)
    }

    public func clearDelegate() {
        self.delegate = nil
        controller.clearDelegate()
    }
}

// MARK: - InternalFetchResultsControllerProtocol

extension PausableFetchedResultsController: InternalFetchResultsControllerProtocol {
    internal func manuallyInsert(objects: [FetchedObject], emitChanges: Bool = true) {
        controller.manuallyInsert(objects: objects, emitChanges: emitChanges)
    }
}

// MARK: - PausableFetchResultsDelegate

internal class PausableFetchResultsDelegate<FetchedObject: FetchableObject>: FetchedResultsControllerDelegate {
    typealias ParentController = FetchedResultsController<FetchedObject>
    typealias PausableController = PausableFetchedResultsController<FetchedObject>
    typealias Section = FetchedResultsSection<FetchedObject>

    private weak var pausableController: PausableController?

    private let willChange: (_ controller: PausableController) -> Void
    private let didChange: (_ controller: PausableController) -> Void

    private let changeObject: (_ controller: PausableController, _ object: FetchedObject, _ change: FetchedResultsChange<IndexPath>) -> Void
    private let changeSection: (_ controller: PausableController, _ section: Section, _ change: FetchedResultsChange<Int>) -> Void

    init<Parent: PausableFetchedResultsControllerDelegate>(
        _ parent: Parent,
        pausableController: PausableController
    ) where Parent.FetchedObject == FetchedObject {
        self.pausableController = pausableController

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

    func controllerWillChangeContent(_ controller: ParentController) {
        guard let pausableController = pausableController, !pausableController.isPaused else {
            return
        }
        pausableController.objectWillChangeSubject.send()
        self.willChange(pausableController)
    }

    func controllerDidChangeContent(_ controller: ParentController) {
        guard let pausableController = pausableController, !pausableController.isPaused else {
            return
        }
        self.didChange(pausableController)
        pausableController.objectDidChangeSubject.send()
    }

    func controller(
        _ controller: ParentController,
        didChange object: FetchedObject,
        for change: FetchedResultsChange<IndexPath>
    ) {
        guard let pausableController = pausableController, !pausableController.isPaused else {
            return
        }
        self.changeObject(pausableController, object, change)
    }

    func controller(
        _ controller: ParentController,
        didChange section: Section,
        for change: FetchedResultsChange<Int>
    ) {
        guard let pausableController = pausableController, !pausableController.isPaused else {
            return
        }
        self.changeSection(pausableController, section, change)
    }
}
