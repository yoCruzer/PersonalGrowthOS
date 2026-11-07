import http.client
import hashlib
import json
from pathlib import Path
import tempfile
import threading
import unittest
from probe_bridge import Bridge, enqueue


class ProbeBridgeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.server = Bridge(self.root, 'synthetic-g1-test', 'probe-run')
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown(); self.server.server_close(); self.thread.join()
        self.temp.cleanup()

    def request(self, method, path, data=None, authorized=True):
        connection = http.client.HTTPConnection('127.0.0.1', self.server.server_port, timeout=2)
        headers = {'Authorization': 'Bearer ' + self.server.token} if authorized else {}
        connection.request(method, path, body=data, headers=headers)
        response = connection.getresponse(); result = response.status, response.read()
        connection.close(); return result

    def command(self):
        path = self.root / 'command.json'
        path.write_text(json.dumps({'id': 'probe-001', 'action': 'snapshot'}))
        enqueue(self.root, path)

    def result(self, **changes):
        value = {'id': 'probe-001', 'status': 'PASS', 'dataset': 'synthetic-g1-test', 'runID': 'probe-run',
                 'commandDigest': hashlib.sha256((self.root / 'command.json').read_bytes()).hexdigest()}
        value.update(changes)
        return json.dumps(value).encode()

    def test_authentication_and_route_limits(self):
        self.assertEqual(self.request('GET', '/next', authorized=False)[0], 403)
        self.assertEqual(self.request('GET', '/files')[0], 404)
        self.assertEqual(self.request('POST', '/result', b'{}', authorized=False)[0], 403)
        self.assertEqual(self.request('GET', '/next'), (200, b''))

    def test_queue_and_immutable_result_retry(self):
        self.command()
        self.assertEqual(json.loads(self.request('GET', '/next')[1])['id'], 'probe-001')
        data = self.result()
        self.assertEqual(self.request('POST', '/result', data)[0], 200)
        self.assertEqual(self.request('POST', '/result', data)[0], 200)
        self.assertEqual(self.request('POST', '/result', self.result(status='FAIL'))[0], 409)
        self.assertEqual(self.request('GET', '/next'), (200, b''))

    def test_unknown_result_and_path_traversal_rejected(self):
        self.assertEqual(self.request('POST', '/result', b'{"id":"probe-unknown","status":"PASS"}')[0], 409)
        self.assertEqual(self.request('POST', '/result', b'{"id":"../private","status":"PASS"}')[0], 400)
        self.assertEqual(list((self.root / 'results').iterdir()), [])

    def test_command_cannot_be_replaced_or_execute_shell(self):
        self.command()
        with self.assertRaises(FileExistsError): enqueue(self.root, self.root / 'command.json')
        p = self.root / 'bad.json'; p.write_text('{"id":"probe-002","action":"shell"}')
        with self.assertRaises(ValueError): enqueue(self.root, p)

    def test_result_must_match_dataset_run_and_exact_command(self):
        self.command()
        for changes in [{'dataset': 'synthetic-g1-other'}, {'runID': 'probe-old'}, {'commandDigest': '0' * 64}]:
            with self.subTest(changes=changes):
                self.assertEqual(self.request('POST', '/result', self.result(**changes))[0], 409)
                self.assertNotEqual(self.request('GET', '/next')[1], b'')
        self.assertEqual(self.request('POST', '/result', b'{"id":"probe-001","status":"PASS"}')[0], 409)


if __name__ == '__main__': unittest.main()
