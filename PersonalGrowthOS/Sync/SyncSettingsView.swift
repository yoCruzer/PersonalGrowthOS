import SwiftUI

struct SyncSettingsView: View {
    @ObservedObject var coordinator: SyncProductCoordinator
    @State private var confirmsEnable = false
    @State private var confirmsInitialSetup = false
    @State private var selectedConflict: SyncConflictSummary?
    var body: some View {
        List {
            Section {
                Text(coordinator.status).accessibilityIdentifier("sync-status")
                if coordinator.busy { ProgressView() }
                if coordinator.enabled {
                    Button("Sync now") { Task { await coordinator.synchronize() } }.disabled(coordinator.busy)
                    Button("Turn off iCloud sync") { Task { await coordinator.disable() } }
                } else {
                    Button("Enable iCloud sync") { confirmsEnable = true }.disabled(coordinator.busy).accessibilityIdentifier("sync-enable")
                }
                if coordinator.canConfirmInitialZoneCreation {
                    Button("Set up iCloud workspace") { confirmsInitialSetup = true }.disabled(coordinator.busy)
                }
                LabeledContent("Pending revisions", value: "\(coordinator.pendingCount)")
            } header: { Text("iCloud sync") }
            footer: { Text("Sync uses your iCloud private database. Turning it off keeps local data and queued changes. Photos may use additional iCloud storage.") }
            if !coordinator.conflicts.isEmpty {
                Section("Versions to review") {
                    ForEach(coordinator.conflicts) { conflict in
                        Button { selectedConflict = conflict } label: {
                            VStack(alignment: .leading) {
                                Text(conflict.key.kind.displayName)
                                Text("\(conflict.heads.count) concurrent versions")
                            }
                        }
                    }
                }
            }
            Section {
                Text("This development version has local validation. Real iCloud and Production acceptance are not yet complete. Keep an exported backup before using sync with important data.")
            }
        }
        .navigationTitle("iCloud sync")
        .alert("Upload this workspace to iCloud?", isPresented: $confirmsEnable) {
            Button("Cancel", role: .cancel) {}
            Button("Enable") { Task { await coordinator.enable() } }
        } message: { Text("Existing records and original photos will be uploaded to the currently signed-in iCloud account. Other installations using that account can receive them. Concurrent edits are kept for review.") }
        .alert("Set up this iCloud workspace?", isPresented: $confirmsInitialSetup) {
            Button("Cancel", role: .cancel) { _ = coordinator.takeInitialZoneConsent() }
            Button("Create workspace") { Task { await coordinator.confirmInitialZoneCreation() } }
        } message: {
            Text("The previous setup was not confirmed and iCloud reports no workspace. Create it using the local records and photos kept on this device? This cannot restore anything that existed only in iCloud.")
        }
        .sheet(item: $selectedConflict) { conflict in
            SyncConflictView(coordinator: coordinator, conflict: conflict)
        }
        .onAppear { coordinator.refreshStatus() }
    }
}

private struct SyncConflictView: View {
    @ObservedObject var coordinator: SyncProductCoordinator
    let conflict: SyncConflictSummary
    @Environment(\.dismiss) private var dismiss
    @State private var versions: [SyncConflictVersion] = []
    @State private var selected: SyncConflictVersion?
    @State private var failure: String?
    var body: some View {
        NavigationStack {
            List {
                Text("Review every version. Choosing one creates a new revision that resolves all versions shown; the originals remain in sync history.")
                ForEach(versions) { version in
                    Section(version.deleted ? "Deleted version" : "Saved version") {
                        Text("Received \(version.receivedAt.formatted())").font(.caption)
                        Text(version.payload).font(.body).textSelection(.enabled)
                        Button(version.deleted ? "Keep deletion" : "Keep this version") { selected = version }
                    }
                }
                if versions.count < conflict.heads.count { Text("Some version contents are still downloading. Sync again before resolving.") }
                if let failure { Text(failure).foregroundStyle(.red) }
            }
            .navigationTitle("Resolve versions")
            .toolbar { Button("Done") { dismiss() } }
            .onAppear {
                do { versions = try coordinator.conflictVersions(conflict) }
                catch { failure = String(describing: error) }
            }
            .confirmationDialog("Keep this version and resolve all concurrent versions?", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
                Button("Keep selected version", role: selected?.deleted == true ? .destructive : nil) {
                    guard let selected else { return }
                    do { try coordinator.resolve(conflict, choosing: selected.id); dismiss() }
                    catch { failure = String(describing: error) }
                    self.selected = nil
                }
            }
        }
    }
}

struct SyncStatusBanner: View {
    @ObservedObject var coordinator: SyncProductCoordinator
    var body: some View {
        if coordinator.enabled && coordinator.requiresAttention {
            Text(coordinator.status).font(.caption).padding(8).frame(maxWidth: .infinity)
                .background(.orange.opacity(0.12)).accessibilityIdentifier("sync-incomplete-banner")
        }
    }
}


extension SyncDomainKind {
    var displayName: String {
        switch self {
        case .entry: return String(localized: "Life record")
        case .tag: return String(localized: "Tag")
        case .objectLink: return String(localized: "Record connection")
        case .habit: return String(localized: "Habit")
        case .habitLog: return String(localized: "Habit check-in")
        case .goal: return String(localized: "Goal")
        case .weight: return String(localized: "Weight record")
        case .weeklyReview: return String(localized: "Weekly review")
        case .todoList: return String(localized: "Task list")
        case .todoSeries: return String(localized: "Recurring tasks")
        case .todoTask: return String(localized: "Task")
        case .importantDay: return String(localized: "Important day")
        case .importantDayEntryLink: return String(localized: "Day memory")
        case .importantDayTodoLink: return String(localized: "Day task")
        case .sleepRecord: return String(localized: "Sleep record")
        case .sleepGoal: return String(localized: "Sleep goal")
        case .captureReceipt: return String(localized: "Shared record receipt")
        case .investmentParticipant: return String(localized: "Participant")
        case .investmentActivity: return String(localized: "Activity")
        case .investmentRecord: return String(localized: "Time investment")
        case .bodyReference: return String(localized: "Body reference")
        case .netWorthItem: return String(localized: "Asset or liability")
        case .netWorthSnapshot: return String(localized: "Net worth snapshot")
        }
    }
}
