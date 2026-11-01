import Foundation
import OSLog

public final class SecurityBookmarkManager {
    public static let shared = SecurityBookmarkManager()
    
    private var activeAccessCounts: [URL: (url: URL, count: Int)] = [:]
    private let lock = NSLock()
    
    private init() {}
    
    deinit {
        stopAccessingAll()
    }
    
    /// Creates a security-scoped bookmark from a URL for persistent access across reboots.
    public func createBookmark(for url: URL) -> Data? {
        switch FileValidator.validateVideoURL(url) {
        case .success(let validatedURL):
            do {
                let bookmarkData = try validatedURL.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                return bookmarkData
            } catch {
                AppLogger.security.warning("Failed to create security-scoped bookmark: \(error.localizedDescription, privacy: .public). Falling back to standard bookmark.")
                do {
                    return try validatedURL.bookmarkData(
                        options: [],
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                } catch {
                    AppLogger.security.error("Failed to create standard bookmark fallback: \(error.localizedDescription, privacy: .public)")
                    return nil
                }
            }
        case .failure(let error):
            AppLogger.security.error("File validation failed before bookmark creation: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
    
    /// Resolves bookmark data back to a usable URL and starts security access if needed with balanced tracking.
    public func resolveBookmark(_ data: Data) -> (url: URL, isStale: Bool)? {
        var isStale = false
        var resolvedURL: URL?
        var didStartAccess = false
        
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if url.startAccessingSecurityScopedResource() {
                didStartAccess = true
            }
            resolvedURL = url
        } catch {
            do {
                let url = try URL(
                    resolvingBookmarkData: data,
                    options: [],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                resolvedURL = url
            } catch {
                AppLogger.security.error("Failed to resolve bookmark: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        
        guard let url = resolvedURL else { return nil }
        
        switch FileValidator.validateVideoURL(url) {
        case .success(let validatedURL):
            if didStartAccess {
                lock.lock()
                let key = validatedURL.standardizedFileURL
                if let existing = activeAccessCounts[key] {
                    activeAccessCounts[key] = (existing.url, existing.count + 1)
                } else {
                    activeAccessCounts[key] = (url, 1)
                }
                lock.unlock()
            }
            return (validatedURL, isStale)
            
        case .failure(let error):
            AppLogger.security.error("Resolved bookmark URL failed validation: \(error.localizedDescription, privacy: .public)")
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
            return nil
        }
    }
    
    /// Stops accessing a security scoped resource URL with balanced reference counting.
    public func stopAccessing(url: URL) {
        lock.lock()
        defer { lock.unlock() }
        let key = url.standardizedFileURL
        if let existing = activeAccessCounts[key] {
            existing.url.stopAccessingSecurityScopedResource()
            if existing.count > 1 {
                activeAccessCounts[key] = (existing.url, existing.count - 1)
            } else {
                activeAccessCounts.removeValue(forKey: key)
            }
        }
    }
    
    /// Stops accessing all active security scoped URLs.
    public func stopAccessingAll() {
        lock.lock()
        defer { lock.unlock() }
        for (_, entry) in activeAccessCounts {
            for _ in 0..<entry.count {
                entry.url.stopAccessingSecurityScopedResource()
            }
        }
        activeAccessCounts.removeAll()
    }
    
    /// Returns the active access count for a URL (useful for verification and unit tests).
    public func activeAccessCount(for url: URL) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return activeAccessCounts[url.standardizedFileURL]?.count ?? 0
    }
    
    /// Returns the set of currently active URLs
    public var activeURLs: Set<URL> {
        lock.lock()
        defer { lock.unlock() }
        return Set(activeAccessCounts.keys)
    }
}
