//
//  APIModels.swift
//  CabFit
//
//  Wire types, and the translation between a KitchenRun and what the server stores.
//

import Foundation

// MARK: - DTOs

struct AttachmentDTO: Decodable {
    let attachment_uid: String
    let run_uid: String?
    let slot: String
    let mime: String
    let byte_size: Int
    let sha256: String
}

struct AttachmentListDTO: Decodable {
    let attachments: [AttachmentDTO]
}

struct RunDTO: Decodable {
    let run_uid: String
    let title: String
    let status: String
    let shape: String
    let revision: Int
    let updated_at: String
    let deleted: Bool
    /// Absent for tombstones.
    let payload: JSONValue?
}

struct RunListDTO: Decodable {
    let runs: [RunDTO]
    let cursor: String
    let has_more: Bool
    let server_time: String
}

struct RunWriteDTO: Decodable {
    let run_uid: String
    let revision: Int
    let updated_at: String
}

// MARK: - JSONValue

/// A decoded-but-not-yet-typed JSON tree. The server stores the run payload opaquely,
/// so the client needs to carry it through `Decodable` without knowing its shape.
enum JSONValue: Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let v = try? container.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? container.decode(Double.self) {
            self = .number(v)
        } else if let v = try? container.decode(String.self) {
            self = .string(v)
        } else if let v = try? container.decode([JSONValue].self) {
            self = .array(v)
        } else if let v = try? container.decode([String: JSONValue].self) {
            self = .object(v)
        } else {
            self = .null
        }
    }

    /// Back to a Foundation object, ready for `JSONSerialization`.
    var anyValue: Any {
        switch self {
        case .null:            return NSNull()
        case .bool(let v):     return v
        case .number(let v):   return v
        case .string(let v):   return v
        case .array(let v):    return v.map { $0.anyValue }
        case .object(let v):   return v.mapValues { $0.anyValue }
        }
    }
}

// MARK: - Run ↔ wire

/// Converts between the app's `KitchenRun` and the JSON the server keeps.
///
/// Binaries are pulled out on the way up: a wall photo is a few hundred kilobytes, and
/// sending it inside every run update would make sync unusable on a site connection —
/// and the server refuses oversized strings in a payload for exactly that reason.
enum RunWire {

    /// The binary slots a run can carry, named the way the server expects them.
    struct Binaries {
        var runPhoto: Data?
        var signature: Data?
        var defectPhotos: [String: Data] = [:]   // defect uuid -> jpeg bytes

        var isEmpty: Bool { runPhoto == nil && signature == nil && defectPhotos.isEmpty }

        static func slot(forDefect id: String) -> String { "defect:\(id)" }
        static let runPhotoSlot = "run_photo"
        static let signatureSlot = "signature"
    }

    enum WireError: LocalizedError {
        case encoding
        case decoding
        var errorDescription: String? {
            switch self {
            case .encoding: return "Could not prepare this run for the server."
            case .decoding: return "Could not read this run from the server."
            }
        }
    }

    /// Encode a run, returning the payload the server stores and the binaries to upload.
    static func encode(_ run: KitchenRun) throws -> (payload: [String: Any], binaries: Binaries) {
        let data = try JSONEncoder().encode(run)
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WireError.encoding
        }

        var binaries = Binaries()
        binaries.runPhoto = run.photo
        binaries.signature = run.signature
        object.removeValue(forKey: "photo")
        object.removeValue(forKey: "signature")

        if var defects = object["defects"] as? [[String: Any]] {
            for index in defects.indices {
                if let uid = defects[index]["id"] as? String,
                   let photo = run.defects.first(where: { $0.id.uuidString.lowercased() == uid.lowercased() })?.photo {
                    binaries.defectPhotos[uid.lowercased()] = photo
                }
                defects[index].removeValue(forKey: "photo")
            }
            object["defects"] = defects
        }

        return (object, binaries)
    }

    /// Rebuild a run from a server payload. Binaries arrive separately and are grafted
    /// back on by the sync engine once downloaded.
    static func decode(_ payload: [String: Any]) throws -> KitchenRun {
        let data = try JSONSerialization.data(withJSONObject: payload)
        do {
            return try JSONDecoder().decode(KitchenRun.self, from: data)
        } catch {
            throw WireError.decoding
        }
    }

    /// A stable fingerprint of the syncable content, used to decide what to push.
    /// Tracking a hash beats threading a dirty flag through every mutation site — a
    /// missed flag would mean silently never syncing an edit.
    static func fingerprint(_ run: KitchenRun) -> String {
        guard let (payload, binaries) = try? encode(run),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        else {
            return UUID().uuidString   // unhashable: treat as always-changed
        }
        var hasher = Hasher()
        hasher.combine(data)
        hasher.combine(binaries.runPhoto?.count ?? 0)
        hasher.combine(binaries.signature?.count ?? 0)
        for (key, value) in binaries.defectPhotos.sorted(by: { $0.key < $1.key }) {
            hasher.combine(key)
            hasher.combine(value.count)
        }
        return String(hasher.finalize())
    }
}
