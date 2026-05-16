import Foundation

extension AppState {

    /// Build the list of OCR'd pages in the same order/filtering that
    /// `TEIBuilder` and `rebuildPreview()` use, so surface ids stay aligned.
    private func teiPages() -> [TEIPage] {
        pages.compactMap { page in
            guard let r = page.result else { return nil }
            return TEIPage(imageURL: page.url, imageSize: r.imageSize, lines: r.lines)
        }
    }

    /// Write a self-contained bundle folder (`tei.xml` + `images/` +
    /// `index.html`) so it can be opened directly in the TEI/IIIF editor
    /// without an IIIF server or upload. `index.html` is a verification view
    /// that renders `tei.xml` live in the browser (see `BundleViewer`), for
    /// checking the OCR text against the page images. Image files are named
    /// `f1.<ext>`, `f2.<ext>`, … matching their surface id.
    func exportBundle(to destDir: URL) throws {
        let fm = FileManager.default
        let teiPages = teiPages()

        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        let imagesDir = destDir.appendingPathComponent("images", isDirectory: true)
        try fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)

        for (index, page) in teiPages.enumerated() {
            let name = TEIBuilder.bundleImageName(index: index, imageURL: page.imageURL)
            let dest = imagesDir.appendingPathComponent(name)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: page.imageURL, to: dest)
        }

        let xml = TEIBuilder.build(pages: teiPages, meta: meta)
        let xmlURL = destDir.appendingPathComponent("tei.xml")
        try xml.write(to: xmlURL, atomically: true, encoding: .utf8)

        // index.html renders tei.xml live in the browser (client-side XSLT).
        let htmlURL = destDir.appendingPathComponent("index.html")
        try BundleViewer.indexHTML.write(to: htmlURL, atomically: true, encoding: .utf8)

        markSaved(xmlURL)
    }
}
