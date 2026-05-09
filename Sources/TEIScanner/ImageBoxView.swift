import SwiftUI
import AppKit

struct ImageBoxView: View {
    let url: URL
    let lines: [OCRLine]
    let imageSize: CGSize?

    @State private var hoveredLineID: OCRLine.ID?
    @State private var zoom: CGFloat = 1.0
    @State private var pinchStart: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var dragStart: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            if lines.isEmpty {
                canvas
            } else {
                HSplitView {
                    canvas
                        .frame(minWidth: 300)
                    lineList
                        .frame(minWidth: 220, idealWidth: 280)
                }
            }
        }
        .onChange(of: url) { _, _ in resetView() }
    }

    private var lineList: some View {
        Group {
            if lines.isEmpty {
                ContentUnavailableView("No OCR lines",
                                       systemImage: "text.alignleft",
                                       description: Text("Run OCR to populate."))
            } else {
                List {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { idx, line in
                        HStack(alignment: .top, spacing: 6) {
                            Text("\(idx + 1)")
                                .font(.caption2.bold())
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.red.opacity(hoveredLineID == line.id ? 1.0 : 0.7))
                                .foregroundStyle(.white)
                                .cornerRadius(3)
                            Text(line.text)
                                .font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(nil)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 1)
                        .background(hoveredLineID == line.id ? Color.accentColor.opacity(0.15) : Color.clear)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            hoveredLineID = hovering ? line.id : (hoveredLineID == line.id ? nil : hoveredLineID)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button { adjustZoom(by: 1 / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }
            Text(String(format: "%.0f%%", zoom * 100))
                .frame(width: 56)
                .monospacedDigit()
            Button { adjustZoom(by: 1.25) } label: { Image(systemName: "plus.magnifyingglass") }
            Divider().frame(height: 16)
            Button("Fit") { resetView() }
            Button("100%") {
                zoom = 1
                offset = .zero
            }
            Spacer()
            Text("\(lines.count) lines")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var canvas: some View {
        GeometryReader { geo in
            let nsImage = NSImage(contentsOf: url)
            let intrinsic = imageSize ?? nsImage?.size ?? CGSize(width: 1, height: 1)
            let fitScale = min(geo.size.width / intrinsic.width,
                               geo.size.height / intrinsic.height)
            let scale = fitScale * zoom
            let displaySize = CGSize(width: intrinsic.width * scale,
                                     height: intrinsic.height * scale)
            let originX = (geo.size.width - displaySize.width) / 2 + offset.width
            let originY = (geo.size.height - displaySize.height) / 2 + offset.height

            ZStack(alignment: .topLeading) {
                Color(nsColor: .windowBackgroundColor)
                if let nsImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .interpolation(.medium)
                        .frame(width: displaySize.width, height: displaySize.height)
                        .offset(x: originX, y: originY)
                }
                ForEach(Array(lines.enumerated()), id: \.element.id) { idx, line in
                    let rect = CGRect(
                        x: originX + line.box.origin.x * scale,
                        y: originY + line.box.origin.y * scale,
                        width: line.box.size.width * scale,
                        height: line.box.size.height * scale
                    )
                    let isHovered = hoveredLineID == line.id
                    Rectangle()
                        .stroke(isHovered ? Color.accentColor : Color.red.opacity(0.7),
                                lineWidth: isHovered ? 2 : 1)
                        .background(
                            Rectangle().fill(isHovered ? Color.accentColor.opacity(0.15) : Color.clear)
                        )
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.origin.x, y: rect.origin.y)
                        .help("\(idx + 1). \(line.text)")
                        .onHover { hovering in
                            hoveredLineID = hovering ? line.id : (hoveredLineID == line.id ? nil : hoveredLineID)
                        }
                    Text("\(idx + 1)")
                        .font(.caption2.bold())
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.red.opacity(0.85))
                        .foregroundStyle(.white)
                        .cornerRadius(2)
                        .offset(x: rect.origin.x, y: max(rect.origin.y - 14, 0))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(magnification)
            .gesture(panning)
        }
    }

    private var magnification: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                zoom = clamp(pinchStart * value)
            }
            .onEnded { _ in pinchStart = zoom }
    }

    private var panning: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(width: dragStart.width + value.translation.width,
                                height: dragStart.height + value.translation.height)
            }
            .onEnded { _ in dragStart = offset }
    }

    private func adjustZoom(by factor: CGFloat) {
        zoom = clamp(zoom * factor)
        pinchStart = zoom
    }

    private func resetView() {
        zoom = 1
        pinchStart = 1
        offset = .zero
        dragStart = .zero
    }

    private func clamp(_ z: CGFloat) -> CGFloat { min(max(z, 0.1), 20) }
}
