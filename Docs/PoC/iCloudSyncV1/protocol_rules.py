"""Audit-only, conservative dependency and deterministic projection rules.

Not a production reducer: no CloudKit, domain statistics, GC or account rebinding.
An entity is a stable OBJECT identity, not merely its type name. Unknown or
malformed lineage is retained by Replica but prevents authoritative publication.
"""
from dataclasses import dataclass
from typing import Optional


@dataclass(frozen=True)
class Projection:
    state: str
    body: Optional[str] = None
    candidates: tuple = ()
    baseline: Optional[str] = None

    @property
    def complete(self):
        # A common-ancestor preview is NOT a confirmed current value.
        return self.state in ('ready', 'deleted', 'absent')


class Graph:
    def __init__(self, rows):
        self.rows = tuple(rows)
        self.by_id = {m.op: m for m in self.rows}
        self.cache = {}

    def lineage(self, op, visiting=frozenset()):
        """Return inclusive same-object ancestry, or None for incomplete/invalid."""
        if op in visiting:
            return None
        if op in self.cache:
            return self.cache[op]
        m = self.by_id.get(op)
        if m is None or m.version != 1:
            return None
        ancestry = {op}
        for parent in m.parents:
            p = self.by_id.get(parent)
            if p is None or p.entity != m.entity:
                self.cache[op] = None
                return None
            inherited = self.lineage(parent, visiting | {op})
            if inherited is None:
                self.cache[op] = None
                return None
            ancestry.update(inherited)
        self.cache[op] = frozenset(ancestry)
        return self.cache[op]

    def raw_heads(self, entity):
        rows = [m for m in self.rows if m.entity == entity]
        # Fail closed on known, incomplete lineage; never fall back to an older
        # live row merely because a newer row cannot yet be published.
        histories = [self.lineage(m.op) for m in rows]
        if any(h is None for h in histories):
            return None
        superseded = set()
        for m, history in zip(rows, histories):
            superseded.update(history - {m.op})
        return sorted((m for m in rows if m.op not in superseded), key=lambda m: m.op)

    def ready(self, m, visiting=frozenset()):
        if m.entity in visiting:
            return False
        # A tombstone must not wait for the targets it is unlinking to reappear.
        if m.deleted:
            return True
        for entity in m.requires:
            heads = self.raw_heads(entity)
            # A dependency must have ONE current, live, recursively ready head.
            # Concurrent live/delete or live/live branches do not satisfy it.
            if heads is None or len(heads) != 1 or heads[0].deleted:
                return False
            if not self.ready(heads[0], visiting | {m.entity}):
                return False
        return True


def publishable_heads(rows, entity):
    graph = Graph(rows)
    heads = graph.raw_heads(entity)
    if heads is None or not all(graph.ready(m) for m in heads):
        return []
    return heads


def project(rows, entity):
    """Pure function of received facts, never of this device's last UI value.

    Caller must not interpret missing/conflicted body as zero or feed a preview
    into confirmed statistics. Domain reducers and natural-key aggregation are
    intentionally outside this small protocol experiment.
    """
    graph = Graph(rows)
    heads = graph.raw_heads(entity)
    if heads is None:
        return Projection('staged', candidates=tuple(sorted(
            m.op for m in graph.rows if m.entity == entity)))
    if not heads:
        return Projection('absent')
    ids = tuple(m.op for m in heads)
    if any(m.deleted for m in heads):
        return Projection('deleted' if len(heads) == 1 else 'deleted_conflict',
                          candidates=ids)
    if not all(graph.ready(m) for m in heads):
        return Projection('staged', candidates=ids)
    if len(heads) == 1:
        return Projection('ready', body=heads[0].body, candidates=ids)
    common = set.intersection(*(set(graph.lineage(m.op)) for m in heads))
    maximal = [op for op in common if not any(
        op != other and op in graph.lineage(other) for other in common)]
    if len(maximal) == 1:
        base = graph.by_id[maximal[0]]
        if not base.deleted and graph.ready(base):
            return Projection('conflict', body=base.body, candidates=ids,
                              baseline=base.op)
    return Projection('conflict', candidates=ids)
