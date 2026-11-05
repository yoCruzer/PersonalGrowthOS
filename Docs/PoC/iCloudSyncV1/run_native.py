#!/usr/bin/env python3
"""Generate native models with exact V16 stored declarations, run only synthetic stores."""
import datetime, hashlib, json, os, pathlib, platform, subprocess, sys, tempfile
ROOT=pathlib.Path(__file__).resolve().parents[3]
HERE=pathlib.Path(__file__).resolve().parent
DEST=pathlib.Path(sys.argv[1]).resolve();DEST.mkdir(parents=True,exist_ok=True)
if (DEST/'native-runs.json').exists():
    raise SystemExit('Use a new evidence directory; previous run evidence is immutable.')
WORK=pathlib.Path(tempfile.mkdtemp(prefix='PGOS-iCloud-Native-'))
subprocess.run([sys.executable,str(HERE/'inventory.py'),str(DEST)],check=True)
inv=json.loads((DEST/'schema-inventory.json').read_text())
defaults={'UUID':'UUID()','String':'""','Date':'Date(timeIntervalSince1970:0)','Int':'0','Int64':'0','Double':'0','Bool':'false','Data':'Data()','[ImageMetadata]':'[]'}
code=['import Foundation\nimport SwiftData']
for name in inv['entities']:
    model=inv['models'][name];code.append('@Model final class '+name+' {')
    fields=model['fields']
    for f in fields:
        annotation='@Attribute(.unique) ' if f['unique'] else ''
        if f['relationship']:annotation+=f['relationship']+'\n'
        code.append(annotation+'var '+f['name']+': '+f['type']+((' = '+f['default']) if f['default'] else ''))
    code.append('init() {')
    for f in fields:
        value='nil' if f['type'].endswith('?') else defaults[f['type']]
        code.append('self.'+f['name']+' = '+value)
    code.append('}\n}')
code.append('let auditModelTypes: [any PersistentModel.Type] = ['+', '.join(x+'.self' for x in inv['entities'])+']')
generated=WORK/'Models.swift';generated.write_text('\n'.join(code))
(DEST/'generated-models.swift').write_text(generated.read_text())
commands=[]
def run(label,cmd,expected=0):
    result=subprocess.run(cmd,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    (DEST/(label+'.log')).write_text(result.stdout)
    commands.append(dict(label=label,command=cmd,exitCode=result.returncode,expectedExit=expected))
    print(label,result.returncode,flush=True)
    if label == 'shape-cloud':
        assert result.returncode in (0,-6) and '134060' in result.stdout and 'does not support unique constraints' in result.stdout and 'Entry: images' in result.stdout
        if result.returncode == -6:
            assert 'bundleIdentifier != nil' in result.stdout
            print('LIMITATION: schema rejection observed, then unbundled command-line teardown aborted (-6)',flush=True)
    elif result.returncode != expected:raise RuntimeError(label+' failed; see log')
try:
    run('compile',['xcrun','swiftc','-parse-as-library','-module-cache-path',str(WORK/'cache'),str(generated),str(HERE/'native.swift'),'-o',str(WORK/'audit')])
    for mode in ['shape-local','shape-cloud','compatible-local','write','rollback','crash-before-save','verify']:
        store=WORK/mode if mode.startswith('shape-') or mode == 'compatible-local' else WORK/'outbox'
        run(mode,[str(WORK/'audit'),mode,str(store)],73 if mode=='crash-before-save' else 0)
    cloud=(DEST/'shape-cloud.log').read_text()
    assert '134060' in cloud and 'unique' in cloud.lower() and 'optional' in cloud.lower(), 'Need model-validation evidence, not entitlement-only failure'
finally:
    result=dict(dateUTC=datetime.datetime.now(datetime.timezone.utc).isoformat(),platform=platform.platform(),work=str(WORK),
        baseline=inv['baseline'],commands=commands,network='No explicit account lookup or CK operation invoked. Cloud configuration uses a fabricated container ID; native model preflight rejects it. No signed cloud test or successful cloud store.')
    (DEST/'native-runs.json').write_text(json.dumps(result,indent=2)+'\n')
