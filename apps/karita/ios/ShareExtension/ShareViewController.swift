import UIKit
import UniformTypeIdentifiers

/// 共有メニューの［karita］。**URL を1件受け、`karita://share?url=…` で本体を開くだけである。**
///
/// 受理するかどうかは本体の `karita_handoff` が決める。ここは規則を持たず、Windows の
/// ブラウザー拡張と同じ配送 URI を作る。
final class ShareViewController: UIViewController {
  private var handled = false

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    if handled { return }
    handled = true
    Task { @MainActor in
      guard let shared = await sharedURL(), let delivery = deliveryURL(for: shared) else {
        finish()
        return
      }
      openContainingApp(delivery)
      finish()
    }
  }

  /// 最初の添付から URL を取る。Safari は URL、他のアプリは本文に URL を含めて渡すことがある。
  private func sharedURL() async -> URL? {
    let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
    for provider in items.flatMap({ $0.attachments ?? [] }) {
      if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
        let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
        url.scheme == "http" || url.scheme == "https"
      {
        return url
      }
      if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
        let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier)
          as? String,
        let url = firstWebURL(in: text)
      {
        return url
      }
    }
    return nil
  }

  private func firstWebURL(in text: String) -> URL? {
    let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    let range = NSRange(text.startIndex..., in: text)
    return detector?.matches(in: text, range: range)
      .compactMap(\.url)
      .first { $0.scheme == "http" || $0.scheme == "https" }
  }

  private func deliveryURL(for shared: URL) -> URL? {
    var components = URLComponents()
    components.scheme = "karita"
    components.host = "share"
    // 内側の URL は丸ごと符号化する。`URLQueryItem` は `&`・`=`・`+` を残し、受け側は `+` を
    // 空白と読む。
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: "&=+?#/:")
    components.percentEncodedQuery =
      "url=" + (shared.absoluteString.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
    return components.url
  }

  /// **共有拡張から本体を開く公式の口は無い。** 応答チェーンの `UIApplication` に頼る。
  /// 開けなくても拡張は閉じる（利用者は［URLを貼り付け］で取り込める）。
  ///
  /// `open(_:options:completionHandler:)` は拡張では使えない宣言なので、名前で引いて呼ぶ。
  /// 拡張は `APPLICATION_EXTENSION_API_ONLY` でしかビルドできない（Xcode 26）。
  private func openContainingApp(_ url: URL) {
    typealias Open = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
    let selector = NSSelectorFromString("openURL:options:completionHandler:")
    var responder: UIResponder? = self
    while let current = responder {
      if let application = current as? UIApplication, application.responds(to: selector) {
        let open = unsafeBitCast(application.method(for: selector), to: Open.self)
        open(application, selector, url as NSURL, NSDictionary(), nil)
        return
      }
      responder = current.next
    }
  }

  private func finish() {
    extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
  }
}
