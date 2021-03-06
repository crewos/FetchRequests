//
//  PaginatingFetchRequest.swift
//  FetchRequests-iOS
//
//  Created by Adam Lickel on 2/28/18.
//  Copyright © 2018 Speramus Inc. All rights reserved.
//

import Foundation

public class PaginatingFetchRequest<FetchedObject: FetchableObject>: FetchRequest<FetchedObject> {
    public typealias PaginationRequest = (
        _ currentResults: [FetchedObject],
        _ completion: @escaping ([FetchedObject]?) -> Void
    ) -> Void

    internal let paginationRequest: PaginationRequest

    public init<VoidToken: ObservableToken, DataToken: ObservableToken>(
        request: @escaping Request,
        paginationRequest: @escaping PaginationRequest,
        objectCreationToken: DataToken,
        creationInclusionCheck: @escaping CreationInclusionCheck = { _ in true },
        associations: [FetchRequestAssociation<FetchedObject>] = [],
        dataResetTokens: [VoidToken] = []
    ) where VoidToken.Parameter == Void, DataToken.Parameter == FetchedObject.RawData {
        self.paginationRequest = paginationRequest
        super.init(
            request: request,
            objectCreationToken: objectCreationToken,
            creationInclusionCheck: creationInclusionCheck,
            associations: associations,
            dataResetTokens: dataResetTokens
        )
    }

    fileprivate func performPagination<Controller>(in fetchController: Controller) where Controller: InternalFetchResultsControllerProtocol, Controller.FetchedObject == FetchedObject {
        let currentResults = fetchController.fetchedObjects
        paginationRequest(currentResults) { [weak fetchController] pageResults in
            guard let pageResults = pageResults else {
                return
            }
            fetchController?.manuallyInsert(objects: pageResults, emitChanges: true)
        }
    }
}

public class PaginatingFetchedResultsController<
    FetchedObject: FetchableObject
>: FetchedResultsController<FetchedObject> {
    private unowned let paginatingRequest: PaginatingFetchRequest<FetchedObject>

    public init(
        request: PaginatingFetchRequest<FetchedObject>,
        sortDescriptors: [NSSortDescriptor] = [],
        sectionNameKeyPath: SectionNameKeyPath? = nil,
        debounceInsertsAndReloads: Bool = true
    ) {
        paginatingRequest = request

        super.init(
            request: request,
            sortDescriptors: sortDescriptors,
            sectionNameKeyPath: sectionNameKeyPath,
            debounceInsertsAndReloads: debounceInsertsAndReloads
        )
    }

    public func performPagination() {
        paginatingRequest.performPagination(in: self)
    }
}

public class PausablePaginatingFetchedResultsController<
    FetchedObject: FetchableObject
>: PausableFetchedResultsController<FetchedObject> {
    private unowned let paginatingRequest: PaginatingFetchRequest<FetchedObject>
    
    public init(
        request: PaginatingFetchRequest<FetchedObject>,
        sortDescriptors: [NSSortDescriptor] = [],
        sectionNameKeyPath: SectionNameKeyPath? = nil,
        debounceInsertsAndReloads: Bool = true
    ) {
        paginatingRequest = request
        
        super.init(
            request: request,
            sortDescriptors: sortDescriptors,
            sectionNameKeyPath: sectionNameKeyPath,
            debounceInsertsAndReloads: debounceInsertsAndReloads
        )
    }
    
    public func performPagination() {
        paginatingRequest.performPagination(in: self)
    }
}
