import Testing
import Foundation
import CoreGraphics
@testable import TEIScanner

@Suite("Bundle viewer")
struct BundleViewerTests {

    @Test("The embedded stylesheet is well-formed XML")
    func stylesheetIsWellFormed() throws {
        // Catches XSLT typos that would otherwise only fail in the browser.
        _ = try XMLDocument(data: Data(BundleViewer.stylesheet.utf8))
    }

    @Test("index.html embeds the stylesheet and a client-side loader")
    func indexHTMLEmbedsViewer() {
        let html = BundleViewer.indexHTML
        #expect(html.hasPrefix("<!DOCTYPE html>"))
        // The stylesheet is embedded verbatim as the renderer.
        #expect(html.contains(#"<script type="application/xslt+xml" id="tei-stylesheet">"#))
        #expect(html.contains("xsl:stylesheet"))
        // It transforms tei.xml live, in the browser.
        #expect(html.contains("XSLTProcessor"))
        #expect(html.contains(#"fetch("tei.xml")"#))
    }

    @Test("exportBundle writes index.html next to tei.xml")
    @MainActor
    func exportBundleWritesIndexHTML() throws {
        let fm = FileManager.default
        let srcDir = fm.temporaryDirectory.appendingPathComponent("teiscanner-src-\(UUID().uuidString)")
        try fm.createDirectory(at: srcDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: srcDir) }
        let imageURL = srcDir.appendingPathComponent("page.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: imageURL)

        let state = AppState()
        state.pages = [
            AppState.PageEntry(
                url: imageURL,
                thumbnail: nil,
                result: OCRPageResult(
                    imageSize: CGSize(width: 100, height: 200),
                    lines: [OCRLine(text: "checked", box: CGRect(x: 1, y: 2, width: 3, height: 4))]
                )
            )
        ]

        let destDir = fm.temporaryDirectory.appendingPathComponent("teiscanner-out-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: destDir) }
        try state.exportBundle(to: destDir)

        let html = try String(contentsOf: destDir.appendingPathComponent("index.html"), encoding: .utf8)
        #expect(html == BundleViewer.indexHTML)
    }
}
