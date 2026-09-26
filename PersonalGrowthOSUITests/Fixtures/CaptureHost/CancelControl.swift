import Social

// Independent system-controller control; no product reader, metadata, or cancellation code.
final class CancelControl: SLComposeServiceViewController {
    override func isContentValid() -> Bool { true }
}
