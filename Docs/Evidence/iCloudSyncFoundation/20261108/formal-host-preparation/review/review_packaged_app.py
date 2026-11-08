import hashlib,json,pathlib,plistlib,subprocess,sys,shutil
root=pathlib.Path('/private/tmp/PGOS-UnsignedHostReview-rebp7hh1');evidence=root/'positive-and-negatives';evidence.mkdir()
output=pathlib.Path('/private/tmp/pgos-locked-app-bound-20261108')
repo=pathlib.Path('/private/tmp/PersonalGrowthOS-icloud-foundation')
script=repo/'Scripts/FormalDevelopmentHost/package_locked_host.py'
probe=pathlib.Path('/private/tmp/pgos-sync-sdk-build/out/Products/Debug/FormalDevelopmentProbe')
sha=lambda b:hashlib.sha256(b).hexdigest();checks=[]
def check(name,condition):
    assert condition,name
    checks.append({'name':name,'passed':True})
def command(name,args,exitcode):
    p=subprocess.run(list(map(str,args)),capture_output=True)
    (evidence/(name+'.stdout')).write_bytes(p.stdout);(evidence/(name+'.stderr')).write_bytes(p.stderr)
    assert p.returncode==exitcode,(name,p.returncode,p.stderr)
    checks.append({'name':name,'exit':p.returncode,'expected':exitcode})
receipt=json.loads((output/'packaging.json').read_bytes());app=output/'FormalSyncProbe.app';binary=app/'Contents/MacOS/FormalDevelopmentHost'
info=plistlib.loads((app/'Contents/Info.plist').read_bytes());ent=plistlib.loads((output/'candidate.entitlements').read_bytes())
check('all-20-input-files-bound-to-receipt-snapshot-and-current-source',len(receipt['sourceSHA256'])==20 and all(sha((output/'source-snapshot'/name).read_bytes())==h==sha((repo/'Packages/SyncFoundation'/name).read_bytes()) for name,h in receipt['sourceSHA256'].items()))
check('three-artifact-hashes',sha(binary.read_bytes())==receipt['binarySHA256'] and sha((app/'Contents/Info.plist').read_bytes())==receipt['infoSHA256'] and sha((output/'candidate.entitlements').read_bytes())==receipt['candidateEntitlementsSHA256'])
check('exact-independent-macos-identity',info['CFBundleIdentifier']=='com.yocruzer.PersonalGrowthOS.FormalSyncProbe' and info['CFBundleExecutable']=='FormalDevelopmentHost' and info['CFBundleSupportedPlatforms']==['MacOSX'] and info['LSMinimumSystemVersion']=='14.0')
check('candidate-not-applied-and-no-profile',not (app/'Contents/embedded.provisionprofile').exists() and not (app/'Contents/_CodeSignature').exists() and not list(app.rglob('*.entitlements')) and ent['com.apple.developer.icloud-container-identifiers']==['iCloud.com.yocruzer.PersonalGrowthOS'] and ent['com.apple.developer.icloud-container-environment']=='Development' and ent['com.apple.security.app-sandbox'] is True and ent['com.apple.security.network.client'] is True and 'aps-environment' not in ent and 'com.apple.security.application-groups' not in ent)
check('receipt-claims-only-build',receipt['appExecutionPerformed'] is False and receipt['developerSigningPerformed'] is False and receipt['cloudRunAuthorized'] is False and receipt['p0Passed'] is False and receipt['packagingCloudOperations']==0)
command('create-plan',[probe,'plan',evidence/'plan'],0);planhash=(evidence/'plan/plan.sha256').read_text().strip()
command('app-still-locked',[binary,'inspect',evidence/'plan',planhash,evidence/'inspect'],2)
report=json.loads((evidence/'inspect/report.json').read_bytes());check('runtime-rejects-authority',report['status']=='NOT_READY' and report['failure']=='EXTERNAL_GATE_NOT_COMPLETE' and report['networkAuthorized'] is False and report['networkOperations']==0)
command('real-preflight-rejects-app',[probe,'preflight',evidence/'plan',planhash,app,evidence/'preflight'],2)
preflight=json.loads((evidence/'preflight/report.json').read_bytes());check('real-preflight-no-profile-or-identity',preflight['status']=='NOT_READY' and 'PROFILE_MISSING' in preflight['rejectionCodes'] and 'CODE_IDENTITY_MISMATCH' in preflight['rejectionCodes'] and preflight['readyForCloudRun'] is False)
command('live-option-rejected',[binary,'live',evidence/'plan',planhash,evidence/'live'],64)
before=sha((output/'packaging.json').read_bytes());command('existing-output-rejected',[sys.executable,script,'--output',output],1);check('existing-receipt-unchanged',sha((output/'packaging.json').read_bytes())==before)
link=evidence/'parent-link';link.symlink_to(evidence,target_is_directory=True)
command('parent-symlink-rejected',[sys.executable,script,'--output',link/'escaped'],1);check('no-symlink-output',not (evidence/'escaped').exists())
fixture=root/'NegativeRepo';(fixture/'Scripts/FormalDevelopmentHost').mkdir(parents=True)
for name in ['package_locked_host.py','trusted-source-sha256.json']:shutil.copy2(repo/'Scripts/FormalDevelopmentHost'/name,fixture/'Scripts/FormalDevelopmentHost'/name)
shutil.copytree(repo/'Packages/SyncFoundation',fixture/'Packages/SyncFoundation',ignore=shutil.ignore_patterns('.build','.swiftpm'))
negative_script=fixture/'Scripts/FormalDevelopmentHost/package_locked_host.py';package=fixture/'Packages/SyncFoundation'
extra=package/'Sources/FormalDevelopmentHost/Injected.swift';extra.write_text('// extra unreviewed synthetic input\n')
command('extra-source-rejected',[sys.executable,negative_script,'--output',evidence/'extra-output'],1);check('extra-source-rejects-before-output',not (evidence/'extra-output').exists());extra.unlink()
main=package/'Sources/FormalDevelopmentHost/main.swift';main.rename(main.with_name('main.swift.saved'))
command('missing-source-rejected',[sys.executable,negative_script,'--output',evidence/'missing-output'],1);main.with_name('main.swift.saved').rename(main)
command('output-inside-source-rejected',[sys.executable,negative_script,'--output',package/'created-output'],1);check('source-path-unchanged',not (package/'created-output').exists())
summary={'status':'PASS','count':len(checks),'checks':checks,'reviewedPackagerSHA256':sha(script.read_bytes()),'actualBinarySHA256':sha(binary.read_bytes()),'developerSigningPerformed':False,'cloudKitNetworkOperations':0,'p0Passed':False}
(evidence/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps(summary,indent=2))
