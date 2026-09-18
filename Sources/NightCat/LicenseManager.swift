import Foundation
import CryptoKit

/// Offline license verification for the paid build.
///
/// A license is the string `NC1.<payload b64>.<signature b64>` where the
/// payload is a UTF-8 sentence naming the buyer, Ed25519-signed with the
/// maintainer-held private key. The public key pinned here verifies it —
/// same trust shape as Sparkle's update signatures. Verification is purely
/// offline; the licensed tier keeps every feature available, so this is a
/// support-the-developer mechanism, not a feature gate.
enum LicenseManager {
    /// Ed25519 raw public key — `license_public.pem`, DER tail (see
    /// scripts/generate_license.sh).
    private static let publicKeyBase64 = "qG0XGU8pSnhrE8/D5aPmD1JC1FMc44cup3bko1Edz7s="
    private static let payloadPrefix = "NightCat license for "
    private static let keyPrefix = "NC1"

    /// Gumroad product page. Created by the maintainer; the slug must match.
    static let purchaseURL = URL(string: "https://eliolewis77.gumroad.com/l/nightcat")!

    /// Verify a pasted license. Returns the buyer email it names, or `nil`
    /// when the key is malformed, forged, or signed by a different key.
    static func verify(_ rawKey: String) -> String? {
        let parts = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == keyPrefix,
              let payload = Data(base64Encoded: String(parts[1])),
              let signature = Data(base64Encoded: String(parts[2])),
              let publicKey = try? Curve25519.Signing.PublicKey(
                rawRepresentation: Data(base64Encoded: publicKeyBase64)!)
        else { return nil }

        let payloadText = String(data: payload, encoding: .utf8) ?? ""
        guard payloadText.hasPrefix(payloadPrefix) else { return nil }
        guard publicKey.isValidSignature(signature, for: payload) else { return nil }

        return String(payloadText.dropFirst(payloadPrefix.count))
    }
}
