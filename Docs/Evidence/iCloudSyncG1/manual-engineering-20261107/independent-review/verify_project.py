from pathlib import Path
import plistlib,shutil,subprocess,tempfile
root=Path('/private/tmp/PersonalGrowthOS-icloud-g1/Experiments/iCloudSyncG1')
def check(root):
 project=plistlib.loads((root/'SyncLab.xcodeproj/project.pbxproj').read_bytes())
 configs={x['name']:x['buildSettings'] for x in project['objects'].values() if x.get('isa')=='XCBuildConfiguration' and 'INFOPLIST_FILE' in x.get('buildSettings',{})}
 assert configs['Debug']['INFOPLIST_FILE']=='App/InfoDebug.plist'
 assert configs['Debug']['SWIFT_ACTIVE_COMPILATION_CONDITIONS']=='DEBUG'
 assert configs['Release']['INFOPLIST_FILE']=='App/Info.plist'
 assert not configs['Release']['SWIFT_ACTIVE_COMPILATION_CONDITIONS']
 debug=plistlib.loads((root/configs['Debug']['INFOPLIST_FILE']).read_bytes())
 release=plistlib.loads((root/configs['Release']['INFOPLIST_FILE']).read_bytes())
 for key in ['UIFileSharingEnabled','LSSupportsOpeningDocumentsInPlace']:
  assert debug[key] is True
  assert not release.get(key)
 refs={x.get('path') for x in project['objects'].values() if x.get('isa')=='PBXFileReference'}
 assert {'Sources/SyncLab/DevelopmentAuthorization.swift','Sources/SyncLab/ManualProbePlan.swift'}<=refs
check(root)
with tempfile.TemporaryDirectory(prefix='g1-generator-review-') as temp:
 copy=Path(temp);shutil.copytree(root/'Sources',copy/'Sources');(copy/'App').mkdir();(copy/'Tools').mkdir()
 shutil.copyfile(root/'Tools/generate_project.py',copy/'Tools/generate_project.py')
 subprocess.run(['/usr/bin/python3',str(copy/'Tools/generate_project.py')],check=True,capture_output=True)
 check(copy)
 assert (copy/'SyncLab.xcodeproj/project.pbxproj').read_bytes()==(root/'SyncLab.xcodeproj/project.pbxproj').read_bytes()
print('PASS: current and independently regenerated project select sharing only in Debug; Release uses base Info without sharing; source membership and project bytes match.')
