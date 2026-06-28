//
//  RefreshGroup.swift
//  AltStore
//
//  Created by Riley Testut on 6/20/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import CoreData
import AltStoreCore
import AltSign

final class RefreshGroup: NSObject
{
    let context: AuthenticatedOperationContext
    let progress = Progress.discreteProgress(totalUnitCount: 0)
    
    var completionHandler: (([String: Result<InstalledApp, Error>]) -> Void)?
    var beginInstallationHandler: ((InstalledApp) -> Void)?
        
    private(set) var results = [String: Result<InstalledApp, Error>]()
    
    // Keep strong references to managed object contexts
    // so they don't die out from under us.
    private(set) var _contexts = Set<NSManagedObjectContext>()
    
    private var isFinished = false
    
    // Tracks the number of pending finish() calls expected in a batch operation.
    // The idle timer is only re-enabled when this reaches 0.
    private(set) var pendingFinishCount: Int = 0

    private let dispatchGroup = DispatchGroup()
    private var operations: [Foundation.Operation] = []
    
    init(context: AuthenticatedOperationContext = AuthenticatedOperationContext())
    {
        self.context = context
        
        super.init()
    }
    
    /// Used to keep track of which operations belong to this group.
    /// This does _not_ add them to any operation queue.
    func add(_ operations: [Foundation.Operation])
    {
        for operation in operations
        {
            self.dispatchGroup.enter()
            
            operation.completionBlock = { [weak self] in
                self?.dispatchGroup.leave()
            }
        }
        
        if self.operations.isEmpty && !operations.isEmpty
        {
            self.dispatchGroup.notify(queue: .global()) { [weak self] in
                self?.finish()
            }
        }
        
        self.operations.append(contentsOf: operations)
    }
    
    func set(_ result: Result<InstalledApp, Error>, forAppWithBundleIdentifier bundleIdentifier: String)
    {
        self.results[bundleIdentifier] = result
        
        switch result
        {
        case .failure: break
        case .success(let installedApp):
            guard let context = installedApp.managedObjectContext else { break }
            self._contexts.insert(context)
        }
    }
    
    func cancel()
    {
        self.operations.forEach { $0.cancel() }
    }

    /// Decrements the pending finish count. Returns `true` when all expected
    /// finish() calls have been received (i.e., the batch is complete).
    @discardableResult
    func decrementPendingFinishCount() -> Bool
    {
        self.pendingFinishCount = max(0, self.pendingFinishCount - 1)
        return self.pendingFinishCount == 0
    }
}

private extension RefreshGroup
{
    func finish()
    {
        guard !self.isFinished else { return }
        self.isFinished = true
        
        self.completionHandler?(self.results)
    }
}
