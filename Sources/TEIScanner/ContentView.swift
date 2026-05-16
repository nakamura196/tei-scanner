import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum DetailMode: String, CaseIterable, Identifiable {
    case image = "Image"
    case xml = "TEI/XML"
    var id: String { rawValue }
}

struct ContentView: View {
    @State private var state = AppState()
    @State private var detailMode: DetailMode = .image
    @State private var isDropTargeted = false
    @State private var screenshotMode = false

    var body: some View {
        Group {
            if state.pages.isEmpty {
                emptyState
            } else if screenshotMode {
                // Flat layout used during automated screenshot capture so that
                // `bitmapImageRepForCachingDisplay` can render every region
                // (NavigationSplitView's sidebar uses NSVisualEffectView which
                // CALayer-backed APIs do not capture).
                HStack(spacing: 0) {
                    sidebar
                        .frame(width: 320)
                        .background(Color(nsColor: .controlBackgroundColor))
                    Divider()
                    detail
                }
            } else {
                NavigationSplitView {
                    sidebar.navigationSplitViewColumnWidth(min: 260, ideal: 320)
                } detail: {
                    detail
                }
            }
        }
        .navigationTitle("TEI Scanner")
        .focusedSceneValue(\.exportTEIAction, state.xmlPreview.isEmpty ? nil : { saveXML() })
        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)
        .onAppear { parseLaunchArgs() }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            VStack(spacing: 18) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(isDropTargeted ? Color.accentColor : .secondary)
                Text("Drop a folder of page images here")
                    .font(.title2)
                Text("or")
                    .foregroundStyle(.secondary)
                Button {
                    chooseFolder()
                } label: {
                    Label("Choose Folder…", systemImage: "folder")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("o", modifiers: .command)

                if Bundle.main.url(forResource: "SamplePages", withExtension: nil) != nil {
                    Button {
                        loadBundledSample()
                    } label: {
                        Label("Try sample", systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                Text("Supports JPG, PNG, TIFF, HEIC, BMP, GIF")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
                    .padding(40)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            actionPanel
            Divider()
            metadataBox
            Divider()
            ScrollViewReader { proxy in
                List(selection: Binding(
                    get: { state.selectedPageID },
                    set: { state.selectedPageID = $0 }
                )) {
                    ForEach(state.pages) { page in
                        pageRow(page)
                            .tag(Optional(page.id))
                            .id(page.id)
                            .listRowBackground(rowTint(page.status))
                    }
                }
                .listStyle(.inset)
                .onChange(of: state.pages.map(\.status)) { _, _ in
                    if let running = state.pages.first(where: {
                        if case .running = $0.status { return true } else { return false }
                    }) {
                        withAnimation { proxy.scrollTo(running.id, anchor: .center) }
                    }
                }
            }
        }
    }

    private var actionPanel: some View {
        VStack(spacing: 8) {
            Button {
                chooseFolder()
            } label: {
                Label(state.folderURL == nil ? "Choose Folder…" : "Change Folder…",
                      systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .keyboardShortcut("o", modifiers: .command)

            runOCRButton
            exportBundleButton
            exportButton

            if state.isProcessing {
                ProgressView(value: Double(state.doneCount), total: Double(max(state.pages.count, 1))) {
                    Text(state.progressText).font(.caption).lineLimit(1)
                }
                .progressViewStyle(.linear)
                .padding(.top, 2)
            }
        }
        .padding(10)
    }

    @ViewBuilder
    private var runOCRButton: some View {
        let body = Button {
            Task { await state.runOCRAll() }
        } label: {
            Label(ocrButtonLabel, systemImage: "text.viewfinder")
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .disabled(state.pages.isEmpty || state.isProcessing)
        .keyboardShortcut(.return, modifiers: .command)
        if state.hasAnyOCRResult {
            body.buttonStyle(.bordered)
        } else {
            body.buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var exportButton: some View {
        let body = Button {
            saveXML()
        } label: {
            Label("Export TEI/XML…", systemImage: "arrow.down.doc")
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .disabled(state.xmlPreview.isEmpty)
        .keyboardShortcut("s", modifiers: .command)
        body.buttonStyle(.bordered)
    }

    @ViewBuilder
    private var exportBundleButton: some View {
        let body = Button {
            exportBundle()
        } label: {
            Label("Export Bundle…", systemImage: "folder.badge.plus")
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .disabled(state.xmlPreview.isEmpty)
        if state.hasAnyOCRResult {
            body.buttonStyle(.borderedProminent)
        } else {
            body.buttonStyle(.bordered)
        }
    }

    private var ocrButtonLabel: String {
        if state.isProcessing { return String(localized: "Running…") }
        if state.pages.isEmpty { return String(localized: "Run OCR") }
        if state.hasAnyOCRResult { return String(localized: "Re-run OCR") }
        let n = state.pages.count
        return String(localized: "Run OCR on \(n) pages")
    }

    private var metadataBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("OCR").font(.headline)
            Picker("Language", selection: Binding(
                get: { state.ocrLanguage },
                set: { state.ocrLanguage = $0 }
            )) {
                ForEach(OCRLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .disabled(state.isProcessing)
            Divider().padding(.vertical, 2)
            Text("Metadata").font(.headline)
            TextField("Title", text: Binding(
                get: { state.meta.title },
                set: { state.meta.title = $0; state.scheduleRebuild() }
            ))
            TextField("Responsible name", text: Binding(
                get: { state.meta.responsibleName },
                set: { state.meta.responsibleName = $0; state.scheduleRebuild() }
            ))
            TextField("Language (ISO)", text: Binding(
                get: { state.meta.language },
                set: { state.meta.language = $0; state.scheduleRebuild() }
            ))
            TextField("Date (YYYY-MM-DD)", text: Binding(
                get: { state.meta.date },
                set: { state.meta.date = $0; state.scheduleRebuild() }
            ))
        }
        .textFieldStyle(.roundedBorder)
        .padding(10)
    }

    private func pageRow(_ page: AppState.PageEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                if let thumb = page.thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(4)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .frame(width: 56, height: 56)
                }
                if case .running = page.status {
                    ProgressView()
                        .controlSize(.small)
                        .padding(2)
                        .background(.regularMaterial, in: Circle())
                        .padding(2)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(page.url.lastPathComponent).font(.callout).lineLimit(1)
                statusBadge(page.status)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func statusBadge(_ status: AppState.PageStatus) -> some View {
        switch status {
        case .pending:
            Label("Pending", systemImage: "clock")
                .font(.caption).foregroundStyle(.secondary)
        case .running:
            Label("Running…", systemImage: "ellipsis")
                .font(.caption).foregroundStyle(.blue)
        case .done(let n):
            Label("\(n) lines", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .failed(let msg):
            Label(msg, systemImage: "xmark.octagon.fill")
                .font(.caption).foregroundStyle(.red).lineLimit(2)
        }
    }

    private func rowTint(_ s: AppState.PageStatus) -> Color? {
        switch s {
        case .running: return Color.blue.opacity(0.08)
        case .failed:  return Color.red.opacity(0.08)
        default:       return nil
        }
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $detailMode) {
                ForEach(DetailMode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)
            .onChange(of: state.xmlPreview.isEmpty) { _, isEmpty in
                if isEmpty { detailMode = .image }
            }
            Divider()
            switch detailMode {
            case .image: imagePreview
            case .xml: xmlPreviewView
            }
        }
        .overlay(alignment: .bottom) {
            if state.showSavedToast, let url = state.lastSavedURL {
                savedToast(url: url)
            }
        }
        .animation(.spring(duration: 0.25), value: state.showSavedToast)
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let page = state.selectedPage {
            ImageBoxView(url: page.url,
                         lines: page.result?.lines ?? [],
                         imageSize: page.result?.imageSize)
        } else {
            ContentUnavailableView("No image selected",
                                   systemImage: "photo",
                                   description: Text("Select a page in the sidebar."))
        }
    }

    @ViewBuilder
    private var xmlPreviewView: some View {
        if state.xmlPreview.isEmpty {
            ContentUnavailableView("No TEI output yet",
                                   systemImage: "doc.text",
                                   description: Text("Run OCR to generate a TEI/XML preview."))
        } else {
            CodeTextView(text: state.xmlPreview)
        }
    }

    private func savedToast(url: URL) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text("Saved to \(url.path(percentEncoded: false))")
                .lineLimit(1)
                .truncationMode(.middle)
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            .buttonStyle(.link)
            Button {
                state.showSavedToast = false
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 6, y: 2)
        .padding(.bottom, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - File operations

    private func parseLaunchArgs() {
        let args = CommandLine.arguments

        if let i = args.firstIndex(of: "--demo-folder"), i + 1 < args.count {
            let url = URL(fileURLWithPath: args[i + 1])
            if FileManager.default.fileExists(atPath: url.path) {
                state.loadFolder(url)
            }
        }

        if let i = args.firstIndex(of: "--show-tab"), i + 1 < args.count {
            switch args[i + 1] {
            case "xml": detailMode = .xml
            case "image": detailMode = .image
            default: break
            }
        }

        if args.contains("--auto-run-ocr") && !state.pages.isEmpty {
            Task { await state.runOCRAll() }
        }

        if let i = args.firstIndex(of: "--screenshot"), i + 1 < args.count {
            let pathArg = args[i + 1]
            var delay: Double = 1.5
            if let di = args.firstIndex(of: "--screenshot-delay"), di + 1 < args.count,
               let d = Double(args[di + 1]) {
                delay = d
            }
            screenshotMode = true
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                captureFrontWindow(toPathArg: pathArg)
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func captureFrontWindow(toPathArg pathArg: String) {
        // Render via Cocoa's bitmap cache. `screenshotMode` swaps the
        // NavigationSplitView (which uses an NSVisualEffectView sidebar that
        // does not capture via this API) for a flat HStack so all regions
        // appear in the bitmap.
        let visible = NSApplication.shared.windows.filter { $0.isVisible }
        guard let window = visible.first ?? NSApplication.shared.windows.first,
              let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        if pathArg == "-" {
            FileHandle.standardOutput.write(data)
        } else {
            try? data.write(to: URL(fileURLWithPath: pathArg))
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            let folder = isDir.boolValue ? url : url.deletingLastPathComponent()
            Task { @MainActor in state.loadFolder(folder) }
        }
        return true
    }

    private func loadBundledSample() {
        guard let url = Bundle.main.url(forResource: "SamplePages", withExtension: nil) else {
            return
        }
        state.loadFolder(url)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select folder of page images"
        if panel.runModal() == .OK, let url = panel.url {
            state.loadFolder(url)
        }
    }

    private func saveXML() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.xml]
        panel.nameFieldStringValue = "\(sanitize(state.meta.title)).xml"
        if panel.runModal() == .OK, let url = panel.url {
            do { try state.saveXML(to: url) }
            catch {
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }
    }

    private func exportBundle() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = sanitize(state.meta.title)
        panel.prompt = String(localized: "Export Bundle")
        panel.message = String(localized: "Choose where to create the bundle folder (tei.xml + images/ + index.html).")
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do { try state.exportBundle(to: url) }
            catch {
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }
    }

    private func sanitize(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_"))
        return s.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "_" }
            .reduce(into: "") { $0.append($1) }
    }
}

// MARK: - File menu hook

private struct ExportTEIKey: FocusedValueKey { typealias Value = () -> Void }
extension FocusedValues {
    var exportTEIAction: (() -> Void)? {
        get { self[ExportTEIKey.self] }
        set { self[ExportTEIKey.self] = newValue }
    }
}
