from pathlib import Path
import base64,hashlib,json,plistlib,subprocess
repo=Path('/private/tmp/PersonalGrowthOS-icloud-execution-guard')
package=repo/'Packages/SyncFoundation'
u=Path('/private/tmp/pgos-guard-completion-package-20261108')
s=Path('/private/tmp/PGOS-FormalSigning-20261108-cfpay1lu/runtime-guard-completion')
app=s/'FormalSyncProbe.app';binary=app/'Contents/MacOS/FormalDevelopmentHost'
sha=lambda b:hashlib.sha256(b).hexdigest()
checks=[]
def check(name,good):
 checks.append({'check':name,'passed':bool(good)})
 if not good:raise AssertionError(name)
receiptBytes=(u/'packaging.json').read_bytes();receipt=json.loads(receiptBytes)
pins=json.loads((repo/'Scripts/FormalDevelopmentHost/trusted-source-sha256.json').read_text())
def sourceMap(root):
 files=[root/'Package.swift']+list((root/'Sources').rglob('*.swift'))+list((root/'Tests').rglob('*.swift'))
 return {str(p.relative_to(root)):sha(p.read_bytes()) for p in files}
current=sourceMap(package);snapshot=sourceMap(u/'source-snapshot')
check('complete-current-source-map-and-reviewed-pins',current==pins and len(current)==40)
check('receipt-and-actual-compiler-source-snapshot',snapshot==current==receipt['sourceSHA256'])
check('build-success-without-cloud-or-signing-authority',receipt['buildExitCode']==0 and receipt['packagingCloudOperations']==0 and not receipt['cloudRunAuthorized'] and not receipt['p0Passed'])
check('unsigned-binary-receipt',sha((u/'FormalSyncProbe.app/Contents/MacOS/FormalDevelopmentHost').read_bytes())==receipt['binarySHA256'])
check('signed-copy-retains-exact-unsigned-receipt',(s/'unsigned-source-receipt.json').read_bytes()==receiptBytes)
check('signed-info-bound-to-reviewed-receipt',sha((app/'Contents/Info.plist').read_bytes())==receipt['infoSHA256'])
check('external-entitlement-candidate-bound-to-receipt',sha((s/'candidate.entitlements').read_bytes())==receipt['candidateEntitlementsSHA256'])
requestBytes=(s/'offline-request.json').read_bytes();request=json.loads(requestBytes);binding=request['runtime']
rbytes=base64.b64decode(request['packagingReceipt'],validate=True);pbytes=base64.b64decode(request['sourcePins'],validate=True)
check('offline-input-mode-and-canonical-bytes',request['mode']=='OFFLINE_RUNTIME_INSPECTION' and requestBytes==json.dumps(request,sort_keys=True,separators=(',',':')).encode())
check('offline-receipt-byte-binding',rbytes==receiptBytes and sha(rbytes)==binding['packagingReceiptSHA256'])
check('offline-source-pins-map-and-byte-binding',json.loads(pbytes)==pins and sha(pbytes)==binding['sourcePinsSHA256'])
check('signed-executable-and-profile-byte-binding',sha(binary.read_bytes())==binding['signedBinarySHA256'] and sha((app/'Contents/embedded.provisionprofile').read_bytes())==binding['profileSHA256'])
verify=subprocess.run(['/usr/bin/codesign','--verify','--deep','--strict',str(app)],capture_output=True)
check('independent-strict-code-signature-verification',verify.returncode==0)
details=subprocess.run(['/usr/bin/codesign','-d','--verbose=4',str(app)],capture_output=True)
metadata={}
for line in details.stderr.decode(errors='replace').splitlines():
 if line.startswith(('Identifier=','TeamIdentifier=','CDHash=')):
  k,v=line.split('=',1);metadata[k]=v
check('actual-code-directory-team-and-independent-bundle',details.returncode==0 and metadata.get('CDHash')==binding['codeDirectoryHash'] and metadata.get('TeamIdentifier')=='83SKX2PM7B' and metadata.get('Identifier')=='com.yocruzer.PersonalGrowthOS.FormalSyncProbe')
ent=subprocess.run(['/usr/bin/codesign','-d','--entitlements',':-',str(app)],capture_output=True)
actualEnt=plistlib.loads(ent.stdout)
check('actual-applied-entitlements-match-reviewed-candidate',ent.returncode==0 and actualEnt==plistlib.loads((s/'candidate.entitlements').read_bytes()))
report=json.loads((s/'inspect-runtime.stdout').read_bytes());exitinfo=json.loads((s/'inspect-runtime-exit.json').read_bytes())
check('existing-execution-report-bound-to-binary-and-request',exitinfo['exit']==0 and exitinfo['binarySHA256']==binding['signedBinarySHA256'] and exitinfo['requestSHA256']==sha(requestBytes))
check('existing-real-runtime-qualified-signature-device-session-path',report['status']=='SELF_QUALIFICATION_PASS' and all(report.get(k) is True for k in ['signatureProfileDeviceVerified','osSessionVerified','applicationSupportParentVerified']))
check('existing-runtime-report-makes-no-cloud-owner-or-p0-claim',report['mode']=='OFFLINE_ONLY' and report['networkOperations']==0 and report['accountQualification']=='NOT_RUN' and report['actualServiceAccess']=='NOT_RUN' and all(report.get(k) is False for k in ['networkAuthorized','ownerApprovalVerified','p0Passed']))
result={'status':'PASS','checks':checks,'passed':len(checks),'failed':0,'sourceFiles':len(current),'signedBinarySHA256':binding['signedBinarySHA256'],'codeDirectoryHash':binding['codeDirectoryHash'],'profileSHA256':binding['profileSHA256'],'packagingReceiptSHA256':binding['packagingReceiptSHA256'],'sourcePinsSHA256':binding['sourcePinsSHA256'],'reviewedRuntimeReportSHA256':sha((s/'inspect-runtime.stdout').read_bytes()),'applicationReexecuted':False,'cloudOperations':0,'privateCertificateOrDeviceValuesPublished':False,'limits':['Existing signed runtime observation was independently rebound, not rerun.','This verifies offline artifact/source/signing correspondence, not test iCloud identity or real service behavior.','No raw profile, certificates, device identifiers or Apple account values copied or emitted.']}
Path('/private/tmp/pgos-entry-independent-evidence-20261108/signed-binding-review.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
