// Append to exact HEAD TodoFoundationTests.swift in a temporary git archive.
@MainActor
extension TodoFoundationTests {
    func testGenerateOriginalV11CandidateFixture() throws {
        let root = URL(fileURLWithPath: "/tmp/pgos-review-evidence/OriginalV11", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try autoreleasepool {
            let container = try PersistenceContainerFactory.makeOnDisk(at: root.appendingPathComponent("store.sqlite"))
            let service = TodoTaskService(context: container.mainContext, now: { self.date("2026-01-31") }, timeZone: { self.zone })
            let first = try service.create(TodoDraft(title: "Original V11", plannedDay: "2026-01-31", remindAt: TodoRecurrence.reminder(day: TodoDay("2026-01-30")!, minutes: 1200, timeZone: zone), frequency: .monthly))
            try service.transition(id: first.id, to: .completed)
            try TodoIntegrity.validate(context: container.mainContext)
            try Data(first.id.uuidString.utf8).write(to: root.appendingPathComponent("task-id.txt"))
        }
    }
}
