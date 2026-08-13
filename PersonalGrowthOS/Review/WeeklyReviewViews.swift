import SwiftData
import SwiftUI

struct WeeklyReviewView: View {
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
    @State private var saveMessage: String?
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private var period: WeeklyReviewPeriod? {
        try? WeeklyReviewPeriod(containing: Date())
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
        .onChange(of: rememberedText) { _, _ in saveMessage = nil }
        .onChange(of: improvementText) { _, _ in saveMessage = nil }
        .onChange(of: nextStepText) { _, _ in saveMessage = nil }
        .onChange(of: focusText) { _, _ in saveMessage = nil }
        .onChange(of: isCompleted) { _, _ in saveMessage = nil }
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
        Section("Activity") {
            if !summary.hasActivity {
                Text("No activity recorded this week yet.")
                    .foregroundStyle(.secondary)
            }
            if let entryCount = summary.entryCount {
                LabeledContent("Entries", value: "\(entryCount)")
                if let dayCount = summary.entryDayCount {
                    LabeledContent("Days with Entries", value: "\(dayCount)")
                }
            }
            if let imageEntryCount = summary.imageEntryCount {
                LabeledContent("Photo Entries", value: "\(imageEntryCount)")
            }
            if let habitCheckInCount = summary.habitCheckInCount {
                LabeledContent("Habit Check-ins", value: "\(habitCheckInCount)")
            }
            if let habit = summary.habitHighlight {
                LabeledContent("Most Active Habit", value: habit.habitName)
                LabeledContent("Check-ins", value: "\(habit.checkInCount)")
                LabeledContent("Active Days", value: "\(habit.activeDayCount)")
            }
            if let weight = summary.weight {
                LabeledContent("Latest Weight", value: WeightFormatting.kilograms(weight.latestKilograms))
                if let change = weight.changeKilograms {
                    LabeledContent("Weight Change", value: WeightFormatting.kilograms(change))
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
                TextField("What do you want to remember?", text: $rememberedText, axis: .vertical)
                    .lineLimit(3...6)
                    .focused($focusedField, equals: .remembered)
                    .accessibilityIdentifier("weekly-review-remembered")
                TextField("What could be better?", text: $improvementText, axis: .vertical)
                    .lineLimit(3...6)
                    .focused($focusedField, equals: .improvement)
                    .accessibilityIdentifier("weekly-review-improvement")
                TextField("What is your next step?", text: $nextStepText, axis: .vertical)
                    .lineLimit(2...4)
                    .focused($focusedField, equals: .nextStep)
                    .accessibilityIdentifier("weekly-review-next-step")
                TextField("One focus for next week", text: $focusText, axis: .vertical)
                    .lineLimit(2...4)
                    .focused($focusedField, equals: .focus)
                    .accessibilityIdentifier("weekly-review-focus")
            }
            Section {
                Toggle("Mark this review complete", isOn: $isCompleted)
                    .accessibilityIdentifier("weekly-review-completed")
                Button("Save Review", action: saveReview)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .disabled(isSaving)
                    .accessibilityIdentifier("save-weekly-review")
                if let saveMessage {
                    Label(saveMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityIdentifier("weekly-review-save-confirmation")
                }
            } footer: {
                Text("Your review is saved only on this device.")
            }
        }
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
        saveMessage = nil
        isSaving = true
        Task { @MainActor in
            await Task.yield()
            performSave()
        }
    }

    private func performSave() {
        defer { isSaving = false }
        guard let period else {
            errorMessage = String(localized: "The weekly review was not saved.")
            return
        }
        do {
            guard let review = try WeeklyReviewService(context: modelContext).review(
                containing: period.start,
                createIfNeeded: false
            ) else {
                errorMessage = String(localized: "The weekly review was not saved.")
                return
            }
            try WeeklyReviewService(context: modelContext).update(
                review,
                draft: WeeklyReviewDraft(
                    rememberedText: rememberedText,
                    improvementText: improvementText,
                    nextStepText: nextStepText,
                    focusText: focusText,
                    isCompleted: isCompleted
                )
            )
            saveMessage = String(localized: "Saved")
        } catch {
            errorMessage = String(localized: "The weekly review was not saved.")
        }
    }

    private func loadDraft(from review: WeeklyReview? = nil) {
        let review = review ?? currentReview
        rememberedText = review?.rememberedText ?? ""
        improvementText = review?.improvementText ?? ""
        nextStepText = review?.nextStepText ?? ""
        focusText = review?.focusText ?? ""
        isCompleted = review?.isCompleted ?? false
    }
}
