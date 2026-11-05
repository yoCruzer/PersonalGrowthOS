#!/usr/bin/env python3
"""Deterministic standalone project; no third-party generator, no product mutations."""
from pathlib import Path
import hashlib, plistlib
root = Path(__file__).resolve().parents[1]
def uid(s): return hashlib.sha256(s.encode()).hexdigest()[:24].upper()
objects={}
def add(key,**values):
    objects[uid(key)]=values
    return uid(key)
sources=sorted((root/'Sources/SyncLab').glob('*.swift'))+[root/'App/SyncLabApp.swift']
refs=[]; builds=[]
for source in sources:
    path=str(source.relative_to(root)); ref=add(path,isa='PBXFileReference',lastKnownFileType='sourcecode.swift',path=path,sourceTree='<group>');refs.append(ref)
    builds.append(add('build:'+path,isa='PBXBuildFile',fileRef=ref))
product=add('product',isa='PBXFileReference',explicitFileType='wrapper.application',path='SyncLab.app',sourceTree='BUILT_PRODUCTS_DIR')
products=add('products',isa='PBXGroup',children=[product],name='Products',sourceTree='<group>')
main=add('main',isa='PBXGroup',children=refs+[products],sourceTree='<group>')
phase=add('sources',isa='PBXSourcesBuildPhase',buildActionMask='2147483647',files=builds,runOnlyForDeploymentPostprocessing='0')
configs=[]; project_configs=[]
for name in ['Debug','Release']:
    settings=dict(PRODUCT_NAME='SyncLab',PRODUCT_BUNDLE_IDENTIFIER='com.yocruzer.PersonalGrowthOS.SyncLab',DEVELOPMENT_TEAM='83SKX2PM7B',CODE_SIGN_STYLE='Automatic',CODE_SIGN_ENTITLEMENTS='App/SyncLab.entitlements',INFOPLIST_FILE='App/Info.plist',GENERATE_INFOPLIST_FILE='NO',SWIFT_VERSION='5.0',IPHONEOS_DEPLOYMENT_TARGET='17.0',MACOSX_DEPLOYMENT_TARGET='14.0',SUPPORTED_PLATFORMS='iphoneos iphonesimulator macosx',TARGETED_DEVICE_FAMILY='1,2',ENABLE_HARDENED_RUNTIME='YES',ENABLE_APP_SANDBOX='YES',MARKETING_VERSION='0.1',CURRENT_PROJECT_VERSION='1',SWIFT_OPTIMIZATION_LEVEL='-Onone' if name=='Debug' else '-O',SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG' if name=='Debug' else '',SDKROOT='iphoneos')
    settings['CODE_SIGN_ENTITLEMENTS[sdk=macosx*]']='App/SyncLabMac.entitlements'
    configs.append(add('target:'+name,isa='XCBuildConfiguration',name=name,buildSettings=settings))
    project_configs.append(add('project:'+name,isa='XCBuildConfiguration',name=name,buildSettings={'CLANG_ENABLE_MODULES':'YES'}))
config=add('target-config',isa='XCConfigurationList',buildConfigurations=configs,defaultConfigurationIsVisible='0',defaultConfigurationName='Debug')
project_config=add('project-config',isa='XCConfigurationList',buildConfigurations=project_configs,defaultConfigurationIsVisible='0',defaultConfigurationName='Debug')
target=add('target',isa='PBXNativeTarget',name='SyncLab',productName='SyncLab',productReference=product,productType='com.apple.product-type.application',buildConfigurationList=config,buildPhases=[phase],buildRules=[],dependencies=[])
project=add('project',isa='PBXProject',attributes={'LastUpgradeCheck':'2700','TargetAttributes':{target:{'CreatedOnToolsVersion':'27.2'}}},buildConfigurationList=project_config,compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings='0',knownRegions=['en','Base'],mainGroup=main,productRefGroup=products,projectDirPath='',projectRoot='',targets=[target])
pbx=root/'SyncLab.xcodeproj'; pbx.mkdir(exist_ok=True)
(pbx/'project.pbxproj').write_bytes(plistlib.dumps({'archiveVersion':'1','classes':{},'objectVersion':'56','objects':objects,'rootObject':project},sort_keys=True))
scheme=pbx/'xcshareddata/xcschemes';scheme.mkdir(parents=True,exist_ok=True)
(scheme/'SyncLab.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="SyncLab.app" BlueprintName="SyncLab" ReferencedContainer="container:SyncLab.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="SyncLab.app" BlueprintName="SyncLab" ReferencedContainer="container:SyncLab.xcodeproj"/></BuildableProductRunnable></LaunchAction></Scheme>''')
info={'CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleName':'SyncLab','CFBundlePackageType':'APPL','CFBundleShortVersionString':'$(MARKETING_VERSION)','CFBundleVersion':'$(CURRENT_PROJECT_VERSION)','LSMinimumSystemVersion':'$(MACOSX_DEPLOYMENT_TARGET)','UILaunchScreen':{},'UIBackgroundModes':['remote-notification']}
(root/'App/Info.plist').write_bytes(plistlib.dumps(info))
ents={'com.apple.developer.icloud-container-identifiers':['iCloud.com.yocruzer.PersonalGrowthOS.SyncLab'],'com.apple.developer.icloud-services':['CloudKit'],'com.apple.developer.icloud-container-environment':'Development','aps-environment':'development'}
(root/'App/SyncLab.entitlements').write_bytes(plistlib.dumps(ents))
ents.pop('aps-environment');ents.update({'com.apple.developer.aps-environment':'development','com.apple.security.app-sandbox':True,'com.apple.security.network.client':True})
(root/'App/SyncLabMac.entitlements').write_bytes(plistlib.dumps(ents))
