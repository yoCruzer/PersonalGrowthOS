# Exact Build 8 V8 fixture

Synthetic data only. Generated 2026-09-16 by exact source `ae8f7cb6577f2d1bc479471bcd98d6f437670210`, isolated at `/tmp/PGOS-Build9-ExactBuild8`. No product source was modified. A test-only extension copied the existing exact-Build7 fixture, opened it through the unchanged V8 factory, applied `HabitAnalyticsMigrationBootstrap` at Unix 1730000000 in Asia/Tokyo, saved, released and reopened it. The WAL was empty after the test process exited; only the checkpointed SQLite store and synthetic PNG are retained.

Command: `xcodebuild test -project /tmp/PGOS-Build9-ExactBuild8/PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -destination 'platform=iOS Simulator,id=5F04DE28-8329-4774-9488-076D6DDC5230' -derivedDataPath /tmp/PGOS-Build9-V8Derived -only-testing:PersonalGrowthOSTests/HabitFoundationTests/testGenerateExactBuild8Fixture -resultBundlePath /tmp/PGOS-Build9-V8Generate.xcresult`

Result: PASS, exit 0. The generator test is retained beside this manifest for reproducibility; append it only to an isolated copy of the exact old test file. Existing Build7 source identities/content remain, with 4 V8 Plan revisions, 4 lifecycle baselines and 6 Local Day metadata records. No user database was accessed.
