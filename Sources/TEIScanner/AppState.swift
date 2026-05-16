import Foundation
import SwiftUI
import AppKit

@MainActor
@Observable
final class AppState {
    enum PageStatus: Equatable {
        case pending
        case running
        case done(lineCount: Int)
        case failed(String)
    }

    struct PageEntry: Identifiable {
        let id = UUID()
        var url: URL
        var thumbnail: NSImage?
        var status: PageStatus = .pending
        var result: OCRPageResult?
    }

    var folderURL: URL?
    var pages: [PageEntry] = []
    var selectedPageID: PageEntry.ID?
    var meta = TEIMeta()
    var ocrLanguage: OCRLanguage = .auto
    var xmlPreview: String = ""
    var isProcessing = false
    var progressText: String = ""
    var lastSavedURL: URL?
    var showSavedToast = false
    var requestedDetailMode: String?  // "image" | "xml"
    private var rebuildDebounceTask: Task<Void, Never>?

    var selectedPage: PageEntry? {
        guard let id = selectedPageID else { return pages.first }
        return pages.first { $0.id == id } ?? pages.first
    }

    var hasAnyOCRResult: Bool { pages.contains { $0.result != nil } }
    var doneCount: Int {
        pages.reduce(0) { acc, p in
            if case .done = p.status { return acc + 1 }
            if case .failed = p.status { return acc + 1 }
            return acc
        }
    }

    func loadFolder(_ url: URL) {
        folderURL = url
        let exts: Set<String> = ["jpg", "jpeg", "png", "tif", "tiff", "heic", "bmp", "gif"]
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        let imgs = items
            .filter { exts.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        pages = imgs.map { url in
            PageEntry(url: url, thumbnail: makeThumbnail(url: url))
        }
        selectedPageID = pages.first?.id
        if meta.title == "Untitled" {
            meta.title = url.lastPathComponent
        }
        xmlPreview = ""
    }

    private func makeThumbnail(url: URL) -> NSImage? {
        guard let img = NSImage(contentsOf: url) else { return nil }
        let target: CGFloat = 96
        let ratio = max(img.size.width, img.size.height) / target
        let size = NSSize(width: img.size.width / max(ratio, 1), height: img.size.height / max(ratio, 1))
        let thumb = NSImage(size: size)
        thumb.lockFocus()
        img.draw(in: NSRect(origin: .zero, size: size),
                 from: .zero,
                 operation: .copy,
                 fraction: 1.0)
        thumb.unlockFocus()
        return thumb
    }

    func runOCRAll() async {
        guard !pages.isEmpty else { return }
        isProcessing = true
        defer {
            isProcessing = false
            progressText = ""
            rebuildPreview()
        }

        for index in pages.indices {
            pages[index].status = .running
            progressText = "OCR \(index + 1)/\(pages.count): \(pages[index].url.lastPathComponent)"
            let url = pages[index].url
            let lang = ocrLanguage
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try OCRService.recognize(imageURL: url, language: lang)
                }.value
                pages[index].result = result
                pages[index].status = .done(lineCount: result.lines.count)
            } catch {
                pages[index].status = .failed(String(describing: error))
            }
        }
    }

    func rebuildPreview() {
        let teiPages: [TEIPage] = pages.compactMap { page in
            guard let r = page.result else { return nil }
            return TEIPage(imageURL: page.url, imageSize: r.imageSize, lines: r.lines)
        }
        xmlPreview = TEIBuilder.build(pages: teiPages, meta: meta)
    }

    /// Coalesce frequent rebuild requests (e.g. per-keystroke metadata edits)
    /// into one rebuild after 300 ms of quiet, so typing doesn't re-stringify
    /// every page on every key.
    func scheduleRebuild(after ms: Int = 300) {
        rebuildDebounceTask?.cancel()
        rebuildDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(ms))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.rebuildPreview() }
        }
    }

    func saveXML(to url: URL) throws {
        try xmlPreview.write(to: url, atomically: true, encoding: .utf8)
        markSaved(url)
    }

    /// Record `url` as the last saved location and flash the "Saved" toast.
    /// Shared by `saveXML` and the bundle export (see `BundleExport.swift`).
    func markSaved(_ url: URL) {
        lastSavedURL = url
        showSavedToast = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            await MainActor.run { self?.showSavedToast = false }
        }
    }
}
