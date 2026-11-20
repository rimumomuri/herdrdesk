import Foundation
import CryptoKit
import Darwin

public struct UserDispatchIntent {
    public let id: String
    public let payload: String
}

/// Local GUI provenance, not an authentication boundary against other same-UID processes.
/// Sender outcome and observed input are independent. No request body is persisted.
public final class UserDispatchReceipts {
    public let root: URL
    public let generation: String
    private let ttl: TimeInterval = 600
    private let mutex = NSLock()
    private var invalidatedEpochs = Set<String>()
    private struct Receipt: Codable {
        var id, sourceID, nonce, address, session, generation, observerEpoch, digest, senderState: String
        var createdAt: TimeInterval
    }
    private struct Observation: Codable {
        var sourceDigest, requestID, generation, claimKey, turn: String
    }
    private struct ObserverEpoch: Codable {
        var id, generation, address, session: String
    }
    public init(root: URL, generation: String = UUID().uuidString) {
        self.root = root
        self.generation = generation
    }
    public static func defaultRoot() -> URL { DeskPaths.data.appendingPathComponent("user-dispatch", isDirectory:true) }

    /// Sender and first source reserve the same target epoch, in either order.
    public func observerEpoch(address: String, session: String) throws -> String {
        try locked(create:true) { try currentEpoch(address:address,session:session) }
    }

    /// A retained cursor does not call this. Removal/replacement revokes pending
    /// intents even if persisting the replacement epoch temporarily fails.
    public func rotateObserverEpoch(address: String, session: String, expected: String?) throws {
        if let expected {
            mutex.lock(); invalidatedEpochs.insert(revocationKey(address:address,session:session,epoch:expected)); mutex.unlock()
        }
        try locked(create:true) {
            let current = try currentEpoch(address:address,session:session)
            if let expected, current != expected { return }
            try writeEpoch(address:address,session:session)
        }
    }

    /// Called only after target/attachment validation, immediately before dispatch.
    public func arm(sourceID: String, address: String, session: String, payload: String, now: Date = Date()) throws -> UserDispatchIntent {
        guard !address.isEmpty, !session.isEmpty, sourceID.count <= 96 else { throw failure() }
        let id = "u" + UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased()
        let nonce = UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased()
        let outgoing = "[HerdrDesk user request id=\(id) nonce=\(nonce)]\n" + payload
        try locked(create:true) {
            let epoch = try currentEpoch(address:address,session:session)
            let receipt = Receipt(id:id, sourceID:sourceID, nonce:nonce, address:address, session:session, generation:generation,
                                  observerEpoch:epoch, digest:Self.hash(outgoing), senderState:"armed", createdAt:now.timeIntervalSince1970)
            guard !exists(observationURL(receipt)) else { throw failure() }
            try write(receipt)
        }
        return UserDispatchIntent(id:id,payload:outgoing)
    }

    public func recordSenderResult(_ id: String, outcome: SendOutcome) throws {
        try locked(create:false) {
            var receipt = try read(id)
            guard receipt.generation == generation else { throw failure() }
            switch outcome {
            case .sent: receipt.senderState = "sent"
            case .notSent: receipt.senderState = "not_sent"
            case .needsCheck: receipt.senderState = "needs_check"
            case .refused: receipt.senderState = "refused"
            }
            try write(receipt)
        }
    }

    /// Only a newly observed typed provider user record may call this. Reprocessing
    /// that exact source position is idempotent; a different position is a replay.
    public func claim(text: String, address: String, session: String, turn: String, recordKey: String, observerEpoch: String? = nil, now: Date = Date()) -> Bool {
        guard !turn.isEmpty, !recordKey.isEmpty, let payload = Self.candidatePayload(text),
              let token = Self.token(payload) else { return false }
        do {
            return try locked(create:false) {
                let receipt = try read(token.id)
                guard receipt.id == token.id, receipt.nonce == token.nonce, receipt.address == address,
                      receipt.session == session, receipt.generation == generation, receipt.digest == Self.hash(payload) else { return false }
                let activeEpoch = try currentEpoch(address:address,session:session)
                guard receipt.observerEpoch == activeEpoch, observerEpoch.map({ $0 == activeEpoch }) ?? true else { return false }
                let key = Self.hash(recordKey + ":" + turn)
                let observedURL = observationURL(receipt)
                if exists(observedURL) {
                    try privateItem(observedURL,directory:false)
                    let observed = try JSONDecoder().decode(Observation.self,from:Data(contentsOf:observedURL))
                    return observed.requestID == receipt.id && observed.generation == generation && observed.claimKey == key
                        && observed.turn == turn && observed.sourceDigest == sourceDigest(receipt)
                }
                let age = now.timeIntervalSince1970 - receipt.createdAt
                guard age >= 0, age <= ttl else { return false }
                let observed = Observation(sourceDigest:sourceDigest(receipt),requestID:receipt.id,generation:generation,claimKey:key,turn:turn)
                try writeData(JSONEncoder().encode(observed),to:observedURL)
                return true
            }
        } catch { return false }
    }

    static func candidatePayload(_ text: String) -> String? {
        if text.hasPrefix("[HerdrDesk user request ") { return text }
        let frame = text.trimmingCharacters(in:.whitespacesAndNewlines)
        let pattern = #"\A<hc from="([A-Za-z0-9._/-]+)(?: [^"<>\r\n]+)?"(?: reach="hc send \1(?: [^"<>\r\n]*)?")?>([\s\S]+)</hc>\z"#
        guard let regex = try? NSRegularExpression(pattern:pattern),
              let match = regex.firstMatch(in:frame,range:NSRange(frame.startIndex...,in:frame)),
              let body = Range(match.range(at:2),in:frame) else { return nil }
        let payload = String(frame[body])
        return payload.hasPrefix("[HerdrDesk user request ") ? payload : nil
    }
    private static func token(_ payload: String) -> (id:String,nonce:String)? {
        let pattern = #"\A\[HerdrDesk user request id=(u[0-9a-f]{32}) nonce=([0-9a-f]{32})\]\n"#
        guard let regex = try? NSRegularExpression(pattern:pattern),
              let match = regex.firstMatch(in:payload,range:NSRange(payload.startIndex...,in:payload)),
              let id = Range(match.range(at:1),in:payload), let nonce = Range(match.range(at:2),in:payload) else { return nil }
        return (String(payload[id]),String(payload[nonce]))
    }
    private static func hash(_ text: String) -> String { SHA256.hash(data:Data(text.utf8)).map { String(format:"%02x",$0) }.joined() }
    private func epochURL(address: String, session: String) -> URL {
        root.appendingPathComponent("epoch-" + Self.hash([generation,address,session].joined(separator:"\u{0}")) + ".json")
    }
    private func revocationKey(address: String, session: String, epoch: String) -> String {
        Self.hash([generation,address,session,epoch].joined(separator:"\u{0}"))
    }
    private func currentEpoch(address: String, session: String) throws -> String {
        let url = epochURL(address:address,session:session)
        if exists(url) {
            try privateItem(url,directory:false)
            let epoch = try JSONDecoder().decode(ObserverEpoch.self,from:Data(contentsOf:url))
            guard epoch.generation == generation, epoch.address == address, epoch.session == session,
                  UUID(uuidString:epoch.id) != nil else { throw failure() }
            if !invalidatedEpochs.contains(revocationKey(address:address,session:session,epoch:epoch.id)) { return epoch.id }
        }
        return try writeEpoch(address:address,session:session)
    }
    @discardableResult
    private func writeEpoch(address: String, session: String) throws -> String {
        let epoch = ObserverEpoch(id:UUID().uuidString,generation:generation,address:address,session:session)
        try writeData(JSONEncoder().encode(epoch),to:epochURL(address:address,session:session))
        return epoch.id
    }
    private func sourceDigest(_ receipt: Receipt) -> String { Self.hash([receipt.sourceID,receipt.address,receipt.session].joined(separator:"\u{0}")) }
    private func observationURL(_ receipt: Receipt) -> URL { root.appendingPathComponent("observed-" + sourceDigest(receipt) + ".json") }
    private func exists(_ url: URL) -> Bool { var info = stat(); return lstat(url.path,&info) == 0 }
    private func failure() -> NSError { NSError(domain:"user-dispatch",code:1,userInfo:[NSLocalizedDescriptionKey:"User request receipt is unavailable or unsafe."]) }
    private func file(_ id: String) throws -> URL {
        guard id.range(of:"^u[0-9a-f]{32}$",options:.regularExpression) != nil else { throw failure() }
        return root.appendingPathComponent(id + ".json")
    }
    private func privateItem(_ url: URL, directory: Bool) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath:url.path)
        guard attributes[.type] as? FileAttributeType == (directory ? .typeDirectory : .typeRegular),
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              (attributes[.posixPermissions] as? NSNumber)?.intValue == (directory ? 0o700 : 0o600) else { throw failure() }
    }
    private func locked<T>(create: Bool, _ action: () throws -> T) throws -> T {
        mutex.lock()
        defer { mutex.unlock() }
        if create && !FileManager.default.fileExists(atPath:root.path) {
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        }
        try privateItem(root,directory:true)
        let lockURL = root.appendingPathComponent(".claim.lock")
        if exists(lockURL) { try privateItem(lockURL,directory:false) }
        let fd = open(lockURL.path,O_CREAT | O_RDWR | O_NOFOLLOW,0o600)
        guard fd >= 0 else { throw failure() }
        defer { close(fd) }
        guard flock(fd,LOCK_EX) == 0 else { throw failure() }
        defer { flock(fd,LOCK_UN) }
        try privateItem(lockURL,directory:false)
        return try action()
    }
    private func read(_ id: String) throws -> Receipt {
        let url = try file(id)
        try privateItem(url,directory:false)
        guard let size = (try FileManager.default.attributesOfItem(atPath:url.path))[.size] as? NSNumber, size.intValue < 16 * 1024 else { throw failure() }
        return try JSONDecoder().decode(Receipt.self,from:Data(contentsOf:url))
    }
    private func write(_ receipt: Receipt) throws {
        try writeData(JSONEncoder().encode(receipt),to:file(receipt.id))
    }
    private func writeData(_ data: Data, to destination: URL) throws {
        if exists(destination) { try privateItem(destination,directory:false) }
        let temporary = root.appendingPathComponent("." + UUID().uuidString + ".tmp")
        let fd = open(temporary.path,O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,0o600)
        guard fd >= 0 else { throw failure() }
        let handle = FileHandle(fileDescriptor:fd,closeOnDealloc:true)
        do {
            try handle.write(contentsOf:data)
            try handle.synchronize(); try handle.close()
            guard rename(temporary.path,destination.path) == 0 else { throw failure() }
        } catch {
            try? handle.close(); unlink(temporary.path)
            throw error
        }
    }
}
