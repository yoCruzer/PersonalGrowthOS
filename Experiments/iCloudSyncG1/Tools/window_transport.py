"""Authenticated, one-stage loopback collection. Never accesses App containers."""
import base64
import hmac
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
import re
import secrets
import subprocess
import threading
import uuid
from fault_window import canonical, publish, read_regular, sha

POINTS={73:'beforeSaveCommit',74:'afterSaveCommit',75:'afterFetchedInstall',76:'afterFetchedState',77:'assetLeaseBeforeACK'}


def unique_object(pairs):
    result={}
    for key,value in pairs:
        if key in result: raise ValueError('Duplicate JSON key')
        result[key]=value
    return result


def require(value):
    if not value: raise ValueError('Invalid stage evidence')


def validate_plan(stage,raw):
    require(len(raw)<=24576)
    plan=stage['plan'];require(json.loads(raw,object_pairs_hook=unique_object)==plan and plan.get('version')==1)
    for key,prefix in [('id','probe-'),('dataset','synthetic-g1-'),('runID','probe-')]:
        value=plan.get(key);require(isinstance(value,str) and value.startswith(prefix) and re.fullmatch('[A-Za-z0-9_-]{1,128}',value))
    commands=plan.get('commands');require(isinstance(commands,list) and 1<=len(commands)<=16)
    ids=[]
    actions={'connect','save','sync','snapshot','reopen','stop','openCached','reopenLocal','crashBeforeSave','crashAfterSave','crashOnFetch','crashOnState','editDuringSend','inspectFaults','imageFaults','restoreIsolation','waitForAccountChange','closePartition','crashWithImageLease'}
    for command in commands:
        name=command.get('id');require(isinstance(name,str) and re.fullmatch('probe-[A-Za-z0-9_-]{1,122}',name) and command.get('action') in actions)
        ids.append(name)
    require(len(set(ids))==len(ids))
    require(stage.get('expectedExit') is None or type(stage['expectedExit']) is int and stage['expectedExit'] in POINTS)
    return plan


class Receiver(HTTPServer):
    def __init__(self, output, stage, plan_bytes):
        self.plan=validate_plan(stage,plan_bytes)
        self.output=output;self.stage=stage;self.plan_bytes=plan_bytes
        self.token=secrets.token_hex(32);self.launch=str(uuid.uuid4());self.nonce=None
        self.count=0;self.total=0
        super().__init__(('127.0.0.1',0),Handler)
    def get_request(self):
        connection,address=super().get_request();connection.settimeout(3);return connection,address
    def identity(self,value):
        require(value.get('planID')==self.plan['id'] and value.get('dataset')==self.plan['dataset'] and value.get('runID')==self.plan['runID'])
    def process(self,value):
        nonce=value.get('processNonce');require(isinstance(nonce,str));uuid.UUID(nonce)
        require(type(value.get('processID')) is int and value['processID']>0)
        require(self.nonce is None or self.nonce==nonce);self.nonce=nonce
    def accept(self,kind,data):
        require(len(data)<=32000000)
        value=json.loads(data,object_pairs_hook=unique_object);require(isinstance(value,dict))
        if kind=='failure':
            require(value=={'code':'WINDOW_FAILED'});target=self.output/'failure.json'
        elif kind=='report':
            self.identity(value);require(value.get('planDigest')==sha(self.plan_bytes))
            rows=value['results'];require(isinstance(rows,list) and 1<=len(rows)<=len(self.plan['commands']))
            require(type(value.get('completedAllCommands')) is bool)
            for command,result in zip(self.plan['commands'],rows):
                self.identity(result);self.process(result)
                require(result.get('id')==command['id'] and result.get('commandDigest')==sha(canonical(command)) and result.get('platform')=='macOS')
                require(result.get('status') in ('PASS','FAIL') and type(result.get('halted')) is bool)
            target=self.output/'report.json'
        elif kind=='observation':
            self.identity(value);self.process(value)
            command=next((c for c in self.plan['commands'] if c['id']==value.get('commandID')),None)
            require(command is not None and value.get('commandDigest')==sha(canonical(command)))
            point=value.get('point');require(isinstance(point,str) and re.fullmatch(r'[A-Za-z0-9_-]{1,128}',point))
            require(isinstance(value.get('sourceAccountHash'),str) and re.fullmatch('[0-9a-f]{64}',value['sourceAccountHash']))
            cloud=command['action'] in ('crashOnFetch','crashOnState','crashWithImageLease','editDuringSend','restoreIsolation')
            require(value.get('provenance')==('actualCloudKitCallback' if cloud else 'localTransactionOrFileFault'))
            directory=self.output/'observations';directory.mkdir(exist_ok=True)
            target=directory/(command['id']+'-'+point+'.json')
            if point==POINTS.get(self.stage.get('expectedExit')):
                require(command==self.plan['commands'][-1])
                self.persist(data,self.output/'boundary.json')
        else: raise ValueError('Unknown output route')
        self.persist(data,target)
        return canonical({'acceptedSHA256':sha(data)})
    def persist(self,data,target):
        if target.exists() or target.is_symlink():
            require(read_regular(target)==data)
        else: publish(data,target)


class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args): pass
    def do_POST(self):
        self.close_connection=True
        try:
            require(hmac.compare_digest(self.headers.get('Authorization',''),'Bearer '+self.server.token))
            require(hmac.compare_digest(self.headers.get('X-SyncLab-Launch',''),self.server.launch))
            require(self.headers.get('Transfer-Encoding') is None)
            require(len(self.headers.get_all('Content-Length',[]))==1)
            length=int(self.headers['Content-Length']);require(0<length<=32000000)
            self.server.count+=1;self.server.total+=length
            require(self.server.count<=128 and self.server.total<=96000000)
            require(self.path in ('/report','/observation','/failure'))
            data=self.rfile.read(length);require(len(data)==length)
            response=self.server.accept(self.path[1:],data)
        except Exception:
            self.send_response(400);self.send_header('Content-Length','0');self.end_headers();return
        self.send_response(200);self.send_header('Content-Type','application/json')
        self.send_header('Content-Length',str(len(response)));self.end_headers();self.wfile.write(response)


def run_network(root,name,config,stage,plan_bytes):
    validate_plan(stage,plan_bytes)
    require(os.getuid()==config['testUID'])
    output=root/'results'/name;output.mkdir()
    app=root/'SyncLab.app';require(sha((app/'Contents/MacOS/SyncLab').read_bytes())==config['executableSHA256'])
    subprocess.run(['/usr/bin/codesign','--verify','--strict',str(app)],check=True)
    server=Receiver(output,stage,plan_bytes)
    thread=threading.Thread(target=server.serve_forever,kwargs={'poll_interval':0.1},daemon=True);thread.start()
    plan=stage['plan'];env=dict(os.environ)
    for key in list(env):
        if key.startswith('SYNCLAB_'):env.pop(key)
    env.update(SYNCLAB_ENABLE_DEVELOPMENT='YES',SYNCLAB_DATASET=plan['dataset'],SYNCLAB_PROBE_RUN=plan['runID'],
               SYNCLAB_PROBE_WINDOW_URL='http://127.0.0.1:'+str(server.server_port),SYNCLAB_PROBE_WINDOW_TOKEN=server.token,
               SYNCLAB_PROBE_WINDOW_LAUNCH=server.launch,SYNCLAB_PROBE_WINDOW_PLAN=base64.b64encode(plan_bytes).decode())
    publish(canonical({'launchID':server.launch,'planID':plan['id'],'planDigest':sha(plan_bytes),'scope':'Authenticated loopback; app exit status not exposed'}),output/'transport.json')
    try:
        subprocess.run(['/usr/bin/open','-n','-W','-a',str(app)],env=env,check=True,timeout=720)
    finally:
        server.shutdown();thread.join(timeout=4);server.server_close()
    require(not (output/'failure.json').exists())
    if (output/'report.json').exists():
        report=json.loads(read_regular(output/'report.json'))
        require(stage.get('expectedExit') is None and report['completedAllCommands'] is True)
        require(len(report['results'])==len(plan['commands']))
        require(all(r['status']=='PASS' and r['halted'] is False and r.get('errorCode') is None for r in report['results']))
    else: require(stage.get('expectedExit') in POINTS and (output/'boundary.json').exists())
    print(name+': fresh loopback evidence collected; paired acceptance pending',flush=True)
