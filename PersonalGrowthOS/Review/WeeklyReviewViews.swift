import SwiftData
import SwiftUI

struct WeeklyReviewView: View {
    let referenceDate: Date
    let weekIdentifier: String?

    private enum Field: Hashable {
        case remembered
        case improvement
        case nextStep
        case focus
    }

    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [Entry]
    @Query private var habits: [Habit]
    @Query private var habitLogs: [HabitLog]
    @Query private var weightRecords: [WeightRecord]
    @Query private var tags: [Tag]
    @Query private var links: [ObjectLink]
    @Query private var reviews: [WeeklyReview]

    @State private var rememberedText = ""
    @State private var improvementText = ""
    @State private var nextStepText = ""
    @State private var focusText = ""
    @State private var isCompleted = false
    @State private var isSaving = false
    @State private var editState: WeeklyReviewEditState?
    @State private var showsSaveConfirmation = false
    @State private var saveConfirmationTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    init(referenceDate: Date = Date()) {
        self.referenceDate = referenceDate
        weekIdentifier = nil
    }

    init(weekIdentifier: String) {
        referenceDate = Date()
        self.weekIdentifier = weekIdentifier
    }

    private var period: WeeklyReviewPeriod? {
        if let weekIdentifier {
            return try? WeeklyReviewPeriod(identifier: weekIdentifier)
        }
        return try? WeeklyReviewPeriod(containing: referenceDate)
    }

    private var currentReview: WeeklyReview? {
        guard let period else { return nil }
        return reviews.first { $0.weekIdentifier == period.identifier }
    }

    private var summary: WeeklySummary? {
        guard let period else { return nil }
        return WeeklySummaryService.make(
            period: period,
            entries: entries,
            habits: habits,
            habitLogs: habitLogs,
            weightRecords: weightRecords,
            tags: tags,
            links: links
        )
    }

    private var previousWeekFocus: String? {
        guard let period,
              let previousPeriod = try? period.previous(),
              let focus = reviews.first(where: {
                $0.weekIdentifier == previousPeriod.identifier
              })?.focusText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !focus.isEmpty else {
            return nil
        }
        return focus
    }

    private var draft: WeeklyReviewDraft {
        WeeklyReviewDraft(
            rememberedText: rememberedText,
            improvementText: improvementText,
            nextStepText: nextStepText,
            focusText: focusText,
            isCompleted: isCompleted
        )
    }

    private var isDirty: Bool {
        editState?.isDirty(draft) ?? false
    }

    var body: some View {
        List {
            if let period {
                Section("This Week") {
                    LabeledContent("Period") {
                        Text("\(period.start.formatted(date: .abbreviated, time: .omitted)) – \(period.end.formatted(date: .abbreviated, time: .omitted))")
                    }
                }

                if let summary {
                    summarySection(summary)
                }

                if let previousWeekFocus {
                    Section("Last Week’s Focus") {
                        Text(previousWeekFocus)
                            .accessibilityIdentifier("weekly-review-last-focus")
                    }
                }

                if currentReview != nil {
                    reflectionSections
                } else {
                    Section {
                        ContentUnavailableView(
                            "Reflect on this week",
                            systemImage: "text.book.closed",
                            description: Text("Start only when you are ready. Nothing is generated automatically.")
                        )
                        GrowthEmptyStateAddButton(
                            title: "Start Weekly Review",
                            systemImage: "square.and.pencil",
                            action: createReview
                        )
                        .accessibilityIdentifier("start-weekly-review")
                    }
                }
            } else {
                ContentUnavailableView(
                    "Weekly Review Unavailable",
                    systemImage: "calendar.badge.exclamationmark"
                )
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Weekly Review")
        .accessibilityIdentifier("weekly-review-view")
        .onAppear { loadDraft() }
        .onChange(of: currentReview?.id) { _, _ in loadDraft() }
        .onChange(of: draft) { _, _ in draftChanged() }
        .onDisappear {
            saveConfirmationTask?.cancel()
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
                    .accessibilityIdentifier("weekly-review-keyboard-done")
            }
        }
        .alert("Could Not Save Review", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? String(localized: "Please try again."))
        }
    }

    @ViewBuilder
    private func summarySection(_ summary: WeeklySummary) -> some View {
        Section("Your Week") {
            if !summary.hasActivity {
                Text("No activity recorded this week yet.")
                    .foregroundStyle(.secondary)
            }
            if summary.hasActivity {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 96), alignment: .leading)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    if let entryCount = summary.entryCount {
                        WeeklySummaryFact(label: "Entries", value: "\(entryCount)")
                    }
                    if let dayCount = summary.entryDayCount {
                        WeeklySummaryFact(label: "Days with Entries", value: "\(dayCount)")
                    }
                    if let imageEntryCount = summary.imageEntryCount {
                        WeeklySummaryFact(label: "Photo Entries", value: "\(imageEntryCount)")
                    }
                    if let habitCheckInCount = summary.habitCheckInCount {
                        WeeklySummaryFact(label: "Habit Check-ins", value: "\(habitCheckInCount)")
                    }
                    if let habit = summary.habitHighlight {
                        WeeklySummaryFact(label: "Most Active Habit", value: habit.habitName)
                        WeeklySummaryFact(label: "Active Days", value: "\(habit.activeDayCount)")
                    }
                    if let weight = summary.weight {
                        WeeklySummaryFact(
                            label: "Latest Weight",
                            value: WeightFormatting.kilograms(weight.latestKilograms)
                        )
                        if let change = weight.changeKilograms {
                            WeeklySummaryFact(
                                label: "Weight Change",
                                value: WeightFormatting.kilograms(change)
                            )
                        }
                    }
                }
            }
            if !summary.topTags.isEmpty {
                LabeledContent("Top Tags", value: summary.topTags.joined(separator: ", "))
            }
            if !summary.recentEntries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Entries")
                    ForEach(summary.recentEntries) { entry in
                        Text(entry.title ?? entry.body ?? "Entry")
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var reflectionSections: some View {
        Group {
            Section("Reflect") {
                reflectionField(
                    "What do you want to remember?",
                    text: $rememberedText,
                    field: .remembered,
                    lineLimit: 3...6,
                    identifier: "weekly-review-remembered"
                )
                reflectionField(
                    "What could be better?",
                    text: $improvementText,
                    field: .improvement,
                    lineLimit: 3...6,
                    identifier: "weekly-review-improvement"
                )
                reflectionField(
                    "What is your next step?",
                    text: $nextStepText,
                    field: .nextStep,
                    lineLimit: 2...4,
                    identifier: "weekly-review-next-step"
                )
                reflectionField(
                    "One focus for next week",
                    text: $focusText,
                    field: .focus,
                    lineLimit: 2...4,
                    identifier: "weekly-review-focus"
                )
            }
            Section {
                Toggle("Mark this review complete", isOn: $isCompleted)
                    .accessibilityIdentifier("weekly-review-completed")
                Button("Save Review", action: saveReview)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .disabled(isSaving || !isDirty)
                    .accessibilityIdentifier("save-weekly-review")
                if isDirty {
                    Label("Unsaved changes", systemImage: "circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("weekly-review-unsaved")
                } else if showsSaveConfirmation {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityIdentifier("weekly-review-save-confirmation")
                }
            } footer: {
                Text("Your review is saved only on this device.")
            }
        }
    }

    private func reflectionField(
        _ prompt: LocalizedStringKey,
        text: Binding<String>,
        field: Field,
        lineLimit: ClosedRange<Int>,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(prompt)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("", text: text, axis: .vertical)
                .lineLimit(lineLimit)
                .focused($focusedField, equals: field)
                .accessibilityIdentifier(identifier)
        }
        .padding(.vertical, 3)
    }

    private func createReview() {
        guard let period else { return }
        do {
            let review = try WeeklyReviewService(context: modelContext).review(containing: period.start)
            loadDraft(from: review)
        } catch {
            errorMessage = String(localized: "The weekly review was not saved.")
        }
    }

    private func saveReview() {
        focusedField = nil
        saveConfirmationTask?.cancel()
        showsSaveConfirmation = false
        isSaving = true
        let draftToSave = draft
        Task { @MainActor in
            await Task.yield()
            performSave(draftToSave)
        }
    }

    private func performSave(_ draftToSave: WeeklyReviewDraft) {
        defer { isSaving = false }
        guard let period else {
            errorMessage = String(localized: "The weekly review was not saved.")
            return
        }
        do {
            guard let review = try WeeklyReviewService(context: modelContext).review(
                identifier: period.identifier
            ) else {
                errorMessage = String(localized: "The weekly review was not saved.")
                return
            }
            try WeeklyReviewService(context: modelContext).update(
                review,
                draft: draftToSave
            )
            editState?.markSaved(draftToSave)
            guard draft == draftToSave else { return }
            showsSaveConfirmation = true
            saveConfirmationTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.75))
                guard !Task.isCancelled, draft == draftToSave else { return }
                showsSaveConfirmation = false
            }
        } catch {
            errorMessage = String(localized: "The weekly review was not saved.")
        }
    }

    private func loadDraft(from review: WeeklyReview? = nil) {
        let review = review ?? currentReview
        let loadedDraft = WeeklyReviewDraft(review: review)
        rememberedText = loadedDraft.rememberedText
        improvementText = loadedDraft.improvementText
        nextStepText = loadedDraft.nextStepText
        focusText = loadedDraft.focusText
        isCompleted = loadedDraft.isCompleted
        editState = WeeklyReviewEditState(baseline: loadedDraft)
        saveConfirmationTask?.cancel()
        showsSaveConfirmation = false
    }

    private func draftChanged() {
        guard isDirty else { return }
        saveConfirmationTask?.cancel()
        showsSaveConfirmation = false
    }
}

struct WeeklyReviewHistoryView: View {
    @Query(sort: [
        SortDescriptor(\WeeklyReview.periodStart, order: .reverse),
        SortDescriptor(\WeeklyReview.createdAt, order: .reverse),
        SortDescriptor(\WeeklyReview.id, order: .forward)
    ]) private var reviews: [WeeklyReview]

    var body: some View {
        Group {
            if reviews.isEmpty {
                ContentUnavailableView(
                    "No Weekly Reviews",
                    systemImage: "text.book.closed",
                    description: Text("Weekly Reviews you start from Today will appear here.")
                )
            } else {
                List(reviews) { review in
                    NavigationLink {
                        WeeklyReviewView(weekIdentifier: review.weekIdentifier)
                    } label: {
                        WeeklyReviewRow(review: review)
                    }
                    .accessibilityIdentifier("weekly-review-history-\(review.weekIdentifier)")
                }
            }
        }
        .navigationTitle("Weekly Reviews")
        .accessibilityIdentifier("weekly-review-history")
    }
}

struct WeeklyReviewRow: View {
    let review: WeeklyReview

    private var preview: String? {
        [
            review.rememberedText,
            review.improvementText,
            review.nextStepText
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("\(review.periodStart.formatted(date: .abbreviated, time: .omitted)) – \(review.periodEnd.formatted(date: .abbreviated, time: .omitted))")
                    .font(.headline)
                Spacer()
                Label {
                    Text(
                        review.isCompleted
                            ? String(localized: "Completed")
                            : String(localized: "Incomplete")
                    )
                } icon: {
                    Image(systemName: review.isCompleted ? "checkmark.circle.fill" : "circle")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if let preview {
                Text(preview)
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
            }
            if let focus = review.focusText, !focus.isEmpty {
                LabeledContent("Next Week’s Focus", value: focus)
                    .font(.caption)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct WeeklySummaryFact: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline)
                .lineLimit(2)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
