import UIKit
import LinkPresentation

final class ShareViewController: UIViewController, UITextViewDelegate {
    private let editor = UITextView()
    private let sourceLabel = UILabel()
    private let statusLabel = UILabel()
    private let preview = UIImageView()
    private let saveButton = UIButton(type: .system)
    private var payload = ShareImportPayload()
    private var files: [UUID: URL] = [:]
    private var metadataProvider: LPMetadataProvider?
    private var finished = false
    private var saving = false
    private var loaded = false
    private var textDraft = CaptureTextDraft()
    private var generation = UUID()
    private var loadTask: Task<Void, Never>?
    private let retryButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let diagnosticButton = UIButton(type: .system)
    private var failureDiagnostic: FailureDiagnostic?
    private var issues: [CaptureReadIssue] = []
    private var workspace = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        cancelButton.setTitle(NSLocalizedString("Cancel", comment: ""), for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelCapture), for: .touchUpInside)
        saveButton.setTitle(NSLocalizedString("Save", comment: ""), for: .normal)
        saveButton.isEnabled = false
        saveButton.addTarget(self, action: #selector(saveCapture), for: .touchUpInside)
        retryButton.setTitle(NSLocalizedString("Retry", comment: ""), for: .normal)
        retryButton.addTarget(self, action: #selector(beginLoad), for: .touchUpInside)
        retryButton.isHidden = true
        diagnosticButton.setTitle(NSLocalizedString("Copy Diagnostic Report", comment: ""), for: .normal)
        diagnosticButton.addTarget(self, action: #selector(copyDiagnostic), for: .touchUpInside)
        diagnosticButton.isHidden = true
        let toolbar = UIStackView(arrangedSubviews: [cancelButton, retryButton, UIView(), saveButton])
        toolbar.heightAnchor.constraint(equalToConstant: 44).isActive = true
        editor.delegate = self
        editor.font = .preferredFont(forTextStyle: .body)
        editor.accessibilityIdentifier = "share-text"
        sourceLabel.numberOfLines = 3
        sourceLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        preview.contentMode = .scaleAspectFit
        preview.heightAnchor.constraint(equalToConstant: 100).isActive = true
        preview.isHidden = true
        let stack = UIStackView(arrangedSubviews: [toolbar, sourceLabel, preview, editor, statusLabel, diagnosticButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -12)
        ])
        beginLoad()
    }

    @objc private func beginLoad() {
        guard !finished, !saving else { return }
        failureDiagnostic = nil
        diagnosticButton.isHidden = true
        loadTask?.cancel()
        metadataProvider?.cancel()
        let oldWorkspace = workspace
        let previous = loadTask
        Task { await previous?.value; try? FileManager.default.removeItem(at: oldWorkspace) }
        workspace = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        generation = UUID()
        let current = generation
        let workingDirectory = workspace
        payload = ShareImportPayload()
        files = [:]
        issues = []
        loaded = false
        editor.text = ""
        editor.isEditable = false
        preview.image = nil
        preview.isHidden = true
        sourceLabel.text = nil
        saveButton.isEnabled = false
        retryButton.isHidden = true
        statusLabel.text = NSLocalizedString("Reading shared content…", comment: "")
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        loadTask = Task { [weak self] in
            do {
                _ = try ShareInbox.shared()
                let result = try await ShareProviderReader(workspace: workingDirectory).read(items)
                try Task.checkCancellation()
                guard let self, !self.finished, self.generation == current else { return }
                self.payload = result.payload
                self.files = result.files
                self.issues = result.issues
                self.loaded = true
                self.editor.isEditable = true
                self.textDraft.receive(result.textItems)
                self.editor.text = self.textDraft.text
                if let data = result.thumbnail {
                    self.preview.image = UIImage(data: data)
                    self.preview.isHidden = false
                }
                self.updateSource()
                self.updateReadStatus()
                if let issue = result.issues.first { self.recordFailure(issue.reason, stage: .providerRead) }
                self.fetchMetadata()
            } catch {
                guard let self, !self.finished, self.generation == current else { return }
                self.retryButton.isHidden = false
                self.statusLabel.text = NSLocalizedString("Unable to read this share. Try sharing text, a webpage, or up to 9 photos (25 MB each).", comment: "")
                self.recordFailure(error, stage: .providerRead)
            }
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        textDraft.edit(textView.text)
        updateReadStatus()
    }

    private func updateReadStatus() {
        guard loaded, !saving, !finished else { return }
        payload.text = editor.text
        retryButton.isHidden = issues.isEmpty
        do {
            try payload.validate()
            saveButton.isEnabled = true
            if issues.isEmpty {
                statusLabel.text = NSLocalizedString("Saved shares appear when you next open 随心log.", comment: "")
            } else {
                statusLabel.text = issueMessage
            }
        } catch {
            saveButton.isEnabled = false
            retryButton.isHidden = false
            statusLabel.text = payload.text.utf8.count > 1_048_576
                ? NSLocalizedString("Shared text is too long. Shorten it before saving; the original has not been truncated.", comment: "")
                : NSLocalizedString("Unable to read this share. Try sharing text, a webpage, or up to 9 photos (25 MB each).", comment: "")
        }
    }

    private var issueMessage: String {
        let details = issues.map { issue in
            let reason: String
            switch issue.reason {
            case .providerTimedOut: reason = NSLocalizedString("Reading timed out", comment: "")
            case .multipleSources: reason = NSLocalizedString("Additional source kept in text", comment: "")
            case .tooLarge: reason = NSLocalizedString("Supported size or count exceeded", comment: "")
            default: reason = NSLocalizedString("Content could not be read", comment: "")
            }
            return "\(issue.item): \(reason)"
        }.joined(separator: "\n")
        return NSLocalizedString("Some shared items need attention. Retry, or confirm saving only the content shown below.", comment: "") + "\n" + details
    }

    private func updateSource() {
        payload.source?.normalizeMetadata()
        sourceLabel.text = [payload.source?.title, payload.source?.url].compactMap { $0 }.joined(separator: "\n")
    }

    private func fetchMetadata() {
        guard let source = payload.source, source.title?.isEmpty != false,
              let url = CaptureSource.webURL(source.url) else { return }
        let provider = LPMetadataProvider()
        provider.timeout = 3
        provider.shouldFetchSubresources = false
        metadataProvider = provider
        CaptureLog.event("metadata.started", id: payload.id)
        let current = generation
        provider.startFetchingMetadata(for: url) { [weak self] metadata, error in
            Task { @MainActor in
                guard let self, !self.finished, !self.saving, self.generation == current else { return }
                if let metadata {
                    self.payload.source?.title = metadata.title
                    self.payload.source?.canonicalURL = CaptureSource.webURL(metadata.url?.absoluteString)?.absoluteString
                    self.updateSource()
                }
                CaptureLog.event(error == nil ? "metadata.completed" : "metadata.fallback", id: self.payload.id)
            }
        }
    }

    @objc private func saveCapture() {
        guard loaded, !finished, !saving, saveButton.isEnabled else { return }
        CaptureLog.event("capture.saveRequested", id: payload.id)
        if !issues.isEmpty {
            let alert = UIAlertController(title: NSLocalizedString("Save readable content only?", comment: ""),
                message: issueMessage, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
            alert.addAction(UIAlertAction(title: NSLocalizedString("Save Shown Content", comment: ""), style: .default) { [weak self] _ in
                guard let self else { return }
                CaptureLog.event("capture.partialConfirmed", id: self.payload.id)
                self.publishCapture()
            })
            present(alert, animated: true)
        } else { publishCapture() }
    }

    private func publishCapture() {
        guard loaded, !finished, !saving else { return }
        CaptureLog.event("capture.publishStarted", id: payload.id)
        payload.text = editor.text
        if !payload.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           payload.text != payload.source?.url { payload.source?.captureMode = .selectedContent }
        payload.source?.normalizeMetadata()
        // A value snapshot freezes metadata and edits before leaving MainActor.
        let snapshot = payload
        let sourceFiles = files
        saving = true
        failureDiagnostic = nil
        diagnosticButton.isHidden = true
        saveButton.isEnabled = false
        cancelButton.isEnabled = false
        retryButton.isHidden = true
        editor.isEditable = false
        metadataProvider?.cancel()
        statusLabel.text = NSLocalizedString("Saving shared content…", comment: "")
        Task {
            do {
                try await Task.detached { try ShareInbox.shared().publish(snapshot, files: sourceFiles) }.value
                finished = true
                try? FileManager.default.removeItem(at: workspace)
                extensionContext?.completeRequest(returningItems: nil)
            } catch {
                saving = false
                cancelButton.isEnabled = true
                editor.isEditable = true
                updateReadStatus()
                recordFailure(error, stage: .publish)
                statusLabel.text = CaptureError.isStorageFailure(error)
                    ? NSLocalizedString("Not enough storage. Free some space, then retry. Your share has not been published.", comment: "")
                    : NSLocalizedString("Could not save. Your share is still here; please retry or cancel.", comment: "")
            }
        }
    }

    private func recordFailure(_ error: Error, stage: FailureDiagnostic.Stage) {
        let diagnostic = FailureDiagnostic(error: error, stage: stage, role: .shareExtension)
        failureDiagnostic = diagnostic
        diagnosticButton.isHidden = false
        diagnostic.log()
    }

    @objc private func copyDiagnostic() {
        guard let failureDiagnostic else { return }
        UIPasteboard.general.string = failureDiagnostic.report
    }

    @objc private func cancelCapture() {
        guard !saving, !finished else { return }
        CaptureLog.event("capture.cancelled", id: payload.id)
        finished = true
        generation = UUID()
        loadTask?.cancel()
        metadataProvider?.cancel()
        let task = loadTask
        let directory = workspace
        Task { await task?.value; try? FileManager.default.removeItem(at: directory) }
        extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }
}
