import Foundation

public final class SecurityBookmarkManager {
    public static let shared = SecurityBookmarkManager()
    
    private init() {}
    
    /// Creates a security-scoped bookmark from a URL for persistent access across reboots.
    public func createBookmark(for url: URL) -> Data? {
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            return bookmarkData
        } catch {
            NSLog("[SecurityBookmarkManager] Warning: failed to create security-scoped bookmark: \(error.localizedDescription). Falling back to standard bookmark.")
            do {
                return try url.bookmarkData(
                    options: [],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            } catch {
                NSLog("[SecurityBookmarkManager] Error: failed to create any bookmark: \(error.localizedDescription)")
                return nil
            }
        }
    }
    
    /// Resolves bookmark data back to a usable URL and starts security access if needed.
    public func resolveBookmark(_ data: Data) -> (url: URL, isStale: Bool)? {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if url.startAccessingSecurityScopedResource() {
                // Successfully started accessing security scoped resource
            }
            return (url, isStale)
        } catch {
            do {
                let url = try URL(
                    resolvingBookmarkData: data,
                    options: [],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                return (url, isStale)
            } catch {
                NSLog("[SecurityBookmarkManager] Failed to resolve bookmark: \(error.localizedDescription)")
                return nil
            }
        }
    }
    
    /// Stops accessing a security scoped resource URL.
    public func stopAccessing(url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}
