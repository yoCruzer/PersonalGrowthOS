import os
"""No App/cloud: copied transport Swift source, minimal local stubs, synthetic HTTP."""
from http.server import HTTPServer,BaseHTTPRequestHandler
import hashlib,json,subprocess,threading,time
from pathlib import Path
ROOT=Path(os.environ['G1_LOOPBACK_OUT']);seen=[];mode='good'
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*a):pass
 def do_POST(self):
  raw=self.rfile.read(int(self.headers['Content-Length']));seen.append((self.path,self.headers.get('Authorization'),self.headers.get('X-SyncLab-Launch'),raw))
  if mode=='redirect':self.send_response(307);self.send_header('Location',f'http://127.0.0.1:{self.server.server_port}/redirect-target');self.end_headers();return
  self.send_response(500 if mode=='error' else 200);self.end_headers()
  data=json.dumps({'acceptedSHA256':hashlib.sha256(raw).hexdigest()}).encode()
  if mode=='wrong-digest':data=b'{"acceptedSHA256":"wrong"}'
  if mode=='invalid-json':data=b'not-json'
  if mode=='oversized':data=b' '*1100+data
  if mode=='timeout':time.sleep(8)
  try:self.wfile.write(data)
  except BrokenPipeError:pass
server=HTTPServer(('127.0.0.1',0),Handler);thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
try:
 for mode in ['good','wrong-digest','error','invalid-json','oversized','redirect','timeout']:
  seen.clear();start=time.monotonic();out=subprocess.check_output([str(ROOT/'transport-harness'),f'http://127.0.0.1:{server.server_port}'],text=True).strip();expected='ACCEPTED' if mode=='good' else 'REJECTED'
  assert out==expected,(mode,out);assert len(seen)==1 and seen[0][0]=='/report';assert seen[0][1]=='Bearer '+'a'*64;assert seen[0][2]=='12345678-1234-1234-1234-123456789ABC';assert time.monotonic()-start<8
  print('PASS',mode,flush=True)
finally:server.shutdown();server.server_close()
