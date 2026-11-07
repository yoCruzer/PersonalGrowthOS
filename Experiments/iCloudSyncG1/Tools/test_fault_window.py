import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import fault_window as window
from verify_fault_window import redact, verify


class FaultWindowTests(unittest.TestCase):
    def test_regular_reader_rejects_symlink_fifo_and_oversize(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d); actual=root/'actual'; actual.write_bytes(b'private fixture')
            link=root/'link'; link.symlink_to(actual)
            with self.assertRaises(OSError):window.read_regular(link)
            with self.assertRaises(ValueError):window.read_regular(actual,2)
            fifo=root/'fifo';os.mkfifo(fifo)
            with self.assertRaises(ValueError):window.read_regular(fifo)
            self.assertEqual(window.read_regular(actual),b'private fixture')

    def test_result_publication_is_atomic_and_never_replaces(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'report.json'
            window.publish(b'original',path)
            with self.assertRaises(FileExistsError):window.publish(b'replacement',path)
            self.assertEqual(path.read_bytes(),b'original')
            self.assertEqual(list(Path(d).iterdir()),[path])

    def test_stage_components_cannot_escape(self):
        window.safe_stage('03-mac-fetch-crash')
        window.safe_stage('21-mac-account-A')
        for name in ['../escape','03-../../escape','/tmp/out','03-foo/bar','03-foo\\bar','03-','x'*200,23]:
            with self.assertRaises(ValueError):window.safe_stage(name)

    def test_changed_manifest_and_plan_fail_before_launch(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d); (root/'plans/03-mac-fetch-crash').mkdir(parents=True)
            plan={'id':'probe-a','commands':[]}
            manifest=json.dumps([{'name':'03-mac-fetch-crash','device':'macOS','plan':plan}]).encode()
            (root/'window.json').write_text(json.dumps({'manifestSHA256':window.sha(manifest)}))
            (root/'plans/manifest.json').write_bytes(manifest)
            path=root/'plans/03-mac-fetch-crash/SyncLab-Probe-Plan.json'
            path.write_text(json.dumps(plan))
            self.assertEqual(window.load_stage(root,'03-mac-fetch-crash')[1]['plan'],plan)
            path.write_text('{}')
            with self.assertRaises(ValueError):window.load_stage(root,'03-mac-fetch-crash')
            (root/'plans/manifest.json').write_bytes(manifest+b' ')
            with self.assertRaises(ValueError):window.load_stage(root,'03-mac-fetch-crash')

    def test_redaction_is_recursive_and_keeps_truth(self):
        value={'accountFingerprint':'private','faultObservations':[{'sourceAccountHash':'private2','processNonce':'nonce','snapshot':{'text':'SYNTHETIC'}}]}
        clean=redact(value)
        self.assertNotIn('private',json.dumps(clean))
        self.assertEqual(clean['faultObservations'][0]['processNonce'],'nonce')
        self.assertEqual(value['accountFingerprint'],'private')

    def test_missing_evidence_never_passes(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);(root/'manifest.json').write_text('[]')
            with self.assertRaises(ValueError):verify(root,root)


if __name__=='__main__':unittest.main()
