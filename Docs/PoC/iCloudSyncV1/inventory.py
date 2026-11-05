#!/usr/bin/env python3
"""Read-only inventory of the pinned V16 source. Not a general Swift parser."""
import hashlib, json, pathlib, re, subprocess, sys
ROOT = pathlib.Path(__file__).resolve().parents[3]
DEST = pathlib.Path(sys.argv[1])
DEST.mkdir(parents=True, exist_ok=True)
persistence = (ROOT/'PersonalGrowthOS/Persistence/PersistenceFoundation.swift').read_text()
def block(text, start):
    opening = text.index('{', start)
    depth = 1
    pos = opening + 1
    while depth:
        depth += (text[pos] == '{') - (text[pos] == '}')
        pos += 1
    return text[opening+1:pos-1]
schemas = {}
for m in re.finditer(r'enum (PersonalGrowthSchema\w+): VersionedSchema', persistence):
    body = block(persistence, m.start())
    model_body = block(body, body.index('static var models:'))
    parents = re.findall(r'(PersonalGrowthSchema\w+)\.models', model_body)
    schemas[m[1]] = sum((schemas[p] for p in parents), []) + re.findall(r'(\w+)\.self', model_body)
models = {}
manifest = {}
for file in sorted((ROOT/'PersonalGrowthOS').rglob('*.swift')):
    raw = file.read_bytes(); text = raw.decode()
    manifest[str(file.relative_to(ROOT))] = hashlib.sha256(raw).hexdigest()
    for m in re.finditer(r'@Model\s+final class (\w+)\s*\{', text):
        if m[1] not in schemas['PersonalGrowthSchemaV16']: continue
        # The only nested historical duplicate is V11Original.TodoSeries.
        if file.name == 'PersistenceFoundation.swift' and m[1] == 'TodoSeries': continue
        body = block(text, m.start())
        fields = []
        depth = 0
        pending = ''
        for line in body.splitlines():
            clean = line.split('//')[0].strip()
            if depth == 0:
                if clean.startswith('@Relationship'): pending = clean
                f = re.match(r'(?:(@Attribute\([^\n]*?\))\s*)?var\s+(\w+):\s*([^={]+?)(?:\s*=\s*(.*))?$', clean)
                if f:
                    fields.append(dict(name=f[2], type=f[3].strip(), unique=bool(f[1] and '.unique' in f[1]),
                                       default=f[4], relationship=pending or None))
                    pending = ''
            depth += clean.count('{') - clean.count('}')
        assert fields, m[1]
        models[m[1]] = dict(path=str(file.relative_to(ROOT)), line=text[:m.start()].count('\n')+1, fields=fields)
assert set(models) == set(schemas['PersonalGrowthSchemaV16'])
result = dict(baseline='96f72339a1a3082c43018e06d6115dd93df1df97', entities=schemas['PersonalGrowthSchemaV16'], models=models)
result['counts'] = dict(entities=len(models), fields=sum(len(m['fields']) for m in models.values()),
    unique=sum(f['unique'] for m in models.values() for f in m['fields']),
    requiredWithoutDeclarationDefault=sum(not f['type'].endswith('?') and f['default'] is None and not f['relationship'] for m in models.values() for f in m['fields']))
(DEST/'schema-inventory.json').write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n')
(DEST/'production-source-sha256.json').write_text(json.dumps(manifest, indent=2)+'\n')
print(json.dumps(result['counts']))
