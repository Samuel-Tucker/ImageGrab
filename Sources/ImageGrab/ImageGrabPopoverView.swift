import SwiftUI
import UniformTypeIdentifiers

struct ImageGrabPopoverView: View {
    @ObservedObject var viewModel: PopoverViewModel
    let onClose: () -> Void
    @State private var editingID: UUID?
    @State private var editText = ""
    @State private var originalEditText = ""
    @State private var copiedID: UUID?
    @State private var hoveredID: UUID?
    @State private var showClearAllConfirm = false
    @FocusState private var isRenameFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("ImageGrab")
                    .font(.headline)
                Text("Ctrl+Opt+G")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(viewModel.entries.count) captures")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Hide ImageGrab")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if viewModel.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "camera.viewfinder")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No captures yet")
                        .foregroundStyle(.secondary)
                    Text("Copy an image, then press ctl+opt+G")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 10) {
                        ForEach(viewModel.entries) { entry in
                            captureCell(entry)
                        }
                    }
                    .padding(8)
                }
            }

            Divider()

            // Footer — pill-style buttons with SF Symbols
            HStack {
                Button {
                    viewModel.openFolder()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 10))
                        Text("Open Folder")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    showClearAllConfirm = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                        Text("Clear All")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .confirmationDialog(
                    "Delete all captures?",
                    isPresented: $showClearAllConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Clear All", role: .destructive) {
                        viewModel.clearAll()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This action cannot be undone.")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(width: 300, height: 400)
    }

    @ViewBuilder
    private func captureCell(_ entry: CaptureEntry) -> some View {
        CaptureCell(
            entry: entry,
            viewModel: viewModel,
            isCopied: copiedID == entry.id,
            isHovered: hoveredID == entry.id,
            isEditing: editingID == entry.id,
            editText: $editText,
            isRenameFieldFocused: $isRenameFieldFocused,
            onCopy: { copyPath(for: entry) },
            onQuickView: { viewModel.showQuickView(for: entry) },
            onHover: { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    hoveredID = hovering ? entry.id : nil
                }
            },
            onStartEditing: { startEditing(entry) },
            onCommitRename: { commitRename(for: entry) },
            onCancelRename: { editingID = nil },
            onDelete: { viewModel.delete(id: entry.id) }
        )
    }

    private func startEditing(_ entry: CaptureEntry) {
        let name = (entry.filename as NSString).deletingPathExtension
        editText = name
        originalEditText = name
        editingID = entry.id
    }

    private func commitRename(for entry: CaptureEntry) {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != originalEditText {
            viewModel.rename(id: entry.id, to: trimmed)
        }
        editingID = nil
    }

    private func copyPath(for entry: CaptureEntry) {
        viewModel.copyPath(for: entry)
        copiedID = entry.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if copiedID == entry.id { copiedID = nil }
        }
    }
}

// MARK: - CaptureCell (async thumbnail loading)

private struct CaptureCell: View {
    let entry: CaptureEntry
    let viewModel: PopoverViewModel
    let isCopied: Bool
    let isHovered: Bool
    let isEditing: Bool
    @Binding var editText: String
    var isRenameFieldFocused: FocusState<Bool>.Binding
    let onCopy: () -> Void
    let onQuickView: () -> Void
    let onHover: (Bool) -> Void
    let onStartEditing: () -> Void
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void
    let onDelete: () -> Void

    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            // Thumbnail with copy bar and quick view button
            ZStack(alignment: .bottom) {
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.quaternary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isCopied ? Color.green : Color.clear, lineWidth: 2)
                )
                .overlay(alignment: .topTrailing) {
                    if isHovered {
                        Button {
                            onQuickView()
                        } label: {
                            Image(systemName: "eye")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Color.black.opacity(0.65), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(4)
                        .transition(.opacity)
                    }
                }

                // Copy path button — always visible at bottom
                Button {
                    onCopy()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9, weight: .semibold))
                        Text(isCopied ? "Copied" : "Copy Path")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .foregroundStyle(isCopied ? .green : .white)
                    .background(Color.black.opacity(0.55))
                }
                .buttonStyle(.plain)
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6))
            }
            .onHover { hovering in
                onHover(hovering)
            }
            .contextMenu {
                Button {
                    onCopy()
                } label: {
                    Label("Copy Path", systemImage: "doc.on.doc")
                }
                Button {
                    let path = viewModel.fullPath(for: entry)
                    NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                Button {
                    onStartEditing()
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Divider()
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .onDrag {
                viewModel.onDragStarted?()

                let url = URL(fileURLWithPath: viewModel.fullPath(for: entry))
                let provider = NSItemProvider()
                provider.suggestedName = entry.filename

                let imageType = UTType(filenameExtension: url.pathExtension) ?? .png

                // File URL for Electron/browser drop targets
                provider.registerObject(url as NSURL, visibility: .all)

                // Raw image data for apps that accept image data directly
                if let imageData = try? Data(contentsOf: url) {
                    provider.registerDataRepresentation(
                        forTypeIdentifier: imageType.identifier,
                        visibility: .all
                    ) { completion in
                        completion(imageData, nil)
                        return nil
                    }
                }

                // File representation for file-system-aware apps (Finder, etc.)
                provider.registerFileRepresentation(
                    forTypeIdentifier: imageType.identifier,
                    fileOptions: [],
                    visibility: .all
                ) { completion in
                    completion(url, false, nil)
                    return nil
                }

                // Plain text path for terminal apps (Terminal.app, iTerm2)
                let shellPath = url.path.replacingOccurrences(of: " ", with: "\\ ")
                provider.registerDataRepresentation(
                    forTypeIdentifier: UTType.utf8PlainText.identifier,
                    visibility: .all
                ) { completion in
                    completion(shellPath.data(using: .utf8), nil)
                    return nil
                }

                return provider
            }
            .task(id: entry.filename) {
                thumbnail = await viewModel.thumbnailImage(for: entry)
            }

            // Name
            if isEditing {
                TextField("Name", text: $editText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 9))
                    .focused(isRenameFieldFocused)
                    .onAppear {
                        DispatchQueue.main.async {
                            isRenameFieldFocused.wrappedValue = true
                        }
                    }
                    .onSubmit {
                        onCommitRename()
                    }
                    .onExitCommand {
                        onCancelRename()
                    }
                    .onChange(of: isRenameFieldFocused.wrappedValue) { focused in
                        if !focused && isEditing {
                            onCommitRename()
                        }
                    }
            } else {
                Text((entry.filename as NSString).deletingPathExtension)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .onTapGesture {
                        onStartEditing()
                    }
            }
        }
    }
}
