import Testing
import Foundation
import CoreGraphics
@testable import TEIScanner

@Suite("HTML verification view")
struct TEIHTMLExporterTests {

    private func teiXML(_ pages: [TEIPage], title: String = "Doc") -> String {
        TEIBuilder.build(pages: pages, meta: TEIMeta(title: title))
    }

    @Test("Renders a standalone HTML5 page with the image and OCR text")
    func rendersImageAndText() throws {
        let pages = [
            TEIPage(imageURL: URL(fileURLWithPath: "/tmp/a.png"),
                    imageSize: CGSize(width: 100, height: 200),
                    lines: [OCRLine(text: "verify me", box: .zero)]),
        ]
        let html = try TEIHTMLExporter.renderHTML(fromTEI: teiXML(pages, title: "HTML Test"))

        #expect(html.hasPrefix("<!DOCTYPE html>"))
        #expect(html.contains("HTML Test"))
        #expect(html.contains("verify me"))
        // Image is referenced relative to the bundle folder.
        #expect(html.contains(#"src="images/f1.png""#))
    }

    @Test("Groups OCR lines under their own page")
    func groupsLinesPerPage() throws {
        let pages = [
            TEIPage(imageURL: URL(fileURLWithPath: "/tmp/a.png"),
                    imageSize: CGSize(width: 10, height: 20),
                    lines: [OCRLine(text: "alpha", box: .zero)]),
            TEIPage(imageURL: URL(fileURLWithPath: "/tmp/b.png"),
                    imageSize: CGSize(width: 10, height: 20),
                    lines: [OCRLine(text: "beta", box: .zero),
                            OCRLine(text: "gamma", box: .zero)]),
        ]
        let html = try TEIHTMLExporter.renderHTML(fromTEI: teiXML(pages))

        // Page 1 holds only "alpha"; page 2 holds "beta" then "gamma".
        let page2 = try #require(html.range(of: "Page 2"))
        let alpha = try #require(html.range(of: "alpha"))
        let beta = try #require(html.range(of: "beta"))
        #expect(alpha.lowerBound < page2.lowerBound)
        #expect(page2.lowerBound < beta.lowerBound)
    }

    @Test("exportBundle writes an index.html next to tei.xml")
    @MainActor
    func exportBundleWritesIndexHTML() throws {
        let fm = FileManager.default
        let srcDir = fm.temporaryDirectory.appendingPathComponent("teiscanner-src-\(UUID().uuidString)")
        try fm.createDirectory(at: srcDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: srcDir) }
        let imageURL = srcDir.appendingPathComponent("page.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: imageURL)

        let state = AppState()
        state.meta.title = "Verification Doc"
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

        let htmlURL = destDir.appendingPathComponent("index.html")
        #expect(fm.fileExists(atPath: htmlURL.path))
        let html = try String(contentsOf: htmlURL, encoding: .utf8)
        #expect(html.contains("checked"))
        #expect(html.contains("Verification Doc"))
    }
}
