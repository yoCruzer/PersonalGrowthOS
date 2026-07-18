import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case today
    case timeline
}

struct AppShell: View {
    let container: AppContainer

    @State private var selectedTab: AppTab = .today
    @State private var isCapturing = false
    @State private var isShowingStorage = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                TodayView(
                    openCapture: { isCapturing = true },
                    openStorage: { isShowingStorage = true }
                )
            }
            .tabItem { Label("Today", systemImage: "sun.max") }
            .tag(AppTab.today)

            NavigationStack {
                TimelineView(
                    mediaStore: container.mediaStore,
                    thumbnailStore: container.thumbnailStore
                )
            }
            .tabItem { Label("Timeline", systemImage: "clock") }
            .tag(AppTab.timeline)
        }
        .accessibilityIdentifier("app-shell")
        .sheet(isPresented: $isCapturing) {
            QuickCaptureView(mediaStore: container.mediaStore) {
                selectedTab = .timeline
                isCapturing = false
            }
        }
        .sheet(isPresented: $isShowingStorage) {
            MediaStorageView(
                mediaStore: container.mediaStore,
                integrityReport: container.mediaIntegrityReport
            )
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                isCapturing = true
            } label: {
                Image(systemName: "plus")
                    .font(.title2.bold())
                    .frame(width: 52, height: 52)
                    .background(.tint, in: Circle())
                    .foregroundStyle(.white)
                    .shadow(radius: 4, y: 2)
            }
            .accessibilityLabel("Quick Capture")
            .accessibilityIdentifier("global-capture-button")
            .padding(.trailing, 20)
            .padding(.bottom, 72)
        }
    }
}

private struct TodayView: View {
    let openCapture: () -> Void
    let openStorage: () -> Void

    var body: some View {
        List {
            Section {
                Button(action: openCapture) {
                    Label("Quick Capture", systemImage: "square.and.pencil")
                        .font(.headline)
                }
                .accessibilityIdentifier("quick-capture-button")
            } footer: {
                Text("Save a thought or photo now. Organize it later if you want.")
            }
        }
        .navigationTitle("Today")
        .toolbar {
            Button(action: openStorage) {
                Image(systemName: "gear")
            }
            .accessibilityLabel("Settings")
        }
    }
}

private struct TimelineView: View {
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore

    @Query(sort: [
        SortDescriptor(\Entry.occurredAt, order: .reverse),
        SortDescriptor(\Entry.createdAt, order: .reverse),
        SortDescriptor(\Entry.id, order: .forward)
    ]) private var entries: [Entry]
    @State private var showsArchived = false

    private var displayedEntries: [Entry] {
        entries.filter { showsArchived ? $0.status == .archived : $0.status != .archived }
    }

    var body: some View {
        Group {
            if displayedEntries.isEmpty {
                ContentUnavailableView(
                    showsArchived ? "No Archived Entries" : "No Entries Yet",
                    systemImage: showsArchived ? "archivebox" : "clock",
                    description: Text(showsArchived ? "Archived entries will appear here." : "Your captures will appear here.")
                )
            } else {
                List(displayedEntries) { entry in
                    NavigationLink {
                        EntryDetailView(
                            entry: entry,
                            mediaStore: mediaStore,
                            thumbnailStore: thumbnailStore
                        )
                    } label: {
                        TimelineRow(entry: entry, thumbnailStore: thumbnailStore)
                    }
                }
            }
        }
        .navigationTitle("Timeline")
        .toolbar {
            Button {
                showsArchived.toggle()
            } label: {
                Label(
                    showsArchived ? "Show Active" : "Show Archived",
                    systemImage: showsArchived ? "clock" : "archivebox"
                )
            }
        }
        .accessibilityIdentifier("timeline-view")
    }
}

private struct MediaStorageView: View {
    let mediaStore: MediaStore
    let integrityReport: MediaIntegrityReport

    @Environment(\.dismiss) private var dismiss
    @State private var byteCount: Int64?
    @State private var isCapturing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Original photos") {
                        if let byteCount {
                            Text(ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))
                        } else {
                            ProgressView()
                        }
                    }
                } header: {
                    Text("Media Storage")
                } footer: {
                    Text("Original photos are stored privately on this device.")
                }
                if integrityReport.requiresAttention {
                    Section {
                        if !integrityReport.missingOriginalPaths.isEmpty {
                            Label(
                                "\(integrityReport.missingOriginalPaths.count) photo(s) are missing",
                                systemImage: "exclamationmark.triangle"
                            )
                        }
                        if !integrityReport.recoveryFilePaths.isEmpty {
                            Label(
                                "\(integrityReport.recoveryFilePaths.count) unlinked photo(s) were preserved",
                                systemImage: "lifepreserver"
                            )
                        }
                    } header: {
                        Text("Recovery")
                    } footer: {
                        Text("The app preserved recoverable files instead of deleting them. Keep an app backup before troubleshooting.")
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isCapturing = true
                    } label: {
                        Label("Quick Capture", systemImage: "plus")
                    }
                    .accessibilityIdentifier("settings-capture-button")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                byteCount = try? mediaStore.originalsByteCount()
            }
            .sheet(isPresented: $isCapturing) {
                QuickCaptureView(mediaStore: mediaStore) {
                    isCapturing = false
                    byteCount = try? mediaStore.originalsByteCount()
                }
            }
        }
    }
}

private struct TimelineRow: View {
    let entry: Entry
    let thumbnailStore: ThumbnailStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = entry.title, !title.isEmpty {
                Text(title).font(.headline)
            }
            if let body = entry.body, !body.isEmpty {
                Text(body)
            }
            if let image = entry.images.sorted(by: { $0.sortOrder < $1.sortOrder }).first {
                DownsampledOriginalView(
                    metadata: image,
                    thumbnailStore: thumbnailStore,
                    accessibilityLabel: "First photo in entry"
                )
            }
            Text(entry.occurredAt, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("timeline-entry-\(entry.id.uuidString)")
    }
}

struct DownsampledOriginalView: View {
    let metadata: ImageMetadata
    let thumbnailStore: ThumbnailStore
    var accessibilityLabel = "Entry photo"

    var body: some View {
        if let image = thumbnailStore.image(for: metadata) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel(accessibilityLabel)
        } else {
            Label("Image unavailable", systemImage: "photo.badge.exclamationmark")
                .foregroundStyle(.secondary)
        }
    }

}

extension Entry: Identifiable {}
