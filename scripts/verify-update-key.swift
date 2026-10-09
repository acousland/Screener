import Foundation
import CryptoKit

guard CommandLine.arguments.count == 2 else { fatalError("Usage: verify-update-key.swift private-seed-file") }
let text = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
guard let seed = Data(base64Encoded: text), seed.count == 32 else { fatalError("The update key must be a base64-encoded 32-byte Ed25519 seed.") }
let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
let expected = try String(contentsOfFile: "Assets/update-public-key", encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
guard expected == key.publicKey.rawRepresentation.base64EncodedString() else { fatalError("The private update key does not match the public identity embedded in the applications.") }
print("Update signing key matches the applications' public identity.")
