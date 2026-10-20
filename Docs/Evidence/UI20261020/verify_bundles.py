import pathlib,plistlib,json,subprocess,hashlib,sys
# Frozen product/test candidate; an optional argument selects another built candidate.
sha=sys.argv[1] if len(sys.argv)>1 else '537a6f9103f6ccbf08b8634edf6dfc976247b4c8'
expected={"Archive activity":"归档活动","Restore activity":"恢复活动","Previous month":"上个月","Next month":"下个月","Try Again":"重试","No data":"暂无数据","Quantity":"数量","This todo changed. Reload its reminder settings before trying again.":"此待办已更改。请重新载入提醒设置后再试。"}
today={"Today entry":"今天入口","Show sleep on Today":"在今天显示睡眠入口","Today display":"今天展示","Always in Today":"始终在今天显示","Hidden from Today":"不在今天显示"}
rows=[]
for configuration,location in [("Debug","/private/tmp/pgos-ui-derived/Build/Products/Debug-iphonesimulator"),("Release","/private/tmp/pgos-ui-release/Build/Products/Release-iphoneos")]:
 app=pathlib.Path(location)/'PersonalGrowthOS.app'
 provenance=plistlib.loads((app/'BuildProvenance.plist').read_bytes());assert provenance['Commit']==sha and provenance['Dirty'] is False
 for bundle in [app,*sorted(app.glob('PlugIns/*.appex'))]:
  info=plistlib.loads((bundle/'Info.plist').read_bytes());expectedID={'PersonalGrowthOS.app':'com.yocruzer.PersonalGrowthOS','ShareExtension.appex':'com.yocruzer.PersonalGrowthOS.ShareExtension','ImportantDaysWidget.appex':'com.yocruzer.PersonalGrowthOS.ImportantDaysWidget'}[bundle.name]
  assert info['CFBundleIdentifier']==expectedID
  assert (info['CFBundleShortVersionString'],info['CFBundleVersion'],info['MinimumOSVersion'])==('1.0','7','17.0')
  row={'configuration':configuration,'bundle':bundle.name,'identifier':expectedID,'version':'1.0(7)','minimumOS':'17.0','resources':{}}
  for language in ['en','zh-Hans']:
   file=bundle/(language+'.lproj')/'Localizable.strings';d=plistlib.loads(file.read_bytes())
   for key,value in expected.items():assert d[key]==(key if language=='en' else value),(bundle,key)
   for key,value in today.items():assert d[key]==(key if language=='en' else value),(bundle,key)
   row['resources'][language]={'count':len(d),'sha256':hashlib.sha256(file.read_bytes()).hexdigest(),'new8AndToday5':'PASS'}
  signature=subprocess.run(['codesign','-d',str(bundle)],capture_output=True,text=True)
  row['codesignExit']=signature.returncode;row['codesignMessage']=(signature.stdout+signature.stderr).strip()
  if configuration=='Release': assert signature.returncode!=0 and 'not signed at all' in row['codesignMessage']
  if bundle==app:
   row['provenance']=provenance
   for language,text in [('en','Capture photos you choose to save in your private entries.'),('zh-Hans','拍摄你选择保存在私人记录中的照片。')]:
    d=plistlib.loads((bundle/(language+'.lproj')/'InfoPlist.strings').read_bytes());assert d['NSCameraUsageDescription']==text
   row['cameraResources']='PASS en + zh-Hans'
   binary=bundle/info['CFBundleExecutable']
   if configuration=='Debug':binary=bundle/'PersonalGrowthOS.debug.dylib'
   links=subprocess.check_output(['otool','-l',str(binary)],text=True)
   marker=links.find('name /System/Library/Frameworks/AlarmKit.framework/AlarmKit')
   assert marker>=0 and 'LC_LOAD_WEAK_DYLIB' in links[max(0,marker-150):marker]
   row['AlarmKitWeakLink']='PASS'
  rows.append(row)
print(json.dumps({'head':sha,'result':'PASS','bundles':rows},ensure_ascii=False,indent=2))
