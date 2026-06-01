import AppKit
import SwiftUI

/// Contents of the drop-down capture strip: a horizontally scrolling row of
/// large, draggable thumbnails with a copy-path action on each. Reuses the
/// shared `PopoverViewModel` so it stays in sync with the menu-bar popover.
struct CaptureStripView: View {
    @ObservedObject var viewModel: PopoverViewModel
    var onClose: () -> Void
    /// Reports when a tile enters/leaves inline rename, so the window can suppress
    /// pointer auto-hide while the user is typing a new name.
    var onEditingChanged: (Bool) -> Void = { _ in }

    private let cornerRadius: CGFloat = 14

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(BottomRoundedRectangle(radius: cornerRadius))
        .overlay(
            BottomRoundedRectangle(radius: cornerRadius)
                .stroke(Color.black.opacity(0.18), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 12, weight: .semibold))
            Text("ImageGrab")
                .font(.system(size: 12, weight: .semibold))
            Text("drag a capture out, or copy its path")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.entries.isEmpty {
            VStack {
                Spacer()
                Text("No captures yet — grab one with ⌃⌥G")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.entries, id: \.id) { entry in
                        CaptureStripTile(viewModel: viewModel, entry: entry, onEditingChanged: onEditingChanged)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
    }
}

private struct CaptureStripTile: View {
    @ObservedObject var viewModel: PopoverViewModel
    let entry: CaptureEntry
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var thumbnail: NSImage?
    @State private var copied = false
    @State private var hovered = false
    @State private var isEditingName = false
    @State private var draftName = ""
    @State private var renameHovered = false
    @FocusState private var nameFieldFocused: Bool

    private let tileWidth: CGFloat = 172
    private let imageHeight: CGFloat = 118

    private var name: String { (entry.filename as NSString).deletingPathExtension }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(5)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 22))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: tileWidth, height: imageHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(hovered ? Color.accentColor : Color.white.opacity(0.12),
                            lineWidth: hovered ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onDrag { viewModel.makeDragProvider(for: entry) }
            .help("Drag to insert this capture")

            // Name row with inline rename
            HStack(spacing: 4) {
                if isEditingName {
                    TextField("", text: $draftName, onCommit: commitRename)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10))
                        .focused($nameFieldFocused)
                        .onExitCommand(perform: cancelRename)
                    Button(action: cancelRename) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Cancel")
                } else {
                    Text(name)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(.secondary)
                    Button(action: startRename) {
                        Image(systemName: "pencil")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(renameHovered ? Color.accentColor : Color.secondary)
                            .frame(width: 20, height: 18)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(renameHovered ? Color.accentColor.opacity(0.14) : Color.clear)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .onHover { renameHovered = $0 }
                    .help("Rename capture")
                }
            }
            .frame(width: tileWidth)

            Button(action: copyPath) {
                Label(copied ? "Copied" : "Copy path", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: tileWidth, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(copied ? Color.green.opacity(0.28) : Color.secondary.opacity(0.16))
                    )
            }
            .buttonStyle(.plain)
            .help("Copy file path to clipboard")
        }
        .onHover { hovered = $0 }
        .task(id: entry.id) {
            thumbnail = await viewModel.thumbnailImage(for: entry)
        }
    }

    private func copyPath() {
        viewModel.copyPath(for: entry)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            copied = false
        }
    }

    private func startRename() {
        draftName = name
        isEditingName = true
        onEditingChanged(true)
        DispatchQueue.main.async { nameFieldFocused = true }
    }

    private func commitRename() {
        let proposed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !proposed.isEmpty, proposed != name, !viewModel.rename(id: entry.id, to: proposed) {
            NSSound.beep()
        }
        finishEditing()
    }

    private func cancelRename() {
        draftName = ""
        finishEditing()
    }

    private func finishEditing() {
        isEditingName = false
        nameFieldFocused = false
        onEditingChanged(false)
    }
}

/// A rectangle with only its bottom corners rounded, so the strip reads as a
/// panel that has dropped flush from the top edge of the screen.
private struct BottomRoundedRectangle: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}
