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
    /// Gumroad product id, visible on the product's edit page. Placeholder
    /// until the Gumroad product is created.
    static let productID = "REPLACE_WITH_GUMROAD_PRODUCT_ID"
    static let purchaseURL = URL(string: "https://eliolewis77.gumroad.com/l/nightcat")!

    private static let verifyURL = URL(string: "https://api.gumroad.com/v2/licenses/verify")!

    enum Outcome: Equatable {
        case licensed(email: String)   // verified; buyer email for the About row
        case invalid                   // no such key for this product
        case revoked                   // disabled / refunded / disputed
        case networkFailed             // inconclusive — keep any cached state
    }

    /// Ask Gumroad whether this license key is valid for our product.
    static func verifyOnline(_ key: String) async -> Outcome {
        var request = URLRequest(url: verifyURL)
        request.httpMethod = "POST"
        request.httpBody = "product_id=\(productID)&license_key=\(key)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)?
            .data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .networkFailed }

        guard json["success"] as? Bool == true,
              let purchase = json["purchase"] as? [String: Any] else { return .invalid }
        if purchase["refunded"] as? Bool == true || purchase["disputed"] as? Bool == true {
            return .revoked
        }
        let email = purchase["email"] as? String ?? ""
        return .licensed(email: email)
    }
}
