import Foundation

/// Utility for converting project paths to stable UUIDs for auto-reply settings
@available(iOS 16.0, macOS 13.0, *)
public struct ProjectUUIDConverter {
    /// Convert a project to a stable UUID for settings storage
    public static func uuid(for project: Project) -> UUID {
        return uuid(for: project.path)
    }
    
    /// Convert a project path to a stable UUID for settings storage
    public static func uuid(for projectPath: String) -> UUID {
        // Create a stable UUID based on the project path using a simple deterministic method
        // We use the string hash and create a namespace UUID
        
        let pathHash = abs(projectPath.hashValue)
        
        // Create UUID bytes from the hash
        var uuidBytes: [UInt8] = []
        var hash = pathHash
        
        // Fill 16 bytes for UUID from the hash
        for _ in 0..<4 {
            uuidBytes.append(UInt8(hash & 0xFF))
            uuidBytes.append(UInt8((hash >> 8) & 0xFF))
            uuidBytes.append(UInt8((hash >> 16) & 0xFF))
            uuidBytes.append(UInt8((hash >> 24) & 0xFF))
            // Mix the hash for next 4 bytes
            hash = hash.multipliedReportingOverflow(by: 31).partialValue &+ pathHash
        }
        
        // Set UUID version and variant bits
        uuidBytes[6] = (uuidBytes[6] & 0x0F) | 0x40  // Version 4
        uuidBytes[8] = (uuidBytes[8] & 0x3F) | 0x80  // Variant bits
        
        return UUID(uuid: (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        ))
    }
}
