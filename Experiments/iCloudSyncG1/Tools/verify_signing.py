#!/usr/bin/env python3
"""Read-only, fail-closed entitlement/profile gate. No private fields printed."""
import argparse, datetime, json, pathlib, plistlib, subprocess, sys
from profile_entitlements import allows_cloudkit, allows_development, allows_container
p=argparse.ArgumentParser();p.add_argument('app',type=pathlib.Path);args=p.parse_args()
expected_bundle='com.yocruzer.PersonalGrowthOS.SyncLab'
expected_container='iCloud.com.yocruzer.PersonalGrowthOS.SyncLab'
team='83SKX2PM7B'
def command(*args):
 r=subprocess.run(args,capture_output=True)
 if r.returncode: raise ValueError('signature/profile command failed')
 return r.stdout
try:
 command('codesign','--verify','--strict',str(args.app))
 ent=plistlib.loads(command('codesign','-d','--entitlements',':-',str(args.app)))
 info_path=args.app/'Info.plist'
 if not info_path.exists(): info_path=args.app/'Contents/Info.plist'
 info=plistlib.loads(info_path.read_bytes())
 profiles=[args.app/'embedded.mobileprovision',args.app/'Contents/embedded.provisionprofile']
 path=next((x for x in profiles if x.exists()),None)
 if path is None: raise ValueError('embedded provisioning profile absent')
 profile=plistlib.loads(command('security','cms','-D','-i',str(path))); pe=profile['Entitlements']
 key='application-identifier' if 'application-identifier' in ent else 'com.apple.application-identifier'
 checks={
 'profileNotExpired': profile.get('ExpirationDate',datetime.datetime.min).replace(tzinfo=datetime.timezone.utc)>datetime.datetime.now(datetime.timezone.utc),
 'bundle': info.get('CFBundleIdentifier')==expected_bundle,
 'team': ent.get('com.apple.developer.team-identifier')==team and profile.get('TeamIdentifier')==[team],
 'appIdentifier': ent.get(key)==team+'.'+expected_bundle and pe.get(key)==ent.get(key),
 'cloudKit': allows_cloudkit(ent, pe),
 'container': allows_container(ent, pe, expected_container),
 'development': allows_development(ent, pe),
 'push': ent.get('aps-environment',ent.get('com.apple.developer.aps-environment'))=='development' and pe.get('aps-environment',pe.get('com.apple.developer.aps-environment'))=='development',
 'noProductGroup': not ent.get('com.apple.security.application-groups')
 }
 print(json.dumps({'status':'PASS' if all(checks.values()) else 'FAIL','checks':checks,'scope':'signature only; not cloud access'},indent=2))
 sys.exit(0 if all(checks.values()) else 1)
except Exception as e:
 print(json.dumps({'status':'FAIL','reason':str(e),'scope':'signature only; not cloud access'}));sys.exit(1)
