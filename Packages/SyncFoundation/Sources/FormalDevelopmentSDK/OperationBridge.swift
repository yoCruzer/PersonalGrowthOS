import Foundation
import CloudKit

struct TransportItemEvidence: Codable {
    let item: String
    let status: String
    let errorDomain: String?
    let errorCode: Int?
    let partialErrorCodes: [Int]
}
enum TransportCancellationScope: String, Codable { case sdkOperation, localWaitOnly }
struct TransportOperationEvidence: Codable {
    let operationID: UUID
    let stage: String
    let sequence: Int
    let event: String
    let started: Bool
    let cancellationRequested: Bool
    let remoteOutcomeUnknown: Bool
    let cancellationScope: TransportCancellationScope
    let items: [TransportItemEvidence]
}

typealias TransportEvidenceSink = @MainActor (TransportOperationEvidence) throws -> Void
typealias TransportEvidenceFailure = @MainActor (TransportOperationEvidence) -> Void

@MainActor protocol OperationEvidenceTransport: BatchTransport {
    func bindOperationEvidence(_ sink: @escaping TransportEvidenceSink, onFailure: @escaping TransportEvidenceFailure)
    func requestCancellation()
}

enum TransportOperationFailure: Error { case evidenceNotBound, evidenceWriteFailed, invalidResults }

/// Never serializes arbitrary error descriptions, payloads, paths or unexpected IDs.
func transportItem(_ item: String, error: Error? = nil) -> TransportItemEvidence {
    guard let error else { return .init(item: item, status: "RETURNED_SUCCESS_UNVERIFIED", errorDomain: nil, errorCode: nil, partialErrorCodes: []) }
    let ns = error as NSError
    let partial = (ns.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error])?.values.map { ($0 as NSError).code }.sorted() ?? []
    return .init(item: item, status: "RETURNED_FAILURE", errorDomain: ns.domain == CKErrorDomain ? CKErrorDomain : "OTHER", errorCode: ns.code, partialErrorCodes: partial)
}

/// Callback delivery is FIFO on the main queue. No lock is held while persisting
/// evidence, enqueueing or cancelling: synchronous fake/SDK callbacks can reenter
/// submit safely. Each instance captures its original run's sink permanently.
@MainActor final class OperationCallbackBridge<Key: Hashable, Value, Output> {
    let operationID = UUID()
    let stage: String
    private let expected: Set<Key>
    private let label: (Key) -> String
    private let validValue: (Key, Value) -> Bool
    private let finish: ([Key: Result<Value, Error>], Result<Void, Error>) throws -> Output
    private let sink: TransportEvidenceSink
    private let onFailure: TransportEvidenceFailure
    private let cancellationScope: TransportCancellationScope
    private var continuation: CheckedContinuation<Output, Error>?
    private var operation: Operation?
    private var results: [Key: Result<Value, Error>] = [:]
    private var sequence = 0
    private var started = false
    private var cancelled = false
    private var terminal = false
    private var executed = false
    private var evidenceBroken = false
    private var completionReceived = false
    private var aggregateSucceeded = false

    init(stage: String, expected: Set<Key>, label: @escaping (Key) -> String,
         validValue: @escaping (Key, Value) -> Bool,
         sink: @escaping TransportEvidenceSink, onFailure: @escaping TransportEvidenceFailure,
         cancellationScope: TransportCancellationScope = .sdkOperation,
         finish: @escaping ([Key: Result<Value, Error>], Result<Void, Error>) throws -> Output) {
        self.stage = stage; self.expected = expected; self.label = label; self.validValue = validValue
        self.sink = sink; self.onFailure = onFailure; self.finish = finish
        self.cancellationScope = cancellationScope
    }

    nonisolated func receive(_ key: Key, _ result: Result<Value, Error>) {
        DispatchQueue.main.async { self.item(key, result) }
    }
    nonisolated func complete(_ result: Result<Void, Error>) {
        DispatchQueue.main.async { self.completed(result) }
    }
    nonisolated func unexpectedCallback(_ result: Result<Void, Error>) {
        let item: TransportItemEvidence
        switch result { case .success: item = transportItem("UNEXPECTED_RECORD_ID")
        case .failure(let error): item = transportItem("UNEXPECTED_RECORD_ID", error: error) }
        DispatchQueue.main.async { self.invalidCallback(item) }
    }
    nonisolated func cancelFromAnyQueue() {
        DispatchQueue.main.async { self.requestCancellation() }
    }

    func execute(operation: Operation, enqueue: () -> Void) async throws -> Output {
        guard !executed else { throw TransportOperationFailure.invalidResults }
        executed = true
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { pending in
                continuation = pending
                if Task.isCancelled { requestCancellation() }
                self.operation = operation
                if cancelled || terminal || evidenceBroken {
                    // A cancellation before handle installation remains effective.
                    operation.cancel(); self.operation = nil
                    resume(.failure(evidenceBroken ? TransportOperationFailure.evidenceWriteFailed : CancellationError()))
                    return
                }
                guard emit("OPERATION_ENQUEUE_REQUESTED"), !cancelled, !terminal, !evidenceBroken else { return }
                started = true
                enqueue()
            }
        } onCancel: { self.cancelFromAnyQueue() }
    }

    func requestCancellation() {
        guard !cancelled else { return }
        cancelled = true
        // On a healthy journal this is durably acknowledged before cancel().
        // A broken journal invokes onFailure and only best-effort cancels an
        // already held operation; it never claims the event was persisted.
        _ = emit("CANCEL_REQUESTED")
        let held = operation; operation = nil
        held?.cancel()
        resume(.failure(evidenceBroken ? TransportOperationFailure.evidenceWriteFailed : CancellationError()))
    }

    private func item(_ key: Key, _ result: Result<Value, Error>) {
        let known = expected.contains(key)
        let safeName = known ? label(key) : "UNEXPECTED_RECORD_ID"
        let evidence: TransportItemEvidence
        switch result { case .success: evidence = transportItem(safeName)
        case .failure(let error): evidence = transportItem(safeName, error: error) }
        guard emit(terminal ? "LATE_ITEM_RETURNED" : "ITEM_RETURNED", items: [evidence]) else { return }
        guard !terminal else { return }
        guard known, results[key] == nil else { invalidCallback(); return }
        if case .success(let value) = result, !validValue(key, value) { invalidCallback(); return }
        results[key] = result
    }
    private func invalidCallback(_ item: TransportItemEvidence? = nil) {
        _ = emit(terminal ? "LATE_UNEXPECTED_CALLBACK" : "UNEXPECTED_CALLBACK", items: item.map { [$0] } ?? [])
        guard !terminal else { return }
        resume(.failure(TransportOperationFailure.invalidResults))
        requestCancellation()
    }
    private func completed(_ result: Result<Void, Error>) {
        let items: [TransportItemEvidence]
        switch result { case .success: items = [transportItem("operation")]
        case .failure(let error): items = [transportItem("operation", error: error)] }
        let late = terminal || completionReceived
        completionReceived = true
        if case .success = result { aggregateSucceeded = true } else { aggregateSucceeded = false }
        guard emit(late ? "LATE_OPERATION_RETURNED" : "OPERATION_RETURNED", items: items) else { return }
        operation = nil
        guard !terminal else { return }
        do {
            // Missing/extra per-item results are never inferred from an aggregate
            // success. Aggregate failures are still retained before throwing.
            if case .success = result, Set(results.keys) != expected { throw TransportOperationFailure.invalidResults }
            let value = try finish(results, result)
            resume(.success(value))
        } catch { resume(.failure(error)) }
    }
    @discardableResult private func emit(_ event: String, items: [TransportItemEvidence] = []) -> Bool {
        let value = TransportOperationEvidence(operationID: operationID, stage: stage, sequence: sequence,
            event: event, started: started, cancellationRequested: cancelled,
            remoteOutcomeUnknown: started && (cancelled || evidenceBroken || !aggregateSucceeded || Set(results.keys) != expected
                || results.values.contains { if case .failure = $0 { return true }; return false }),
            cancellationScope: cancellationScope, items: items)
        sequence += 1
        do { try sink(value); return true }
        catch {
            evidenceBroken = true
            onFailure(value)
            // No further enqueue or successful completion is possible. Cancel is
            // best effort only because this evidence could not be persisted.
            let held = operation; operation = nil
            held?.cancel()
            resume(.failure(TransportOperationFailure.evidenceWriteFailed))
            return false
        }
    }
    private func resume(_ result: Result<Output, Error>) {
        terminal = true
        let pending = continuation; continuation = nil
        pending?.resume(with: result)
    }
}
