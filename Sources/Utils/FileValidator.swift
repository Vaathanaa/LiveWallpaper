import Foundation
import UniformTypeIdentifiers
import OSLog

public enum FileValidationError: LocalizedError, Equatable {
    case notAFileURL
    case pathTraversalAttempt
    case isSymbolicLink
    case notARegularFile
    case fileDoesNotExist
    case unsupportedContentType(String)
    
    public var errorDescription: String? {
        switch self {
        case .notAFileURL:
            return "The selected URL is not a local file URL."
        case .pathTraversalAttempt:
            return "The file path contains invalid path traversal components."
        case .isSymbolicLink:
            return "Symbolic links are not permitted for wallpaper media."
        case .notARegularFile:
            return "The selected path is not a regular file."
        case .fileDoesNotExist:
            return "The video file does not exist or is not readable."
        case .unsupportedContentType(let type):
            return "The file type '\(type)' is not a supported video format (.mp4, .mov, .m4v)."
        }
    }
}

public enum FileValidator {
    public static let supportedVideoTypes: [UTType] = [
        .movie,
        .video,
        .mpeg4Movie,
        .quickTimeMovie
    ]
    
    public static func validateVideoURL(_ url: URL) -> Result<URL, FileValidationError> {
        // 1. Must be a file URL
        guard url.isFileURL else {
            AppLogger.security.error("Validation rejected non-file URL: \(url.absoluteString, privacy: .private(mask: .hash))")
            return .failure(.notAFileURL)
        }
        
        let path = url.path
        
        // 2. Reject path traversal attempts
        let lowerString = url.absoluteString.lowercased()
        if lowerString.contains("%2e%2e") || lowerString.contains("%2f..") || lowerString.contains("..%2f") {
            AppLogger.security.error("Validation rejected encoded path traversal: \(path, privacy: .private(mask: .hash))")
            return .failure(.pathTraversalAttempt)
        }
        
        if url.pathComponents.contains("..") || path.contains("/../") || path.hasSuffix("/..") || path.hasPrefix("../") || path.contains("/./") {
            AppLogger.security.error("Validation rejected path traversal attempt: \(path, privacy: .private(mask: .hash))")
            return .failure(.pathTraversalAttempt)
        }
        
        let standardizedURL = url.standardizedFileURL
        let standardizedPath = standardizedURL.path
        
        if standardizedURL.pathComponents.contains("..") || standardizedPath.contains("/../") {
            AppLogger.security.error("Validation rejected standardized path traversal: \(standardizedPath, privacy: .private(mask: .hash))")
            return .failure(.pathTraversalAttempt)
        }
        
        // 3. Reject symlinks using resource values and lstat
        var isSymlink = false
        if let resourceValues = try? standardizedURL.resourceValues(forKeys: [.isSymbolicLinkKey]),
           resourceValues.isSymbolicLink == true {
            isSymlink = true
        }
        
        var statInfo = stat()
        if lstat(standardizedPath, &statInfo) == 0 {
            if (statInfo.st_mode & S_IFMT) == S_IFLNK {
                isSymlink = true
            }
        }
        
        if isSymlink {
            AppLogger.security.error("Validation rejected symbolic link URL: \(standardizedPath, privacy: .private(mask: .hash))")
            return .failure(.isSymbolicLink)
        }
        
        // 4. Must exist and be a regular file
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardizedPath, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            AppLogger.security.error("Validation rejected non-existent or directory file: \(standardizedPath, privacy: .private(mask: .hash))")
            return .failure(.fileDoesNotExist)
        }
        
        if stat(standardizedPath, &statInfo) == 0 {
            guard (statInfo.st_mode & S_IFMT) == S_IFREG else {
                AppLogger.security.error("Validation rejected non-regular file: \(standardizedPath, privacy: .private(mask: .hash))")
                return .failure(.notARegularFile)
            }
        }
        
        // 5. Verify Uniform Type Identifier
        var resolvedType: UTType?
        if let resourceValues = try? standardizedURL.resourceValues(forKeys: [.contentTypeKey]),
           let contentType = resourceValues.contentType {
            resolvedType = contentType
        } else {
            let ext = standardizedURL.pathExtension
            if !ext.isEmpty {
                resolvedType = UTType(filenameExtension: ext)
            }
        }
        
        guard let contentType = resolvedType else {
            AppLogger.security.error("Unable to determine UTType for file: \(standardizedPath, privacy: .private(mask: .hash))")
            return .failure(.unsupportedContentType("Unknown"))
        }
        
        let conforms = supportedVideoTypes.contains { contentType.conforms(to: $0) }
        guard conforms else {
            AppLogger.security.error("Validation rejected unsupported content type '\(contentType.identifier)' for: \(standardizedPath, privacy: .private(mask: .hash))")
            return .failure(.unsupportedContentType(contentType.identifier))
        }
        
        return .success(standardizedURL)
    }
    
    /// Scans a directory and returns all validated video URLs found within it
    public static func validateFolder(url: URL) -> [URL] {
        guard url.isFileURL else { return [] }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return []
        }
        guard let files = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.contentTypeKey, .isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return []
        }
        
        return files.compactMap { file in
            if case .success(let validURL) = validateVideoURL(file) {
                return validURL
            }
            return nil
        }
    }
}
