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

    var body: some View {
        Group {
            if state.pages.isEmpty {
                emptyState
            } else {
                NavigationSplitView {
                    sidebar.navigationSplitViewColumnWidth(min: 260, ideal: 320)
                } detail: {
                    detail
                }
            }
        }
        .navigationTitle("TEI Scanner")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    chooseFolder()
                } label: {
                    Label(state.pages.isEmpty ? "Choose folder" : "Change folder",
                          systemImage: "folder")
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await state.runOCRAll() }
                } label: {
                    Label("Run OCR", systemImage: "text.viewfinder")
                }
                .disabled(state.pages.isEmpty || state.isProcessing)
                .keyboardShortcut(.return, modifiers: .command)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    saveXML()
                } label: {
                    Label("Export TEI/XML", systemImage: "arrow.down.doc")
                }
                .disabled(state.xmlPreview.isEmpty)
            }
        }
        .focusedSceneValue(\.exportTEIAction, state.xmlPreview.isEmpty ? nil : { saveXML() })
        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)
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
                set: { state.meta.title = $0; state.rebuildPreview() }
            ))
            TextField("Responsible name", text: Binding(
                get: { state.meta.responsibleName },
                set: { state.meta.responsibleName = $0; state.rebuildPreview() }
            ))
            TextField("Language (ISO)", text: Binding(
                get: { state.meta.language },
                set: { state.meta.language = $0; state.rebuildPreview() }
            ))
            TextField("Date (YYYY-MM-DD)", text: Binding(
                get: { state.meta.date },
                set: { state.meta.date = $0; state.rebuildPreview() }
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
                .overlay(alignment: .bottom) { ocrCTAOverlay }
        } else {
            ContentUnavailableView("No image selected",
                                   systemImage: "photo",
                                   description: Text("Select a page in the sidebar."))
        }
    }

    @ViewBuilder
    private var ocrCTAOverlay: some View {
        if !state.pages.isEmpty && !state.hasAnyOCRResult && !state.isProcessing {
            HStack(spacing: 14) {
                Image(systemName: "text.viewfinder").font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(state.pages.count) page\(state.pages.count == 1 ? "" : "s") ready")
                        .font(.headline)
                    Text("Next step: run OCR to extract text.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await state.runOCRAll() }
                } label: {
                    Label("Run OCR on \(state.pages.count) page\(state.pages.count == 1 ? "" : "s")",
                          systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12).stroke(.separator)
            )
            .padding(20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if state.isProcessing {
            HStack(spacing: 12) {
                ProgressView(value: Double(state.doneCount), total: Double(max(state.pages.count, 1)))
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 220)
                Text("\(state.doneCount)/\(state.pages.count)")
                    .monospacedDigit().font(.callout)
                Text(state.progressText)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(12)
            .background(.regularMaterial, in: Capsule())
            .padding(20)
        }
    }

    @ViewBuilder
    private var xmlPreviewView: some View {
        if state.xmlPreview.isEmpty {
            ContentUnavailableView("No TEI output yet",
                                   systemImage: "doc.text",
                                   description: Text("Run OCR to generate a TEI/XML preview."))
        } else {
            VStack(spacing: 0) {
                ScrollView {
                    Text(state.xmlPreview)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                Divider()
                HStack {
                    Text("\(state.xmlPreview.count) chars")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        saveXML()
                    } label: {
                        Label("Export TEI/XML…", systemImage: "arrow.down.doc")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: .command)
                }
                .padding(10)
            }
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
