//
//  EntryFilter.swift
//  Antoine
//
//  Created by Serena on 09/12/2022
//

import Foundation

#warning("Add support for making it so that it checks if the entry passes just one of those conditions, rather than all")
/// A Structure defining the filters that can be used to filter out unwanted entries by the user
struct EntryFilter: Codable, Hashable {
    public var messageTextFilter: TextFilter?
    public var processFilter: TextFilter?
    public var subsystemFilter: TextFilter?
    public var categoryFilter: TextFilter?
    public var pid: pid_t?
    
    /// ✅ 新增：按所属 App 的 Bundle ID 过滤（例如 com.apple.Maps / com.tencent.xin）
    public var processBundleID: String?
    
    /// for performance reasons,
    /// (not calling map to the rawValue every single time ``entryPassesFilter(_:)`` is called)
    /// this is a private var which is used in the ``entryPassesFilter(_:)`` function.
    private var _acceptedTypesInternal: [UInt8] = MessageEvent.allCases.map(\.rawValue)
    
    public var acceptedTypes: Set<MessageEvent> {
        didSet {
            _acceptedTypesInternal = acceptedTypes.map(\.rawValue)
        }
    }
    
    init(messageTextFilter: TextFilter? = nil,
         processFilter: TextFilter? = nil,
         subsystemFilter: TextFilter? = nil,
         categoryFilter: TextFilter? = nil,
         pid: pid_t? = nil,
         processBundleID: String? = nil) {
        
        self.messageTextFilter = messageTextFilter
        self.processFilter = processFilter
        self.subsystemFilter = subsystemFilter
        self.categoryFilter = categoryFilter
        self.pid = pid
        self.processBundleID = processBundleID
        
        self.acceptedTypes = Set(_acceptedTypesInternal.compactMap(MessageEvent.init))
    }
    
    /// Check if a given entry passes the current filter
    public func entryPassesFilter(_ entry: StreamEntry) -> Bool {
        return (messageTextFilter?.matches(entry.eventMessage) ?? true)
        && (subsystemFilter?.matches(entry.subsystem) ?? true)
        && (categoryFilter?.matches(entry.category) ?? true)
        && (processFilter?.matches(entry.process) ?? true)
        && _acceptedTypesInternal.contains(entry.messageType)
        && isPidEqualTo(entry.processID)
        && isBundleIDEqualTo(bundleIDFromProcessPath(entry.processImagePath))
    }
    
    // if pid is nil, then it'll be considered true in entryPassesFilter anyways
    private func isPidEqualTo(_ otherPid: pid_t) -> Bool {
        return pid == nil ? true : pid == otherPid
    }
    
    // if processBundleID is nil/empty, then it'll be considered true in entryPassesFilter anyways
    private func isBundleIDEqualTo(_ otherBundleID: String?) -> Bool {
        guard let want = processBundleID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !want.isEmpty else { return true }
        return otherBundleID == want
    }
}

// MARK: - BundleID lookup (cached)
// 通过进程可执行文件路径向上找 .app，然后读 CFBundleIdentifier
private enum BundleIDLookup {
    static var cache: [String: String?] = [:]   // key: processImagePath
    static let lock = NSLock()
}

private func bundleIDFromProcessPath(_ processImagePath: String) -> String? {
    // 缓存命中
    BundleIDLookup.lock.lock()
    if let hit = BundleIDLookup.cache[processImagePath] {
        BundleIDLookup.lock.unlock()
        return hit
    }
    BundleIDLookup.lock.unlock()
    
    var url = URL(fileURLWithPath: processImagePath)
    url.deleteLastPathComponent()
    
    var appURL: URL?
    for _ in 0..<10 {
        if url.pathExtension.lowercased() == "app" {
            appURL = url
            break
        }
        let parent = url.deletingLastPathComponent()
        if parent.path == url.path { break }
        url = parent
    }
    
    let bundleID: String?
    if let appURL, let bundle = Bundle(url: appURL) {
        bundleID = bundle.bundleIdentifier
    } else {
        bundleID = nil
    }
    
    BundleIDLookup.lock.lock()
    BundleIDLookup.cache[processImagePath] = bundleID
    BundleIDLookup.lock.unlock()
    
    return bundleID
}
