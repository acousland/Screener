import Foundation
import CryptoKit

// Sparkle 2.10 accepts a base64-encoded 32-byte Ed25519 seed.
// The private seed remains local; only the public key is committed.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let directory = root.appendingPathComponent(".secrets", isDirectory: true)
let seedURL = directory.appendingPathComponent("sparkle-private-key")
let publicURL = root.appendingPathComponent("Assets/update-public-key")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions:0o700])
let key: Curve25519.Signing.PrivateKey
if FileManager.default.fileExists(atPath: seedURL.path) {
    let text = try String(contentsOf: seedURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    guard let data = Data(base64Encoded: text) else { fatalError("The existing local update key is invalid.") }
    key = try Curve25519.Signing.PrivateKey(rawRepresentation: data)
} else {
    guard !FileManager.default.fileExists(atPath: publicURL.path) else { fatalError("A public update key already exists. Restore its matching private key instead of replacing it.") }
    key = Curve25519.Signing.PrivateKey()
    try (key.rawRepresentation.base64EncodedString() + "\n").write(to: seedURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions:0o600], ofItemAtPath: seedURL.path)
}
let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
if FileManager.default.fileExists(atPath: publicURL.path) {
    let existing = try String(contentsOf: publicURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    guard existing == publicKey else { fatalError("The local update key does not match the committed public key.") }
} else { try (publicKey + "\n").write(to: publicURL, atomically: true, encoding: .utf8) }
print("Sparkle public key is ready. The private signing seed is stored only in .secrets/.")
