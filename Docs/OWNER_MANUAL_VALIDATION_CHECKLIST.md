# Owner Manual Validation Checklist

This checklist begins only after V1 Candidate Technical Completion. Every item below is intentionally **unchecked**: Codex has not installed the app on a physical iPhone, used Owner data, validated the real Photos Picker or permissions, started Dogfooding, or started the formal 30-day observation.

## Safety Before Testing

- [ ] Use a physical iPhone and signing configuration selected by the Owner.
- [ ] Begin with disposable test content, not the only copy of real memories.
- [ ] Confirm the device has comfortable free storage before image and restore tests.
- [ ] Keep exported ZIP files in an Owner-controlled location outside the app container.
- [ ] Treat every export as sensitive: the ZIP is not encrypted and contains entry text plus original photos.
- [ ] Keep the current app installation until an external backup has been confirmed present and shareable.

## Install, Launch and Offline Boundary

- [ ] Build and install the Candidate on a real iPhone.
- [ ] Launch it successfully and confirm Today, Timeline, Growth and Library are reachable.
- [ ] Turn on Airplane Mode and confirm launch, capture, search, organization and Growth flows still work.
- [ ] Confirm no account, network, CloudKit or sign-in prompt is required.
- [ ] Force-quit and reopen the app; confirm previously created content remains available.

## Capture, Media and Time Semantics

- [ ] Create, reopen and edit a text-only Entry.
- [ ] Create and reopen an image-only Entry through the real Photos Picker.
- [ ] Create and reopen a mixed text-and-image Entry.
- [ ] Select multiple photos, reorder them, save, reopen and confirm order and original quality.
- [ ] Exercise camera capture if the device and signing configuration expose it.
- [ ] Test Photos and Camera permission grant, denial and later Settings recovery behavior.
- [ ] Backdate `occurredAt`; confirm the Entry appears at the intended Timeline time while creation time remains current.
- [ ] Archive and restore an Entry; confirm its images remain intact.
- [ ] Permanently delete one of two image Entries; confirm only its own image disappears.

## Organization, Growth, Review and Search

- [ ] Leave an Entry in Inbox, then organize it without creating a Tag.
- [ ] Create a Tag, attach it to an Entry and find the Entry through global Search.
- [ ] Create a Habit and perform a simple HabitLog check-in.
- [ ] Add a Habit insight through a linked Entry and reopen it from Habit history.
- [ ] Pause, restart, complete and archive a disposable Habit as appropriate.
- [ ] Create both a Goal and a Flag; verify their lifecycle and Today context.
- [ ] Link an Entry to a Goal and a Habit to a Goal, then reopen each relationship.
- [ ] Create a lightweight Review with a period and link an Entry, Habit and Goal.
- [ ] Find an ordinary Entry, Review Entry, Tag, Habit, Goal and Flag through Search.

## Export, Privacy Warning and Disposable Restore Rehearsal

- [ ] Open Settings and start Export; confirm the unencrypted-backup privacy warning appears before sharing.
- [ ] Export a disposable complete data set to an Owner-controlled Files location.
- [ ] Confirm the ZIP exists outside the app container and can be copied before altering the app installation.
- [ ] Confirm Import refuses a non-empty database and does not erase or merge its content.
- [ ] For the destructive rehearsal, use only the disposable data set and retain the external ZIP.
- [ ] Remove the disposable active app data by deleting/reinstalling the app, then launch the empty database.
- [ ] Import the retained ZIP and verify text, timestamps, image order/originals, Tags, Habits, HabitLogs, Goals/Flags, Reviews and relationships.
- [ ] Force-quit and reopen after restore; confirm restored content and media remain intact.
- [ ] Export the restored data again and retain both packages until the rehearsal is accepted.

## Physical-device Quality Review

- [ ] Review capture, Timeline scrolling, Search and image viewing responsiveness with representative real-life content volume.
- [ ] Watch for memory pressure, termination, heat or long main-thread stalls during multi-image capture and full backup/restore.
- [ ] Compare free storage before and after representative image capture, export and restore.
- [ ] Confirm progress, cancellation and failure messages are understandable and leave the prior data set intact.
- [ ] Check VoiceOver labels, selected-state announcements, Dynamic Type at the Owner's preferred size, contrast and touch targets on the physical device.
- [ ] Record every real-iPhone Daily Driver blocker with reproduction steps and whether it risks data integrity.

## Owner Decision Boundary

- [ ] Review the Candidate report, known limitations, Milestone C evidence and this completed checklist.
- [ ] Decide whether to accept the Candidate, request fixes or abandon selected implementation areas.
- [ ] Explicitly decide whether formal Dogfooding may begin; technical completion does not start it automatically.
- [ ] Only after Candidate acceptance and the physical-device blocker review, record the date formal Dogfooding begins.
- [ ] Only after the Owner explicitly starts it, record the start date of the Foundation-defined continuous 30-day V1 Exit Observation.
- [ ] At the end of that uninterrupted period, evaluate the Foundation exit criteria using actual Owner experience; do not infer success from simulator or automated evidence.

## Owner Notes

| Item | Owner record |
| --- | --- |
| Physical device / iOS version |  |
| Candidate commit |  |
| Signing configuration |  |
| Validation date |  |
| Blocking defects |  |
| Non-blocking defects |  |
| Candidate decision |  |
| Dogfooding start decision/date |  |
| 30-day observation start decision/date |  |
