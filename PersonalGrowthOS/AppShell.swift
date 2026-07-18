import ImageIO
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

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                TodayView(openCapture: { isCapturing = true })
            }
            .tabItem { Label("Today", systemImage: "sun.max") }
            .tag(AppTab.today)

            NavigationStack {
                TimelineView(mediaStore: container.mediaStore)
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
    }
}

private struct TodayView: View {
    let openCapture: () -> Void

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
    }
}

private struct TimelineView: View {
    let mediaStore: MediaStore

    @Query(sort: [
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
                    TimelineRow(entry: entry, mediaStore: mediaStore)
                }
            }
        }
        .navigationTitle("Timeline")
        .accessibilityIdentifier("timeline-view")
    }
}

private struct TimelineRow: View {
    let entry: Entry
    let mediaStore: MediaStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = entry.title, !title.isEmpty {
                Text(title).font(.headline)
            }
            if let body = entry.body, !body.isEmpty {
                Text(body)
            }
            if let image = entry.images.sorted(by: { $0.sortOrder < $1.sortOrder }).first {
                DownsampledOriginalView(mediaStore: mediaStore, relativePath: image.relativePath)
            }
            Text(entry.occurredAt, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("timeline-entry-\(entry.id.uuidString)")
    }
}

private struct DownsampledOriginalView: View {
    let mediaStore: MediaStore
    let relativePath: String

    var body: some View {
        if let image = downsampledImage() {
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

    private func downsampledImage() -> UIImage? {
        guard let url = try? mediaStore.fileURL(for: relativePath),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 512
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

extension Entry: Identifiable {}
