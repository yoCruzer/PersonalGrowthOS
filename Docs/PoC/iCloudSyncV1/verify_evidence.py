#!/usr/bin/env python3
"""Crosscheck native diagnostics against source-derived inventory and pinned tree."""
import hashlib, json, pathlib, subprocess
ROOT=pathlib.Path(__file__).resolve().parents[3]
E=ROOT/'Docs/Evidence/iCloudSyncV1'
x=json.loads((E/'schema-inventory.json').read_text())
assert x['counts']==dict(entities=39,fields=263,unique=52,requiredWithoutDeclarationDefault=221)
log=(E/'shape-cloud.log').read_text()
section=log.split('The following attributes are marked non-optional but do not have a default value:\n',1)[1].split('CloudKit integration requires that all relationships',1)[0]
native=set(section.strip().splitlines())
source={name+': '+f['name'] for name,m in x['models'].items() for f in m['fields'] if not f['type'].endswith('?') and f['default'] is None and not f['relationship']}
assert native==source,(native-source,source-native)
unique=set(log.split('The following entities are constrained:\n',1)[1].split('}',1)[0].strip().splitlines())
assert unique=={name+': '+f['name'] for name,m in x['models'].items() for f in m['fields'] if f['unique']}
assert 'Entry: images' in log and '134060' in log and 'bundleIdentifier != nil' in log
for name,digest in json.loads((E/'production-source-sha256.json').read_text()).items():
    assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest,name
subprocess.run(['git','diff','--exit-code',x['baseline'],'--','.',':(exclude)Docs'],cwd=ROOT,check=True)
unknown=subprocess.check_output(['git','ls-files','--others','--exclude-standard'],cwd=ROOT,text=True).splitlines()
assert all(p.startswith('Docs/') for p in unknown),unknown
runs=json.loads((E/'native-runs.json').read_text())
actual={r['label']:r['exitCode'] for r in runs['commands']}
assert actual==dict(compile=0,**{'shape-local':0,'shape-cloud':-6,'compatible-local':0,'write':0,'rollback':0,'crash-before-save':73,'verify':0}),actual
assert 'Ran 16 tests' in (E/'protocol-tests.log').read_text() and (E/'protocol-tests.log').read_text().rstrip().endswith('OK')
print('PASS: native/source exact sets 221 attributes, 52 unique; 39 model inventory; original Swift hashes; non-Docs tree unchanged; raw outcomes retained')
