import AppKit
import Foundation

/// License verification backed by Gumroad's license-key system.
///
/// Flow: the buyer pays on Gumroad, which auto-generates and emails a
/// license key. The app verifies it once online (product id is public
/// information — nothing sensitive ships in this open-source repo), then
/// caches the result. Later launches re-verify quietly in the background;
/// an offline or unreachable Gumroad never removes an existing license —
/// only an explicit "disabled/refunded" verdict does.
enum LicenseManager {
    /// Gumroad product id (from the product edit page URL).
    static let productID = "Zw2vSj4SG_tvXIvfhW5TqQ=="
    static let purchaseURL = URL(string: "https://eliowave2.gumroad.com/l/nightcat")!

    private static let verifyURL = URL(string: "https://api.gumroad.com/v2/licenses/verify")!
    /// Gumroad is a small POST-JSON endpoint; without an explicit interval a
    /// black-holed connection holds the awaiting task for URLSession's 60s
    /// default.
    private static let timeout: TimeInterval = 10

    enum Outcome: Equatable {
        case licensed(email: String)   // verified; buyer email for the About row
        case invalid                   // no such key for this product
        case revoked                   // disabled / refunded / disputed
        case networkFailed             // inconclusive — keep any cached state
    }

    /// Single funnel for every "buy" affordance (panel row, About section) so
    /// a distribution change lands in one place.
    static func openPurchasePage() {
        NSWorkspace.shared.open(purchaseURL)
    }

    /// Ask Gumroad whether this license key is valid for our product.
    static func verifyOnline(_ key: String) async -> Outcome {
        // Per-value encoding via URLComponents: pasting the whole query string
        // through percent-encoding would leave `&`/`=`/`+` unencoded, so a key
        // containing `+` would arrive as a space and one with `&` truncated.
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "product_id", value: productID),
            URLQueryItem(name: "license_key", value: key),
        ]
        var request = URLRequest(url: verifyURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .networkFailed }

        // Gumroad answers "no such key" with HTTP 404 + `success:false`, so
        // the status code alone can't separate invalid from unreachable.
        guard (200...299).contains(http.statusCode) else {
            return json["success"] as? Bool == false ? .invalid : .networkFailed
        }
        guard json["success"] as? Bool == true,
              let purchase = json["purchase"] as? [String: Any] else { return .invalid }
        // A disabled key still answers 200/success:true — only the flags
        // tell it apart.
        if json["disabled"] as? Bool == true
            || purchase["refunded"] as? Bool == true
            || purchase["disputed"] as? Bool == true {
            return .revoked
        }
        let email = purchase["email"] as? String ?? ""
        return .licensed(email: email)
    }
}
