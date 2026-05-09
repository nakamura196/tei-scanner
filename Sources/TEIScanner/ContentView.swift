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

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            detail
        }
        .navigationTitle("TEI Scanner")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    chooseFolder()
                } label: {
                    Label("Choose folder", systemImage: "folder")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await state.runOCRAll() }
                } label: {
                    Label("Run OCR", systemImage: "text.viewfinder")
                }
                .disabled(state.pages.isEmpty || state.isProcessing)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    saveXML()
                } label: {
                    Label("Save XML", systemImage: "square.and.arrow.down")
                }
                .disabled(state.xmlPreview.isEmpty)
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            metadataBox
            Divider()
            if state.pages.isEmpty {
                ContentUnavailableView("No folder selected",
                                       systemImage: "folder.badge.questionmark",
                                       description: Text("Choose a folder of page images to begin."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: Binding(
                    get: { state.selectedPageID },
                    set: { state.selectedPageID = $0 }
                )) {
                    ForEach(state.pages) { page in
                        pageRow(page).tag(Optional(page.id))
                    }
                }
                .listStyle(.inset)
            }
            if state.isProcessing {
                ProgressView(state.progressText)
                    .progressViewStyle(.linear)
                    .padding(8)
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
            Text("Pending").font(.caption).foregroundStyle(.secondary)
        case .running:
            Text("Running…").font(.caption).foregroundStyle(.blue)
        case .done(let n):
            Text("\(n) lines").font(.caption).foregroundStyle(.green)
        case .failed(let msg):
            Text("Failed: \(msg)").font(.caption).foregroundStyle(.red).lineLimit(2)
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
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let page = state.selectedPage {
            ImageBoxView(url: page.url, lines: page.result?.lines ?? [], imageSize: page.result?.imageSize)
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
            ScrollView {
                Text(state.xmlPreview)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
    }

    // MARK: - File operations

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
        return s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }.reduce(into: "") { $0.append($1) }
    }
}
