import Testing
import Foundation
import CoreGraphics
@testable import TEIScanner

@Suite("Bundle image naming")
struct BundleImageNamingTests {

    @Test("Image name is keyed to the surface id")
    func bundleImageNameUsesSurfaceID() {
        let url = URL(fileURLWithPath: "/tmp/scan.png")
        #expect(TEIBuilder.bundleImageName(index: 0, imageURL: url) == "f1.png")
        #expect(TEIBuilder.bundleImageName(index: 4, imageURL: url) == "f5.png")
    }

    @Test("Original extension is preserved and lower-cased")
    func bundleImageNameLowercasesExtension() {
        let url = URL(fileURLWithPath: "/tmp/SOME SCAN 001.JPG")
        #expect(TEIBuilder.bundleImageName(index: 0, imageURL: url) == "f1.jpg")
    }

    @Test("Missing extension falls back to png")
    func bundleImageNameDefaultsToPNG() {
        let url = URL(fileURLWithPath: "/tmp/noextension")
        #expect(TEIBuilder.bundleImageName(index: 2, imageURL: url) == "f3.png")
    }

    @Test("graphic url points into the images/ folder, not the original file name")
    func graphicURLUsesImagesFolder() {
        let pages = [
            TEIPage(imageURL: URL(fileURLWithPath: "/tmp/original-name-1.png"),
                    imageSize: CGSize(width: 800, height: 1200),
                    lines: [OCRLine(text: "x", box: .zero)]),
            TEIPage(imageURL: URL(fileURLWithPath: "/tmp/original-name-2.jpg"),
                    imageSize: CGSize(width: 640, height: 900),
                    lines: [OCRLine(text: "y", box: .zero)]),
        ]
        let xml = TEIBuilder.build(pages: pages, meta: TEIMeta())
        #expect(xml.contains(#"<graphic url="images/f1.png""#))
        #expect(xml.contains(#"<graphic url="images/f2.jpg""#))
        #expect(!xml.contains("original-name-1"))
        #expect(!xml.contains("original-name-2"))
    }
}

@Suite("Bundle export")
@MainActor
struct ExportBundleTests {

    /// Create a temp folder with placeholder image files and return its URL.
    private func makeSourceImages(_ names: [String]) throws -> (dir: URL, urls: [URL]) {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("teiscanner-src-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let urls = try names.map { name -> URL in
            let url = dir.appendingPathComponent(name)
            try Data([0x89, 0x50, 0x4E, 0x47]).write(to: url) // dummy bytes
            return url
        }
        return (dir, urls)
    }

    private func page(_ url: URL, text: String) -> AppState.PageEntry {
        AppState.PageEntry(
            url: url,
            thumbnail: nil,
            result: OCRPageResult(
                imageSize: CGSize(width: 100, height: 200),
                lines: [OCRLine(text: text, box: CGRect(x: 1, y: 2, width: 3, height: 4))]
            )
        )
    }

    @Test("Writes tei.xml and copies images into images/")
    func writesBundleFolder() throws {
        let fm = FileManager.default
        let (srcDir, urls) = try makeSourceImages(["page-a.png", "page-b.JPG"])
        defer { try? fm.removeItem(at: srcDir) }

        let state = AppState()
        state.meta.title = "Test Document"
        state.pages = [page(urls[0], text: "hello"), page(urls[1], text: "world")]

        let destDir = fm.temporaryDirectory.appendingPathComponent("teiscanner-out-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: destDir) }
        try state.exportBundle(to: destDir)

        #expect(fm.fileExists(atPath: destDir.appendingPathComponent("tei.xml").path))
        #expect(fm.fileExists(atPath: destDir.appendingPathComponent("images/f1.png").path))
        // Original extension is preserved but lower-cased.
        #expect(fm.fileExists(atPath: destDir.appendingPathComponent("images/f2.jpg").path))

        let xml = try String(contentsOf: destDir.appendingPathComponent("tei.xml"), encoding: .utf8)
        #expect(xml.contains(#"url="images/f1.png""#))
        #expect(xml.contains(#"url="images/f2.jpg""#))
    }

    @Test("Skips pages without OCR results and keeps surface ids contiguous")
    func skipsPagesWithoutResults() throws {
        let fm = FileManager.default
        let (srcDir, urls) = try makeSourceImages(["a.png", "b.png", "c.png"])
        defer { try? fm.removeItem(at: srcDir) }

        let state = AppState()
        var middle = page(urls[1], text: "ignored")
        middle.result = nil // page not OCR'd yet
        state.pages = [page(urls[0], text: "first"), middle, page(urls[2], text: "third")]

        let destDir = fm.temporaryDirectory.appendingPathComponent("teiscanner-out-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: destDir) }
        try state.exportBundle(to: destDir)

        let imagesDir = destDir.appendingPathComponent("images")
        let copied = try fm.contentsOfDirectory(atPath: imagesDir.path).sorted()
        #expect(copied == ["f1.png", "f2.png"])

        let xml = try String(contentsOf: destDir.appendingPathComponent("tei.xml"), encoding: .utf8)
        #expect(xml.contains(##"<lb corresp="#f1_l1" n="1" type="line"/>first"##))
        #expect(xml.contains(##"<lb corresp="#f2_l1" n="1" type="line"/>third"##))
        #expect(!xml.contains("ignored"))
    }

    @Test("Overwrites an existing image of the same name")
    func overwritesExistingImage() throws {
        let fm = FileManager.default
        let (srcDir, urls) = try makeSourceImages(["a.png"])
        defer { try? fm.removeItem(at: srcDir) }

        let state = AppState()
        state.pages = [page(urls[0], text: "x")]

        let destDir = fm.temporaryDirectory.appendingPathComponent("teiscanner-out-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: destDir) }

        try state.exportBundle(to: destDir)
        // Running it a second time must not throw on the pre-existing image.
        try state.exportBundle(to: destDir)
        #expect(fm.fileExists(atPath: destDir.appendingPathComponent("images/f1.png").path))
    }
}
