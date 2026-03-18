import SwiftUI
import UniformTypeIdentifiers

struct ImageGrabPopoverView: View {
    @ObservedObject var viewModel: PopoverViewModel
    @State private var editingID: UUID?
    @State private var editText = ""
    @State private var copiedID: UUID?
    @State private var hoveredID: UUID?
    @State private var showClearAllConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("ImageGrab")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.entries.count) captures")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        VStack(spacing: 4) {
            // Thumbnail with hover-only copy overlay
            if let thumb = viewModel.thumbnailImage(for: entry) {
                ZStack(alignment: .topTrailing) {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(copiedID == entry.id ? Color.green : Color.clear, lineWidth: 2)
                        )

                    // Copy button — appears on hover
                    if hoveredID == entry.id || copiedID == entry.id {
                        Button {
                            copyPath(for: entry)
                        } label: {
                            Image(systemName: copiedID == entry.id ? "checkmark.circle.fill" : "doc.on.doc")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(copiedID == entry.id ? .green : .white)
                                .padding(5)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                        .padding(4)
                        .transition(.opacity)
                    }
                }
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        hoveredID = hovering ? entry.id : nil
                    }
                }
                .onTapGesture {
                    copyPath(for: entry)
                }
                .contextMenu {
                    Button {
                        copyPath(for: entry)
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
                        editingID = entry.id
                        editText = (entry.filename as NSString).deletingPathExtension
                    } label: {
                        Label("Edit Name", systemImage: "pencil")
                    }
                    Divider()
                    Button(role: .destructive) {
                        viewModel.delete(id: entry.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .onDrag {
                    viewModel.onDragStarted?()

                    let url = URL(fileURLWithPath: viewModel.fullPath(for: entry))
                    let provider = NSItemProvider()
                    provider.suggestedName = entry.filename

                    // File URL for Electron/browser drop targets
                    provider.registerObject(url as NSURL, visibility: .all)

                    // Raw PNG data for apps that accept image data directly
                    if let imageData = try? Data(contentsOf: url) {
                        provider.registerDataRepresentation(
                            forTypeIdentifier: UTType.png.identifier,
                            visibility: .all
                        ) { completion in
                            completion(imageData, nil)
                            return nil
                        }
                    }

                    // File representation for file-system-aware apps (Finder, etc.)
                    provider.registerFileRepresentation(
                        forTypeIdentifier: UTType.png.identifier,
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
            }

            // Name
            if editingID == entry.id {
                TextField("Name", text: $editText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 9))
                    .onSubmit {
                        if !editText.isEmpty {
                            viewModel.rename(id: entry.id, to: editText)
                        }
                        editingID = nil
                    }
            } else {
                HStack(spacing: 2) {
                    if entry.aiNamed {
                        Image(systemName: "sparkles")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    Text((entry.filename as NSString).deletingPathExtension)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .onTapGesture {
                            editingID = entry.id
                            editText = (entry.filename as NSString).deletingPathExtension
                        }
                }
            }
        }
    }

    private func copyPath(for entry: CaptureEntry) {
        viewModel.copyPath(for: entry)
        copiedID = entry.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if copiedID == entry.id { copiedID = nil }
        }
    }
}
