import Foundation
import SafariServices
import os.log

/// Bridges messages from the Safari Web Extension JS side into the App Group
/// container so the main app can pick them up. On a "save" message we drop a
/// PendingSave JSON and reply with { ok: true }.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {

    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem
        let profile: UUID? = {
            if #available(iOS 17.0, macOS 14.0, *) {
                return request?.userInfo?[SFExtensionProfileKey] as? UUID
            }
            return nil
        }()
        _ = profile

        let message: Any? = {
            if let userInfo = request?.userInfo, let msg = userInfo[SFExtensionMessageKey] {
                return msg
            }
            return nil
        }()

        var responsePayload: [String: Any] = ["ok": false]
        if let dict = message as? [String: Any],
           let action = dict["action"] as? String,
           action == "save",
           let urlString = dict["url"] as? String,
           let url = URL(string: urlString)
        {
            let title = dict["title"] as? String
            let html = dict["html"] as? String
            let pending = PendingSave(
                url: url,
                title: title,
                capturedHTML: html,
                source: .safariWebExtension
            )
            do {
                try pending.write()
                responsePayload = ["ok": true]
            } catch {
                responsePayload = ["ok": false, "error": String(describing: error)]
            }
        }

        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: responsePayload]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
