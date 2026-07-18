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
            MediaStorageView(mediaStore: container.mediaStore)
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

    @Query(filter: #Predicate<Entry> { $0.statusRawValue != "archived" }, sort: [
        SortDescriptor(\Entry.occurredAt, order: .reverse),
        SortDescriptor(\Entry.createdAt, order: .reverse)
    ]) private var entries: [Entry]

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Entries Yet",
                    systemImage: "clock",
                    description: Text("Your captures will appear here.")
                )
            } else {
                List(entries) { entry in
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
        .accessibilityIdentifier("timeline-view")
    }
}

private struct MediaStorageView: View {
    let mediaStore: MediaStore

    @Environment(\.dismiss) private var dismiss
    @State private var byteCount: Int64?

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
            }
            .navigationTitle("Settings")
            .toolbar {
                Button("Done") { dismiss() }
            }
            .task {
                byteCount = try? mediaStore.originalsByteCount()
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
                DownsampledOriginalView(metadata: image, thumbnailStore: thumbnailStore)
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

    var body: some View {
        if let image = thumbnailStore.image(for: metadata) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            Label("Image unavailable", systemImage: "photo.badge.exclamationmark")
                .foregroundStyle(.secondary)
        }
    }

}

extension Entry: Identifiable {}
