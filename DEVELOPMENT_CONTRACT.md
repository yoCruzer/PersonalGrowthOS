# Development Contract

## Purpose

This contract defines how Personal Growth OS is developed over time. It is a durable set of decision principles, not a product specification, implementation plan, or tool-specific procedure.

The Foundation Documents remain the highest authority for product direction. This contract governs how work proceeds when it does not conflict with those documents.

## Authority and Context

Use project knowledge in this order:

1. The Foundation Documents and their index.
2. This Development Contract.
3. `Docs/CURRENT_STATE.md` for verified repository facts.
4. `Docs/CURRENT_TASK.md` for the active development boundary.
5. Approved implementation and execution plans relevant to the task.
6. The existing code and tests as evidence of current behavior.

When sources disagree, follow the higher authority. Do not silently reinterpret a product decision to make implementation easier.

## Development Principles

### Preserve intent

Every change must trace to an approved objective. Product scope comes from the Foundation Documents; a development batch may refine implementation details but may not expand that scope.

### Prefer the smallest coherent change

Implement only what is needed to satisfy the current objective and its success criteria. Avoid speculative abstractions, infrastructure, configuration, and future-facing placeholders.

### Use evidence, not assumptions

Inspect the repository before changing it. Record current state only from files, history, builds, tests, or other reproducible evidence. When an unverified assumption could change the result, verify it or escalate it.

### Keep decisions reversible

Prefer changes that are easy to review, test, and revert. Treat user data, privacy, schema evolution, media ownership, import, export, and other destructive boundaries with extra care.

### Validate at the right level

Define observable success before implementation. Add or update tests when behavior changes, run the applicable automated checks, and use focused manual verification where automation cannot prove the outcome. A passing build alone does not prove product behavior.

### Let architecture follow demonstrated needs

Use the simplest structure that supports current approved behavior. Introduce dependencies, indirection, modules, protocols, or generalized systems only when a present requirement justifies their cost.

### Leave a trustworthy repository

Each completed batch should be internally consistent, documented where durable knowledge changed, represented by a coherent commit, and left in a clean state. Temporary investigation notes and chat-dependent knowledge do not belong in the repository.

## Working Agreement

For each development batch:

1. Read the authoritative context and inspect the verified baseline.
2. State the objective, boundaries, constraints, and measurable success criteria.
3. Make the minimum changes required by that boundary.
4. Validate in proportion to the change and resolve failures within scope.
5. Review the complete diff for unintended behavior or unrelated edits.
6. Update `Docs/CURRENT_STATE.md` and `Docs/CURRENT_TASK.md` when the verified state or next handoff changes.
7. Commit one coherent result and stop at the batch boundary.

Failures are evidence. Do not bypass, disable, or weaken a required check merely to report success.

## Autonomous Decisions and Escalation

Work should proceed autonomously when the decision is within the approved scope, supported by the authority chain, reversible, and verifiable.

Stop and request Owner Review when any of the following is true:

- authoritative documents conflict or the requested work would contradict a Foundation decision;
- a necessary product or architecture choice is not governed by the approved baseline and materially changes scope or long-term direction;
- proceeding requires an irreversible or destructive action whose target or recovery path is uncertain;
- privacy, security, data ownership, or user-data integrity would be weakened;
- a new external dependency, paid service, credential, capability, publication, or other external commitment requires approval;
- required validation cannot be completed and continuing would make the repository state unreliable;
- an applicable approved plan explicitly reserves the decision for the Owner.

An escalation should identify the verified facts, the exact decision required, the available options, and the consequence of each option. Ordinary implementation details, recoverable local changes, and choices already resolved by project documents are not escalation conditions.

## Definition of Done

A batch is complete only when:

- its stated success criteria are met;
- applicable builds, tests, and focused checks pass;
- the final diff contains only in-scope changes;
- durable documentation reflects the verified repository state;
- the next development boundary is clear;
- the repository is clean after a coherent commit; and
- work has stopped without entering the next batch.

## Contract Maintenance

Change this contract only when the long-term development philosophy or authority model changes. Do not edit it for individual features, tools, temporary procedures, or one-off exceptions.
