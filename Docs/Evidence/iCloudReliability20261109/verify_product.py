from pathlib import Path
import json,subprocess,collections
root=Path('/private/tmp/PGOS-ICloud-Reliability-CI')
head='59104222b0ca654ca5cffa8faed3e2f208e91b2e';checkout='280327a64e85b149c0ec5fb47f76681420cf61ea'
run=json.loads((root/'run-42630679905.json').read_text());assert run['head_sha']==head and run['conclusion']=='success'
assert not subprocess.check_output(['git','diff','--name-only',head,checkout,'--','PersonalGrowthOS','PersonalGrowthOSTests','PersonalGrowthOSUITests','PersonalGrowthOS.xcodeproj','Packages','Scripts','.github'])
zips={x['name']:x for x in json.loads((root/'zip-verification-42630679905.json').read_text())}
lanes=[]
def cases(node):
 if isinstance(node,dict):
  if node.get('nodeType')=='Test Case':yield node
  for value in node.values():yield from cases(value)
 elif isinstance(node,list):
  for value in node:yield from cases(value)
for lane in ['release','unit','smoke']:
 r=root/('ios-'+lane+'-1');env=json.loads((r/'environment.json').read_text())
 assert env['headSHA']==head and env['checkoutSHA']==checkout and env['githubSHA']==checkout
 item=dict(lane=lane,**zips['ios-'+lane+'-1'],headSHA=head,checkoutSHA=checkout,xcode=env['xcode'].strip(),conclusion='success')
 if lane=='release':
  bundles=json.loads((r/'bundles.json').read_text());assert len(bundles)==3;item['unsignedBundles']=bundles
 else:
  summary=json.loads((r/'test-summary.json').read_text());tests=list(cases(json.loads((r/'test-tests.json').read_text())))
  counts=collections.Counter(x['result'] for x in tests)
  expected=(715,714,1) if lane=='unit' else (8,8,0)
  assert (summary['totalTestCount'],summary['passedTests'],summary['skippedTests'])==expected
  assert summary['failedTests']==0 and summary['runtimeWarnings']==[] and summary['testFailures']==[]
  assert len(tests)==expected[0] and counts['Passed']==expected[1] and counts['Skipped']==expected[2],counts
  for k in ['totalTestCount','passedTests','failedTests','skippedTests','runtimeWarnings']:item[k]=summary[k]
  item['device']={k:env['deviceType'].get(k) for k in ['name','identifier']}
  item['runtime']={k:env['runtime'].get(k) for k in ['version','buildversion']}
  if lane=='unit':
   skipped=[x['name'] for x in tests if x['result']=='Skipped']
   assert skipped==['testRealLowSpaceVolumeHealthyOpenMigrationAndCorruptCopyFailure()'];item['skippedTestNames']=skipped
   assert any(x['name']=='testBatchAndCallbackFailuresKeepLongestRetryAndProtectiveErrors()' and x['result']=='Passed' for x in tests)
   item['skipReason']='Requires isolated 32MB HFS+ image; primary volume never filled.'
  else:item['testNames']=[x['name'] for x in tests]
 lanes.append(item)
report=dict(sourceHead=head,runID=42630679905,conclusion='success',checkoutSHA=checkout,checkoutRelevantInputsMatch='PASS',lanes=lanes,optionalExtendedUI='NOT_RUN: workflow_dispatch condition not selected',distributionSigned=False,testFlightAvailable='NOT_OBSERVED',realTwoDeviceBackgroundAndFullIntegrity='NOT_RUN')
(root/'product-verification.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
