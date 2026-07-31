import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A ~40pt thumbnail for a receipt attachment: the image itself for image kinds,
/// a doc icon for PDFs. Loads the platform image off the file URL lazily.
struct ReceiptThumbnail: View {
    let url: URL
    let kind: String
    @State private var image: Image?
    private let side: CGFloat = 40

    var body: some View {
        Group {
            if kind == "pdf" {
                Image(systemName: "doc.richtext").foregroundStyle(.secondary)
            } else if let image {
                image.resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: url) { if kind != "pdf", image == nil { image = Self.load(url) } }
    }

    private static func load(_ url: URL) -> Image? {
        #if canImport(UIKit)
        return UIImage(contentsOfFile: url.path).map(Image.init(uiImage:))
        #elseif canImport(AppKit)
        return NSImage(contentsOf: url).map(Image.init(nsImage:))
        #else
        return nil
        #endif
    }
}
