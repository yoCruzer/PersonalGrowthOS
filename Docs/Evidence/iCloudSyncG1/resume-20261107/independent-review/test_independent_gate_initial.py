"""Synthetic verifier integration tests: subprocess codesign/security outputs are mocked.
No actual app, provisioning profile, account, device or signing logs are read.
"""
import contextlib, copy, datetime, io, json, pathlib, plistlib, runpy, subprocess, sys, tempfile, unittest
from unittest.mock import patch
TOOLS = pathlib.Path('/private/tmp/PersonalGrowthOS-icloud-g1/Experiments/iCloudSyncG1/Tools')
sys.path.insert(0, str(TOOLS))
BUNDLE='com.yocruzer.PersonalGrowthOS.SyncLab'
CONTAINER='iCloud.com.yocruzer.PersonalGrowthOS.SyncLab'
TEAM='83SKX2PM7B'
SERVICE='com.apple.developer.icloud-services'
ENV='com.apple.developer.icloud-container-environment'
CONTAINERS='com.apple.developer.icloud-container-identifiers'
def fixture():
    signed={'application-identifier':TEAM+'.'+BUNDLE,'com.apple.developer.team-identifier':TEAM,SERVICE:['CloudKit'],ENV:'Development',CONTAINERS:[CONTAINER],'aps-environment':'development'}
    allowed=copy.deepcopy(signed);allowed[SERVICE]='*';allowed[ENV]=['Production','Development']
    profile={'Entitlements':allowed,'TeamIdentifier':[TEAM],'ExpirationDate':datetime.datetime(2099,1,1)}
    return signed,profile,{'CFBundleIdentifier':BUNDLE}
def invoke(signed, profile, info, signature_ok=True, embedded=True):
    with tempfile.TemporaryDirectory(prefix='g1-synthetic-gate-') as temp:
        app=pathlib.Path(temp)/'Synthetic.app';app.mkdir()
        (app/'Info.plist').write_bytes(plistlib.dumps(info))
        if embedded:(app/'embedded.mobileprovision').write_bytes(b'SYNTHETIC-PLACEHOLDER')
        def command(args, **kwargs):
            if args[0]=='codesign' and '--verify' in args:
                return subprocess.CompletedProcess(args,0 if signature_ok else 1,stdout=b'',stderr=b'')
            if args[0]=='codesign':return subprocess.CompletedProcess(args,0,stdout=plistlib.dumps(signed),stderr=b'')
            if args[0]=='security':return subprocess.CompletedProcess(args,0,stdout=plistlib.dumps(profile),stderr=b'')
            raise AssertionError('Unexpected subprocess')
        out=io.StringIO()
        with patch.object(sys,'argv',['verify_signing.py',str(app)]),patch('subprocess.run',command),contextlib.redirect_stdout(out):
            try:runpy.run_path(str(TOOLS/'verify_signing.py'),run_name='__main__')
            except SystemExit as ex:code=ex.code
        return code,json.loads(out.getvalue())
CASES={
'observed_profile':(lambda s,p,i:None,True),
'environment_order_reversed':(lambda s,p,i:p['Entitlements'].__setitem__(ENV,['Development','Production']),True),
'explicit_service_list':(lambda s,p,i:p['Entitlements'].__setitem__(SERVICE,['CloudDocuments','CloudKit']),True),
'wildcard_service_list':(lambda s,p,i:p['Entitlements'].__setitem__(SERVICE,['*']),True),
'profile_no_cloudkit':(lambda s,p,i:p['Entitlements'].__setitem__(SERVICE,['CloudDocuments']),False),
'profile_partial_wildcard':(lambda s,p,i:p['Entitlements'].__setitem__(SERVICE,['Cloud*']),False),
'profile_malformed_service':(lambda s,p,i:p['Entitlements'].__setitem__(SERVICE,['*',7]),False),
'profile_production_only':(lambda s,p,i:p['Entitlements'].__setitem__(ENV,['Production']),False),
'profile_environment_wildcard':(lambda s,p,i:p['Entitlements'].__setitem__(ENV,['*']),False),
'profile_malformed_environment':(lambda s,p,i:p['Entitlements'].__setitem__(ENV,['Development',7]),False),
'signed_service_wildcard':(lambda s,p,i:s.__setitem__(SERVICE,['*']),False),
'signed_extra_service':(lambda s,p,i:s.__setitem__(SERVICE,['CloudKit','CloudDocuments']),False),
'signed_service_string':(lambda s,p,i:s.__setitem__(SERVICE,'CloudKit'),False),
'signed_production':(lambda s,p,i:s.__setitem__(ENV,'Production'),False),
'signed_environment_list':(lambda s,p,i:s.__setitem__(ENV,['Development']),False),
'wrong_team':(lambda s,p,i:s.__setitem__('com.apple.developer.team-identifier','SYNTHETIC-WRONG'),False),
'wrong_bundle':(lambda s,p,i:i.__setitem__('CFBundleIdentifier','com.synthetic.wrong'),False),
'wrong_container':(lambda s,p,i:s.__setitem__(CONTAINERS,['iCloud.com.synthetic.wrong']),False),
'profile_wrong_container':(lambda s,p,i:p['Entitlements'].__setitem__(CONTAINERS,['iCloud.com.synthetic.wrong']),False),
'profile_expired':(lambda s,p,i:p.__setitem__('ExpirationDate',datetime.datetime(2000,1,1)),False),
'wrong_push':(lambda s,p,i:s.__setitem__('aps-environment','production'),False),
'product_app_group':(lambda s,p,i:s.__setitem__('com.apple.security.application-groups',['group.com.yocruzer.PersonalGrowthOS']),False),
}
class GateIntegrationTests(unittest.TestCase):
    def test_invalid_signature_denied(self):
        self.assertEqual(invoke(*fixture(),signature_ok=False)[0],1)
    def test_missing_embedded_profile_denied(self):
        self.assertEqual(invoke(*fixture(),embedded=False)[0],1)
for name,(mutate,expected) in CASES.items():
    def test(self, mutate=mutate, expected=expected):
        s,p,i=fixture();mutate(s,p,i);code,result=invoke(s,p,i)
        self.assertEqual(code,0 if expected else 1)
        self.assertEqual(result['status'],'PASS' if expected else 'FAIL')
        self.assertEqual(result['scope'],'signature only; not cloud access')
    setattr(GateIntegrationTests,'test_'+name,test)
if __name__=='__main__':unittest.main(verbosity=2)
