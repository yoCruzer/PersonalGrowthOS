"""Synthetic seed-recovery checks. No runtime evidence, App or CloudKit access."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
import verify_fault_window as verifier


class SeedRecoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.plans, self.results = self.root/'plans', self.root/'results'
        self.account = 'a'*64  # Synthetic; never a real account identifier.
        commands = [{'id':'probe-seed-connect','action':'connect'}]
        for i in range(12):
            mutation = {'version':1,'id':f'probe-m-{i}','object':f'probe-o-{i}',
                        'parents':[],'requires':[],'text':f'SYNTHETIC {i}','deleted':False}
            commands.append({'id':f'probe-seed-save-{i}','action':'save','mutation':mutation})
        commands += [{'id':'probe-seed-'+suffix,'action':action}
                     for suffix,action in [('sync','sync'),('drain','sync'),('snapshot','snapshot')]]
        self.plan = {'version':1,'id':'probe-original-seed','dataset':'synthetic-g1-unit-deps',
                     'runID':'probe-unit-run','commands':commands}
        self.stage = {'name':'00-mac-dependency-seed','device':'macOS','plan':self.plan}
        self.raw = verifier.canonical(self.plan)
        self.rows = []
        mutations = []
        for command in commands[:14]:
            if 'mutation' in command: mutations.append(command['mutation'])
            self.rows.append(self.result(command,self.plan,mutations,'original-process'))
        self.rows[-1].update(status='FAIL', errorCode='CK_4')
        self.rows[-1].pop('snapshot')  # Actual failed sync need not return a snapshot.
        self.original = self.report(self.plan,self.raw,self.rows,False)
        self.original['errorCode'] = 'CK_4'
        self.recovery_plan = {'version':1,'id':'probe-r7-dependency-recover-001',
                              'dataset':self.plan['dataset'],'runID':self.plan['runID'],
                              'commands':[{'id':'probe-r7-dependency-recover-'+suffix,'action':action}
                                          for suffix,action in [('connect','connect'),('sync','sync'),('drain','sync'),('snapshot','snapshot')]]}
        self.recovery_raw = verifier.canonical(self.recovery_plan)
        recovered = [self.result(c,self.recovery_plan,mutations,'fresh-process') for c in self.recovery_plan['commands']]
        self.recovery = self.report(self.recovery_plan,self.recovery_raw,recovered,True)
        self.write()

    def tearDown(self):
        self.temp.cleanup()

    def result(self, command, plan, mutations, nonce):
        return {'id':command['id'],'commandDigest':verifier.digest(verifier.canonical(command)),
                'planID':plan['id'],'dataset':plan['dataset'],'runID':plan['runID'],
                'status':'PASS','halted':False,'platform':'macOS','processNonce':nonce,'processID':123,
                'accountFingerprint':self.account,'accountSource':'liveCloudKit','events':[],
                'snapshot':{'envelopes':[{'version':1,'object':m['object'],'mutations':[copy.deepcopy(m)]} for m in mutations],'images':{}},
                'snapshotComplete':True,'unavailableImages':[],'pendingKeys':[]}

    def report(self, plan, raw, rows, complete):
        return {'planID':plan['id'],'dataset':plan['dataset'],'runID':plan['runID'],
                'planDigest':verifier.digest(raw),'completedAllCommands':complete,'results':rows}

    def write(self):
        entries = [(self.results/'00-mac-dependency-seed/report.json', self.original),
                   (self.plans/'00-mac-dependency-recover/SyncLab-Probe-Plan.json', self.recovery_plan),
                   (self.results/'00-mac-dependency-recover/report.json', self.recovery)]
        for path,value in entries:
            path.parent.mkdir(parents=True,exist_ok=True)
            path.write_bytes(verifier.canonical(value))

    def verify(self):
        self.write()
        rows = verifier.dependency_report(self.plan,self.raw,self.original,self.account,'macOS',seed_failure=True)
        return verifier.dependency_seed_recovery(self.stage,rows,self.plans,self.results,self.account)

    def test_valid_recovery_preserves_failed_original_bytes(self):
        before=(self.results/'00-mac-dependency-seed/report.json').read_bytes()
        rows,summary=self.verify()
        self.assertEqual(len(rows),4)
        self.assertEqual(summary['originalStatus'],'FAIL')
        self.assertEqual(summary['originalError'],'CK_4')
        self.assertEqual(summary['originalReportSHA256'],verifier.digest(before))
        self.assertEqual((self.results/'00-mac-dependency-seed/report.json').read_bytes(),before)

    def test_normal_completed_report_still_passes(self):
        report=copy.deepcopy(self.original);report.pop('errorCode');report['completedAllCommands']=True
        report['results']=[self.result(c,self.plan,[],'original-process') for c in self.plan['commands']]
        self.assertEqual(len(verifier.dependency_report(self.plan,self.raw,report,self.account,'macOS')),16)

    def test_ck4_failure_is_not_accepted_without_seed_exception(self):
        with self.assertRaises(ValueError):verifier.dependency_report(self.plan,self.raw,self.original,self.account,'macOS')

    def test_failure_boundary_is_exact(self):
        changes=[lambda r:r.update(errorCode='CK_2'),lambda r:r['results'][-1].update(errorCode='CK_2'),
                 lambda r:r['results'][2].update(status='FAIL',errorCode='CK_4'),
                 lambda r:r.update(results=r['results'][:-1]),lambda r:r.update(completedAllCommands=True),
                 lambda r:r['results'][-1].update(status='PASS'),lambda r:r['results'][-1].update(halted=True)]
        original=copy.deepcopy(self.original)
        for change in changes:
            with self.subTest(change=changes.index(change)):
                self.original=copy.deepcopy(original);change(self.original)
                with self.assertRaises(ValueError):self.verify()

    def test_wrong_original_command_digest_rejected(self):
        self.original['results'][3]['commandDigest']='0'*64
        with self.assertRaises(ValueError):self.verify()

    def test_original_prefix_loss_cannot_be_hidden_by_recovery(self):
        self.original['results'][3]['snapshot']['envelopes'].pop()
        with self.assertRaises(ValueError):self.verify()

    def test_nonempty_original_connect_rejected(self):
        self.original['results'][0]['snapshot']=copy.deepcopy(self.original['results'][1]['snapshot'])
        with self.assertRaises(ValueError):self.verify()

    def test_recovery_requires_fresh_process(self):
        for row in self.recovery['results']:row['processNonce']='original-process'
        with self.assertRaises(ValueError):self.verify()

    def test_recovery_requires_same_account(self):
        for row in self.recovery['results']:row['accountFingerprint']='b'*64
        with self.assertRaises(ValueError):self.verify()

    def test_recovery_plan_is_exact(self):
        changes=[lambda p:p['commands'][1].update(action='save'),lambda p:p['commands'][1].update(id='probe-wrong'),
                 lambda p:p['commands'][1].update(mutation={}),lambda p:p.update(id='probe-other'),
                 lambda p:p.update(dataset='synthetic-g1-other'),lambda p:p.update(runID='probe-other'),
                 lambda p:p['commands'].reverse(),lambda p:p.update(commands=p['commands'][:-1])]
        original=copy.deepcopy(self.recovery_plan)
        for change in changes:
            with self.subTest(change=changes.index(change)):
                self.recovery_plan=copy.deepcopy(original);change(self.recovery_plan)
                with self.assertRaises(ValueError):self.verify()

    def test_recovery_lost_fact_in_connect_cannot_hide_at_end(self):
        self.recovery['results'][0]['snapshot']['envelopes'].pop()
        with self.assertRaises(ValueError):self.verify()

    def test_recovery_failed_or_incomplete_rejected(self):
        self.recovery['results'][1].update(status='FAIL',errorCode='CK_4')
        with self.assertRaises(ValueError):self.verify()

    def test_recovery_pending_or_wrong_digest_rejected(self):
        self.recovery['results'][-1]['pendingKeys']=['object-probe-o-1']
        with self.assertRaises(ValueError):self.verify()
        self.recovery['results'][-1]['pendingKeys']=[];self.recovery['planDigest']='0'*64
        with self.assertRaises(ValueError):self.verify()

    def test_missing_recovery_report_rejected(self):
        (self.results/'00-mac-dependency-recover/report.json').unlink()
        with self.assertRaises(ValueError):
            verifier.dependency_seed_recovery(self.stage,self.rows,self.plans,self.results,self.account)


if __name__=='__main__':unittest.main()
