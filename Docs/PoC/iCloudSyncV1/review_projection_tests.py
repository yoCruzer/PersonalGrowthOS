"""Fixed expectations for R1/R2. No network, accounts, or product statistics."""
import itertools
import unittest
from protocol_probe import Mutation, Replica
from protocol_rules import Projection


class ProjectionTests(unittest.TestCase):
    def setUp(self):
        self.r = Replica(':memory:')
    def tearDown(self):
        self.r.db.close()
    def receive(self, *events):
        self.r.receive(events, 1)
    def test_01_common_ancestor_preview_is_order_independent_and_incomplete(self):
        events = [Mutation('base','entry',body='100'),
                  Mutation('a','entry',('base',),'110'),
                  Mutation('b','entry',('base',),'120')]
        for order in itertools.permutations(events):
            r = Replica(':memory:')
            try:
                for i,m in enumerate(order): r.receive([m,m], i)
                self.assertEqual(r.projection('entry'),
                    Projection('conflict','100',('a','b'),'base'))
                self.assertFalse(r.projection('entry').complete)
            finally: r.db.close()
    def test_02_unrelated_conflicts_have_no_invented_value(self):
        self.receive(Mutation('a','entry',body='110'),Mutation('b','entry',body='120'))
        self.assertEqual(self.r.projection('entry'),Projection('conflict',candidates=('a','b')))
    def test_03_delete_edit_never_revives_normal_value(self):
        events=[Mutation('base','entry',body='100'),
                Mutation('del','entry',('base',),deleted=True),
                Mutation('edit','entry',('base',),'120')]
        for order in itertools.permutations(events):
            r=Replica(':memory:')
            try:
                for i,m in enumerate(order):r.receive([m],i)
                self.assertEqual(r.projection('entry'),
                    Projection('deleted_conflict',candidates=('del','edit')))
                self.assertEqual(len(r.rows()),3)
            finally:r.db.close()
    def test_04_explicit_resolution_becomes_confirmed(self):
        self.receive(Mutation('a','entry',body='A'),Mutation('b','entry',body='B'),
                     Mutation('resolved','entry',('a','b'),'A+B'))
        p=self.r.projection('entry')
        self.assertEqual(p,Projection('ready','A+B',('resolved',)))
        self.assertTrue(p.complete)
        self.assertEqual({m.body for m in self.r.rows()},{'A','B','A+B'})
    def test_05_missing_dependency_arrival_unblocks_transitively(self):
        self.receive(Mutation('entry','entry',requires=('owner',)),
                     Mutation('link','link',requires=('entry',)))
        self.assertEqual(self.r.heads('link'),[])
        self.receive(Mutation('owner','owner'))
        self.assertEqual([m.op for m in self.r.heads('link')],['link'])
    def test_06_current_unready_revision_cannot_fall_back_to_old_live_row(self):
        self.receive(Mutation('old','entry'),Mutation('new','entry',('old',),requires=('missing',)),
                     Mutation('link','link',requires=('entry',)))
        self.assertEqual(self.r.heads('entry'),[])
        self.assertEqual(self.r.heads('link'),[])
    def test_07_dependency_conflict_blocks_link_until_resolved(self):
        self.receive(Mutation('a','entry'),Mutation('b','entry'),
                     Mutation('link','link',requires=('entry',)))
        self.assertEqual(self.r.heads('link'),[])
        self.receive(Mutation('resolved','entry',('a','b')))
        self.assertEqual([m.op for m in self.r.heads('link')],['link'])
    def test_08_required_entity_cycle_is_staged(self):
        self.receive(Mutation('a','entry',requires=('link',)),
                     Mutation('b','link',requires=('entry',)))
        self.assertEqual(self.r.heads('entry'),[])
        self.assertEqual(self.r.heads('link'),[])
    def test_09_cross_object_causal_parent_is_not_a_valid_history(self):
        self.receive(Mutation('a','entry'),Mutation('b','link',('a',)))
        self.assertEqual(self.r.heads('link'),[])
    def test_10_unknown_version_keeps_bytes_and_blocks_dependency(self):
        self.receive(Mutation('old','entry'),Mutation('future','entry',('old',),version=99),
                     Mutation('link','link',requires=('entry',)))
        self.assertEqual(self.r.heads('link'),[])
        self.assertEqual(self.r.projection('entry').state,'staged')
        self.assertEqual(len(self.r.rows()),3)
    def test_11_multiple_maximal_common_ancestors_have_no_arbitrary_baseline(self):
        self.receive(Mutation('a','entry',body='A'),Mutation('b','entry',body='B'),
                     Mutation('x','entry',('a','b'),'X'),Mutation('y','entry',('a','b'),'Y'))
        self.assertEqual(self.r.projection('entry'),Projection('conflict',candidates=('x','y')))
    def test_12_deleted_common_ancestor_is_not_used_as_a_live_preview(self):
        self.receive(Mutation('del','entry',deleted=True),
                     Mutation('a','entry',('del',),'A'),Mutation('b','entry',('del',),'B'))
        self.assertEqual(self.r.projection('entry'),Projection('conflict',candidates=('a','b')))
    def test_13_delete_dependency_all_arrival_orders_stays_unpublished(self):
        events=[Mutation('create','entry'),Mutation('del','entry',('create',),deleted=True),
                Mutation('link','link',requires=('entry',))]
        for order in itertools.permutations(events):
            r=Replica(':memory:')
            try:
                for i,m in enumerate(order):r.receive([m,m],i)
                self.assertEqual(r.heads('link'),[])
                self.assertEqual(len(r.rows()),3)
            finally:r.db.close()
    def test_14_tombstone_does_not_wait_for_deleted_dependency(self):
        self.receive(Mutation('old','link',requires=('missing',)),
                     Mutation('del','link',('old',),deleted=True,requires=('missing',)))
        self.assertEqual(self.r.projection('link'),Projection('deleted',candidates=('del',)))


if __name__ == '__main__':unittest.main(verbosity=2)
