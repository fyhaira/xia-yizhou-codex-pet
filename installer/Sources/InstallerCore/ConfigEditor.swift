import Foundation

public enum CodexConfigEditor {
    public static func selectedAvatar(in text: String) throws -> String? {
        var inTopLevel = true
        var values: [String] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw), trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") { inTopLevel = false; continue }
            if !inTopLevel || trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let equal = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<equal].trimmingCharacters(in: .whitespaces)
            if key != "selected-avatar-id" { continue }
            let valueAndComment = trimmed[trimmed.index(after: equal)...]
            let value = valueAndComment.split(separator: "#", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces) ?? ""
            guard value.count >= 2, value.first == "\"", value.last == "\"" else {
                throw InstallerError.message("selected-avatar-id is not a simple quoted TOML string")
            }
            values.append(String(value.dropFirst().dropLast()))
        }
        if values.count > 1 { throw InstallerError.message("Multiple top-level selected-avatar-id keys; refusing to edit") }
        return values.first
    }

    public static func settingSelectedAvatar(_ id: String, in text: String) throws -> String {
        guard id.range(of: #"^[A-Za-z0-9:_-]+$"#, options: .regularExpression) != nil else {
            throw InstallerError.message("Invalid avatar id")
        }
        _ = try selectedAvatar(in: text)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var inTopLevel = true, replaced = false, firstTable: Int?
        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                inTopLevel = false
                if firstTable == nil { firstTable = index }
                continue
            }
            guard inTopLevel, !trimmed.hasPrefix("#"), let equal = trimmed.firstIndex(of: "=") else { continue }
            if trimmed[..<equal].trimmingCharacters(in: .whitespaces) == "selected-avatar-id" {
                let prefix = String(lines[index].prefix { $0 == " " || $0 == "\t" })
                lines[index] = "\(prefix)selected-avatar-id = \"\(id)\""
                replaced = true
            }
        }
        if !replaced { lines.insert("selected-avatar-id = \"\(id)\"", at: firstTable ?? lines.endIndex) }
        let output = lines.joined(separator: "\n")
        guard try selectedAvatar(in: output) == id else { throw InstallerError.message("Config selection verification failed") }
        return output
    }

    public static func effectiveSelectedAvatar(in text: String) throws -> String? {
        try value(for: "selected-avatar-id", inSection: "desktop", text: text)
    }

    public static func settingEffectiveSelectedAvatar(_ id: String, in text: String) throws -> String {
        guard id.range(of: #"^[A-Za-z0-9:_-]+$"#, options: .regularExpression) != nil else {
            throw InstallerError.message("Invalid avatar id")
        }
        return try settingValue(id, for: "selected-avatar-id", inSection: "desktop", text: text)
    }

    public static func restoringEffectiveSelectedAvatar(_ id: String?, in text: String) throws -> String {
        if let id { return try settingEffectiveSelectedAvatar(id, in: text) }
        return try removingValue(for: "selected-avatar-id", inSection: "desktop", text: text)
    }

    private static func value(for key: String, inSection section: String, text: String) throws -> String? {
        var currentSection: String?
        var values: [String] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = String(raw).trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentSection = String(trimmed.dropFirst().dropLast())
                continue
            }
            guard currentSection == section, !trimmed.isEmpty, !trimmed.hasPrefix("#"), let equal = trimmed.firstIndex(of: "=") else { continue }
            guard trimmed[..<equal].trimmingCharacters(in: .whitespaces) == key else { continue }
            let rawValue = trimmed[trimmed.index(after: equal)...].split(separator: "#", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces) ?? ""
            guard rawValue.count >= 2, rawValue.first == "\"", rawValue.last == "\"" else {
                throw InstallerError.message("[\(section)].\(key) is not a simple quoted TOML string")
            }
            values.append(String(rawValue.dropFirst().dropLast()))
        }
        if values.count > 1 { throw InstallerError.message("Multiple [\(section)].\(key) keys; refusing to edit") }
        return values.first
    }

    private static func settingValue(_ value: String, for key: String, inSection section: String, text: String) throws -> String {
        _ = try self.value(for: key, inSection: section, text: text)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var sectionStart: Int?, sectionEnd: Int?, currentSection: String?, replaced = false
        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                if currentSection == section && sectionEnd == nil { sectionEnd = index }
                currentSection = String(trimmed.dropFirst().dropLast())
                if currentSection == section { sectionStart = index }
                continue
            }
            guard currentSection == section, !trimmed.hasPrefix("#"), let equal = trimmed.firstIndex(of: "=") else { continue }
            if trimmed[..<equal].trimmingCharacters(in: .whitespaces) == key {
                let prefix = String(lines[index].prefix { $0 == " " || $0 == "\t" })
                lines[index] = "\(prefix)\(key) = \"\(value)\""
                replaced = true
            }
        }
        if !replaced {
            if sectionStart != nil { lines.insert("\(key) = \"\(value)\"", at: sectionEnd ?? lines.endIndex) }
            else {
                if lines.last?.isEmpty == false { lines.append("") }
                lines.append("[\(section)]")
                lines.append("\(key) = \"\(value)\"")
            }
        }
        let output = lines.joined(separator: "\n")
        guard try self.value(for: key, inSection: section, text: output) == value else { throw InstallerError.message("Effective config selection verification failed") }
        return output
    }

    private static func removingValue(for key: String, inSection section: String, text: String) throws -> String {
        _ = try value(for: key, inSection: section, text: text)
        var currentSection: String?
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") { currentSection = String(trimmed.dropFirst().dropLast()); return true }
            guard currentSection == section, !trimmed.hasPrefix("#"), let equal = trimmed.firstIndex(of: "=") else { return true }
            return trimmed[..<equal].trimmingCharacters(in: .whitespaces) != key
        }
        let output = lines.joined(separator: "\n")
        guard try value(for: key, inSection: section, text: output) == nil else { throw InstallerError.message("Effective config selection removal verification failed") }
        return output
    }

    public static func removingSelectedAvatar(in text: String) throws -> String {
        _ = try selectedAvatar(in: text)
        var inTopLevel = true
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") { inTopLevel = false; return true }
            guard inTopLevel, !trimmed.hasPrefix("#"), let equal = trimmed.firstIndex(of: "=") else { return true }
            return trimmed[..<equal].trimmingCharacters(in: .whitespaces) != "selected-avatar-id"
        }
        let output = lines.joined(separator: "\n")
        guard try selectedAvatar(in: output) == nil else { throw InstallerError.message("Config selection removal verification failed") }
        return output
    }

    public static func writeAtomically(_ text: String, to url: URL) throws {
        try writeDataAtomically(Data(text.utf8), to: url)
    }

    public static func writeDataAtomically(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).prototype-\(UUID().uuidString)")
        try data.write(to: temporary, options: [.atomic])
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } else { try FileManager.default.moveItem(at: temporary, to: url) }
    }
}
