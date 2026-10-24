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

  /// 共有されたページの URL を1件選ぶ。Safari は URL、他のアプリは本文に URL を含めて渡すことがある。
  ///
  /// **URL の添付を本文より先に見て、App Store のリンクは外す。** Chrome はページを開いていない
  /// 状態の共有で「Chrome をダウンロード」の本文と App Store のリンクだけを渡し、それが karita に
  /// 届くと「何をしますか？」になった（2026-10-24、実機 iOS 27）。
  private func sharedURL() async -> URL? {
    let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
    var linked: [URL] = []
    var written: [URL] = []
    for provider in items.flatMap({ $0.attachments ?? [] }) {
      linked += await urls(in: provider, as: .url)
      written += await urls(in: provider, as: .plainText)
    }
    for item in items {
      written += webURLs(in: item.attributedContentText?.string ?? "")
    }
    return (linked + written).first { isWeb($0) && !isAppStore($0) }
  }

  /// 添付の中身を読む。**型の宣言と中身が一致するとは限らない** — URL の添付が `Data` や
  /// 文字列で来ることがあるので、どれでも URL を取り出す。
  private func urls(in provider: NSItemProvider, as type: UTType) async -> [URL] {
    guard provider.hasItemConformingToTypeIdentifier(type.identifier),
      let item = try? await provider.loadItem(forTypeIdentifier: type.identifier)
    else { return [] }
    switch item {
    case let url as URL:
      return [url]
    case let data as Data:
      if let url = URL(dataRepresentation: data, relativeTo: nil), isWeb(url) { return [url] }
      return webURLs(in: String(data: data, encoding: .utf8) ?? "")
    case let text as String:
      return webURLs(in: text)
    case let text as NSAttributedString:
      return webURLs(in: text.string)
    default:
      return []
    }
  }

  private func webURLs(in text: String) -> [URL] {
    let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    let range = NSRange(text.startIndex..., in: text)
    return detector?.matches(in: text, range: range).compactMap(\.url) ?? []
  }

  private func isWeb(_ url: URL) -> Bool { url.scheme == "http" || url.scheme == "https" }

  private func isAppStore(_ url: URL) -> Bool {
    ["apps.apple.com", "itunes.apple.com"].contains(url.host?.lowercased() ?? "")
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
