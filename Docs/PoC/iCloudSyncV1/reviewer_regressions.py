"""Expected to FAIL on exact PR #15 protocol_probe.py; no CloudKit is used."""
import unittest
from protocol_probe import Mutation, Replica

class DependencySafetyRegressions(unittest.TestCase):
    def setUp(self): self.r = Replica(':memory:')
    def tearDown(self): self.r.db.close()
    def check_hidden(self, parents):
        self.r.receive(parents + [Mutation('link', 'link', requires=('entry',))], 1)
        self.assertEqual(self.r.heads('link'), [],
                         'Unpublishable dependency must not make a child visible')
    def test_R1a_parent_deleted(self):
        self.check_hidden([Mutation('entry-create', 'entry'),
                           Mutation('entry-delete', 'entry', ('entry-create',), deleted=True)])
    def test_R1b_parent_has_missing_ancestor(self):
        self.check_hidden([Mutation('entry-update', 'entry', ('missing-entry-base',))])
    def test_R1c_parent_has_missing_required_entity(self):
        self.check_hidden([Mutation('entry-create', 'entry', requires=('missing-owner',))])
    def test_R1d_parent_has_invalid_causal_cycle(self):
        self.check_hidden([Mutation('entry-a', 'entry', ('entry-b',)),
                           Mutation('entry-b', 'entry', ('entry-a',))])

if __name__ == '__main__': unittest.main(verbosity=2)
