import Testing
import Foundation
import CoreGraphics
@testable import TEIScanner

@Suite("TEIBuilder")
struct TEIBuilderTests {

    private func samplePages() -> [TEIPage] {
        [
            TEIPage(
                imageURL: URL(fileURLWithPath: "/tmp/original-name-1.png"),
                imageSize: CGSize(width: 800, height: 1200),
                lines: [
                    OCRLine(text: "first line", box: CGRect(x: 10, y: 20, width: 100, height: 30)),
                    OCRLine(text: "second line", box: CGRect(x: 12, y: 60, width: 110, height: 32)),
                ]
            ),
            TEIPage(
                imageURL: URL(fileURLWithPath: "/tmp/original-name-2.jpg"),
                imageSize: CGSize(width: 640, height: 900),
                lines: [
                    OCRLine(text: "page two", box: CGRect(x: 5, y: 5, width: 200, height: 40)),
                ]
            ),
        ]
    }

    @Test("Each OCR line yields one zone and one lb linked by corresp")
    func zonesAndLinesAreLinked() {
        let xml = TEIBuilder.build(pages: samplePages(), meta: TEIMeta())
        // Transcription is wrapped in a single <p>, as the editor requires.
        #expect(xml.contains("<body>\n      <p>\n"))
        // 3 OCR lines total across 2 pages.
        #expect(occurrences(of: "<zone ", in: xml) == 3)
        #expect(occurrences(of: "<lb ", in: xml) == 3)
        // corresp references resolve to existing zone ids; text follows the lb.
        #expect(xml.contains(#"<zone xml:id="f1_l1""#))
        #expect(xml.contains(##"<lb corresp="#f1_l1" n="1" type="line"/>first line"##))
        #expect(xml.contains(#"<zone xml:id="f2_l1""#))
        #expect(xml.contains(##"<lb corresp="#f2_l1" n="1" type="line"/>page two"##))
    }

    @Test("Zone coordinates are derived from the line bounding box")
    func zoneCoordinatesComeFromBox() {
        let xml = TEIBuilder.build(pages: samplePages(), meta: TEIMeta())
        // box (10,20,100,30) → ulx=10 uly=20 lrx=110 lry=50
        #expect(xml.contains(#"<zone xml:id="f1_l1" ulx="10" uly="20" lrx="110" lry="50"/>"#))
    }

    @Test("Surface dimensions come from the image size")
    func surfaceDimensionsFromImageSize() {
        let xml = TEIBuilder.build(pages: samplePages(), meta: TEIMeta())
        #expect(xml.contains(#"<surface xml:id="f1" ulx="0" uly="0" lrx="800" lry="1200">"#))
    }

    @Test("Output is a well-formed TEI document")
    func outputIsWellFormedXML() throws {
        let xml = TEIBuilder.build(pages: samplePages(), meta: TEIMeta())
        let data = Data(xml.utf8)
        // Throws if the XML does not parse.
        _ = try XMLDocument(data: data)
    }

    @Test("Special characters in OCR text are escaped")
    func specialCharactersAreEscaped() {
        let pages = [
            TEIPage(
                imageURL: URL(fileURLWithPath: "/tmp/p.png"),
                imageSize: CGSize(width: 100, height: 100),
                lines: [OCRLine(text: "a < b & c > d", box: CGRect(x: 0, y: 0, width: 10, height: 10))]
            )
        ]
        let xml = TEIBuilder.build(pages: pages, meta: TEIMeta())
        #expect(xml.contains("a &lt; b &amp; c &gt; d"))
    }

    // MARK: - helpers

    private func occurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var range = haystack.startIndex..<haystack.endIndex
        while let found = haystack.range(of: needle, range: range) {
            count += 1
            range = found.upperBound..<haystack.endIndex
        }
        return count
    }
}
