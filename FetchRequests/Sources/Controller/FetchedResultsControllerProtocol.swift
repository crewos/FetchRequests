//
//  FetchedResultsControllerProtocol.swift
//  Crew
//
//  Created by Adam Lickel on 4/5/17.
//  Copyright © 2017 Speramus Inc. All rights reserved.
//

import Foundation
import Combine

internal protocol InternalFetchResultsControllerProtocol: FetchedResultsControllerProtocol {
    func manuallyInsert(objects: [FetchedObject], emitChanges: Bool)
}

public protocol DoublyObservableObject: ObservableObject {
    associatedtype ObjectDidChangePublisher: Publisher where ObjectWillChangePublisher.Output == ObjectDidChangePublisher.Output, ObjectWillChangePublisher.Failure == ObjectDidChangePublisher.Failure

    var objectDidChange: ObjectDidChangePublisher { get }
}

public protocol FetchedResultsControllerProtocol: DoublyObservableObject {
    associatedtype FetchedObject: FetchableObject
    typealias SectionNameKeyPath = KeyPath<FetchedObject, String>
    typealias Section = FetchedResultsSection<FetchedObject>

    var request: FetchRequest<FetchedObject> { get }

    var hasFetchedObjects: Bool { get }
    var sections: [Section] { get }
    var fetchedObjects: [FetchedObject] { get }

    var associatedFetchSize: Int { get set }

    var sortDescriptors: [NSSortDescriptor] { get }
    var sectionNameKeyPath: SectionNameKeyPath? { get }

    func performFetch(completion: @escaping () -> Void)
    func resort(using newSortDescriptors: [NSSortDescriptor], completion: @escaping () -> Void)
    func reset()

    func indexPath(for object: FetchedObject) -> IndexPath?
}

// MARK: - Index Paths

public extension FetchedResultsControllerProtocol {
    func performFetch() {
        performFetch(completion: {})
    }

    func resort(using newSortDescriptors: [NSSortDescriptor]) {
        resort(using: newSortDescriptors, completion: {})
    }

    internal func idealSectionIndex(forSectionName name: String) -> Int {
        guard let descriptor = sortDescriptors.first else {
            return 0
        }

        return sections.binarySearch {
            if descriptor.ascending {
                return $0.name < name
            } else {
                return $0.name > name
            }
        }
    }

    internal func idealObjectIndex(for object: FetchedObject, inArray array: [FetchedObject]) -> Int {
        guard !sortDescriptors.isEmpty else {
            return array.endIndex
        }

        let comparator = sortDescriptors.comparator
        return array.binarySearch {
            return comparator($0, object) == .orderedAscending
        }
    }

    func object(at indexPath: IndexPath) -> FetchedObject {
        return sections[indexPath.section].objects[indexPath.item]
    }

    func indexPath(for object: FetchedObject) -> IndexPath? {
        guard !sections.isEmpty else {
            return nil
        }

        let sectionName = object.sectionName(forKeyPath: sectionNameKeyPath)
        let sectionIndex = idealSectionIndex(forSectionName: sectionName)

        guard sectionIndex < sections.count else {
            return nil
        }
        guard let itemIndex = sections[sectionIndex].objects.firstIndex(of: object) else {
            return nil
        }

        return IndexPath(item: itemIndex, section: sectionIndex)
    }

    func indexPath(forObjectMatching matching: (FetchedObject) -> Bool) -> IndexPath? {
        for object in fetchedObjects where matching(object) {
            return indexPath(for: object)
        }
        return nil
    }

    internal func fetchIndex(for indexPath: IndexPath) -> Int? {
        guard !sections.isEmpty else {
            return nil
        }

        let sectionPrefix = sections[0..<indexPath.section].reduce(0) { $0 + $1.numberOfObjects }

        return sectionPrefix + indexPath.item
    }

    internal func indexPath(forFetchIndex fetchIndex: Int) -> IndexPath? {
        guard !sections.isEmpty, fetchIndex < fetchedObjects.count else {
            return nil
        }

        var sectionIndex = 0
        var objectIndex = fetchIndex

        while sectionIndex < sections.count {
            defer {
                sectionIndex += 1
            }

            let section = sections[sectionIndex]
            guard objectIndex >= section.numberOfObjects else {
                return IndexPath(item: objectIndex, section: sectionIndex)
            }

            objectIndex -= section.numberOfObjects
        }

        return nil
    }
}

// MARK: - Index Path Convenience methods

public extension FetchedResultsControllerProtocol {
    func getIndexPath(before indexPath: IndexPath) -> IndexPath? {
        guard 0..<sections.count ~= indexPath.section else {
            return nil
        }

        var section = indexPath.section
        var item = indexPath.item - 1
        guard item < 0 else {
            return IndexPath(item: item, section: section)
        }

        section -= 1
        guard section >= 0 else {
            return nil
        }

        item = sections[section].numberOfObjects - 1

        return IndexPath(item: item, section: section)
    }

    func getIndexPath(after indexPath: IndexPath) -> IndexPath? {
        guard 0..<sections.count ~= indexPath.section else {
            return nil
        }

        var section = indexPath.section
        var item = indexPath.item + 1
        guard item == sections[section].numberOfObjects else {
            return IndexPath(item: item, section: section)
        }

        section += 1
        item = 0

        if section == sections.count {
            return nil
        } else {
            return IndexPath(item: item, section: section)
        }
    }
}

// MARK: - Binary Search

extension RandomAccessCollection where Index: Strideable {
    func binarySearch(matching: (Iterator.Element) -> Bool) -> Self.Index {
        var lowerIndex = startIndex
        var upperIndex = endIndex

        while lowerIndex != upperIndex {
            let middleIndex = index(lowerIndex, offsetBy: distance(from: lowerIndex, to: upperIndex) / 2)
            if matching(self[middleIndex]) {
                lowerIndex = index(after: middleIndex)
            } else {
                upperIndex = middleIndex
            }
        }
        return lowerIndex
    }
}

// MARK: - Section Names

extension FetchableObjectProtocol where Self: NSObject {
    func sectionName(forKeyPath keyPath: KeyPath<Self, String>?) -> String {
        guard let keyPath = keyPath else {
            return ""
        }
        return self[keyPath: keyPath]
    }
}
