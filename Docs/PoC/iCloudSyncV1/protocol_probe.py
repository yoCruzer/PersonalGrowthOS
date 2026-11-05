#!/usr/bin/env python3
"""Executable protocol counterexamples, NOT a CloudKit implementation.

Uses synthetic payloads, SQLite transactions and an explicit causal DAG. The tests
prove only local protocol properties; they make no claim about server delivery.
"""
import hashlib, itertools, json, pathlib, sqlite3, tempfile, unittest
from dataclasses import dataclass, asdict
from protocol_rules import publishable_heads, project

@dataclass(frozen=True)
class Mutation:
    op: str
    entity: str
    parents: tuple = ()
    body: str = ''
    deleted: bool = False
    business_key: str = ''
    requires: tuple = ()
    version: int = 1

class Replica:
    def __init__(self, path, account='A', epoch=1):
        self.db=sqlite3.connect(path)
        self.account=account;self.epoch=epoch
        self.db.executescript('''
        CREATE TABLE IF NOT EXISTS mutations(op TEXT PRIMARY KEY, bytes TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS outbox(op TEXT PRIMARY KEY);
        CREATE TABLE IF NOT EXISTS cursor(id INTEGER PRIMARY KEY CHECK(id=1), value INTEGER);
        INSERT OR IGNORE INTO cursor VALUES(1,0);
        CREATE TABLE IF NOT EXISTS blobs(hash TEXT PRIMARY KEY, bytes BLOB);
        ''')
    def rows(self):
        return [Mutation(**{**json.loads(row[0]),'parents':tuple(json.loads(row[0])['parents']),
                            'requires':tuple(json.loads(row[0])['requires'])})
                for row in self.db.execute('SELECT bytes FROM mutations')]
    def insert(self, mutation):
        raw=json.dumps(asdict(mutation),sort_keys=True)
        previous=self.db.execute('SELECT bytes FROM mutations WHERE op=?',(mutation.op,)).fetchone()
        if previous and previous[0] != raw: raise ValueError('identity collision with different bytes')
        self.db.execute('INSERT OR IGNORE INTO mutations VALUES(?,?)',(mutation.op,raw))
    def write(self, mutation, fail=False):
        with self.db:
            self.insert(mutation)
            if fail: raise OSError('injected before outbox commit')
            self.db.execute('INSERT OR IGNORE INTO outbox VALUES(?)',(mutation.op,))
    def receive(self, mutations, token, account='A', epoch=1, fail=False):
        if (account,epoch) != (self.account,self.epoch):raise ValueError('stale account callback')
        with self.db:
            for m in mutations:self.insert(m)
            if fail:raise OSError('injected before cursor commit')
            self.db.execute('UPDATE cursor SET value=max(value,?) WHERE id=1',(token,))
    def pending(self):return {x[0] for x in self.db.execute('SELECT op FROM outbox')}
    def ack(self, op, account='A', epoch=1):
        if (account,epoch) != (self.account,self.epoch):raise ValueError('stale account acknowledgement')
        with self.db:self.db.execute('DELETE FROM outbox WHERE op=?',(op,))
    def heads(self, entity):
        return publishable_heads(self.rows(), entity)
    def projection(self, entity):
        return project(self.rows(), entity)
    def candidates(self, key):
        return sorted(m.op for e in {m.entity for m in self.rows()} for m in self.heads(e) if m.business_key==key and not m.deleted)
    def put_blob(self, expected, data):
        if hashlib.sha256(data).hexdigest()!=expected:raise ValueError('checksum mismatch')
        with self.db:self.db.execute('INSERT OR IGNORE INTO blobs VALUES(?,?)',(expected,data))
    def export_image(self, expected):
        row=self.db.execute('SELECT bytes FROM blobs WHERE hash=?',(expected,)).fetchone()
        if not row:raise ValueError('full backup incomplete: original not local')
        return row[0]

class ProtocolTests(unittest.TestCase):
    def setUp(self):
        self.root=tempfile.TemporaryDirectory(prefix='PGOS-Sync-Protocol-')
        self.path=pathlib.Path(self.root.name)/'synthetic.sqlite'
        self.r=Replica(self.path)
    def tearDown(self):self.r.db.close();self.root.cleanup()
    def test_01_atomic_fact_and_outbox_failure_then_retry(self):
        m=Mutation('a1','entry',body='original')
        with self.assertRaises(OSError):self.r.write(m,fail=True)
        self.assertEqual(self.r.rows(),[]);self.assertEqual(self.r.pending(),set())
        self.r.write(m);self.r.db.close();self.r=Replica(self.path)
        self.assertEqual([x.body for x in self.r.rows()],['original']);self.assertEqual(self.r.pending(),{'a1'})
    def test_02_stale_ack_and_duplicate_ack(self):
        self.r.write(Mutation('a1','entry'));self.r.write(Mutation('a2','entry',('a1',),'newer'))
        self.r.ack('a1');self.r.ack('a1')
        self.assertEqual(self.r.pending(),{'a2'})
    def test_03_inbound_and_cursor_failure_are_atomic(self):
        with self.assertRaises(OSError):self.r.receive([Mutation('a1','entry')],7,fail=True)
        self.assertEqual(self.r.rows(),[]);self.assertEqual(self.r.db.execute('SELECT value FROM cursor').fetchone(),(0,))
        self.r.receive([Mutation('a1','entry')],7);self.r.receive([Mutation('a1','entry')],7)
        self.assertEqual(len(self.r.rows()),1);self.assertEqual(self.r.db.execute('SELECT value FROM cursor').fetchone(),(7,))
    def test_04_concurrent_edit_permutations_preserve_both(self):
        events=[Mutation('base','entry',body='base'),Mutation('a','entry',('base',),'A text'),Mutation('b','entry',('base',),'B text')]
        for order in itertools.permutations(events):
            r=Replica(':memory:')
            for token,m in enumerate(order):r.receive([m,m],token)
            self.assertEqual([(m.op,m.body) for m in r.heads('entry')],[('a','A text'),('b','B text')]);r.db.close()
    def test_05_delete_edit_keeps_tombstone_and_recoverable_edit(self):
        self.r.receive([Mutation('base','entry'),Mutation('del','entry',('base',),deleted=True),Mutation('edit','entry',('base',),'offline text')],1)
        self.assertEqual({(m.op,m.deleted,m.body) for m in self.r.heads('entry')},{('del',True,''),('edit',False,'offline text')})
        self.r.receive([Mutation('base','entry')],2)
        self.assertEqual({m.op for m in self.r.heads('entry')},{'del','edit'})
    def test_06_explicit_resolution_has_both_parents(self):
        self.r.receive([Mutation('a','entry',body='A'),Mutation('b','entry',body='B')],1)
        self.r.write(Mutation('resolve','entry',('a','b'),'A + B'))
        self.assertEqual([(m.op,m.body) for m in self.r.heads('entry')],[('resolve','A + B')])
        self.assertEqual({m.body for m in self.r.rows()},{'A','B','A + B'})
    def test_07_same_business_key_retains_candidates_only(self):
        self.r.receive([Mutation('a','sleepA',body='unknown',business_key='sleep:2026-01-01'),Mutation('b','sleepB',body='8h',business_key='sleep:2026-01-01')],1)
        self.assertEqual(self.r.candidates('sleep:2026-01-01'),['a','b'])
    def test_08_exact_mutation_replay_deduplicates_and_collision_rejects(self):
        m=Mutation('complete-A','todo:series1:42',body='completed')
        self.r.receive([m,m],1);self.r.receive([m],2)
        self.assertEqual(len(self.r.rows()),1)
        with self.assertRaises(ValueError):self.r.receive([Mutation('complete-A','todo:series1:42',body='canceled')],3)
        self.assertEqual(self.r.rows()[0].body,'completed')
    def test_09_missing_parent_is_staged_then_visible(self):
        self.r.receive([Mutation('link','objectLink',requires=('entry',))],1)
        self.assertEqual(self.r.heads('objectLink'),[]);self.assertEqual(len(self.r.rows()),1)
        self.r.receive([Mutation('entryCreate','entry')],2)
        self.assertEqual([m.op for m in self.r.heads('objectLink')],['link'])
    def test_10_unknown_wire_version_is_retained_not_applied(self):
        self.r.receive([Mutation('future','entry',body='unknown bytes',version=99)],1)
        self.assertEqual(self.r.heads('entry'),[]);self.assertEqual(self.r.rows()[0].body,'unknown bytes')
    def test_11_fixed_account_epoch_rejects_callbacks_not_rebinding(self):
        self.r.write(Mutation('offline','entry',body='private A'))
        self.r.epoch=2
        with self.assertRaises(ValueError):self.r.receive([Mutation('late','entry')],99,epoch=1)
        with self.assertRaises(ValueError):self.r.receive([Mutation('B','entry')],99,account='B',epoch=2)
        with self.assertRaises(ValueError):self.r.ack('offline',epoch=1)
        self.assertEqual(self.r.pending(),{'offline'});self.assertEqual(len(self.r.rows()),1)
    def test_12_partial_ack_keeps_failed_record(self):
        for key in ['ok','quota']:self.r.write(Mutation(key,key))
        self.r.ack('ok');self.assertEqual(self.r.pending(),{'quota'})
    def test_13_checksum_and_missing_asset_block_full_backup(self):
        original=b'synthetic original\x00\xff';digest=hashlib.sha256(original).hexdigest()
        with self.assertRaises(ValueError):self.r.export_image(digest)
        with self.assertRaises(ValueError):self.r.put_blob(digest,b'truncated')
        self.r.put_blob(digest,original);self.assertEqual(self.r.export_image(digest),original)
    def test_14_wall_clock_cannot_choose_winner(self):
        self.r.receive([Mutation('a','entry',body='timestamp 2099'),Mutation('b','entry',body='timestamp 1970')],1)
        self.assertEqual({m.op for m in self.r.heads('entry')},{'a','b'})
    def test_15_exact_old_mutation_replay_does_not_override_tombstone(self):
        original=Mutation('old','entry',body='backup')
        self.r.receive([original,Mutation('del','entry',('old',),deleted=True)],1)
        self.r.receive([original],2)
        self.assertEqual([(m.op,m.deleted) for m in self.r.heads('entry')],[('del',True)])
    def test_16_same_payload_different_ids_not_content_deduplicated(self):
        self.r.receive([Mutation('a','entry-A',body='same'),Mutation('b','entry-B',body='same')],1)
        self.assertEqual(len(self.r.heads('entry-A'))+len(self.r.heads('entry-B')),2)

if __name__=='__main__':unittest.main(verbosity=2)
