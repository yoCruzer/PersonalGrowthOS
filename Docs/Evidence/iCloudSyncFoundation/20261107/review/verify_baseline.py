"""Read synthetic frozen files; open SQLite only after copying Store to a fresh temp root."""
from pathlib import Path
import hashlib, json, sqlite3, tempfile, shutil, zipfile, plistlib, uuid

base = Path(__file__).resolve().parent.parent
root = base / 'baseline-v16'
expected_hashes = json.loads((base / 'baseline-v16-sha256.json').read_text())
def hashes():
    return {str(p.relative_to(root)): {'bytes': p.stat().st_size, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
            for p in sorted(root.rglob('*')) if p.is_file()}
before = hashes()
assert before == expected_hashes
assert (root/'SOURCE.txt').read_text().startswith('96f72339a1a3082c43018e06d6115dd93df1df97\n')
expected = json.loads((root/'expected-transfer.json').read_bytes())
with zipfile.ZipFile(root/'expected-v12.zip') as package:
    assert package.testzip() is None
    manifest = json.loads(package.read('manifest.json'))
    assert manifest['packageSchemaVersion'] == 12
    data = package.read(manifest['dataFile']['path'])
    assert len(data) == manifest['dataFile']['byteCount']
    assert hashlib.sha256(data).hexdigest() == manifest['dataFile']['sha256']
    transfer = json.loads(data)
    assert manifest['objectCounts'] == {k:len(v) for k,v in transfer.items()}
    assert len(transfer['captureReceipts']) == 2
    assert {x['id'] for x in transfer['captureReceipts']} == {'AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA', expected['entries'][0]['id']}
    media = manifest['mediaFiles']
    assert len(media) == 1
    for entry in media:
        raw = package.read(entry['path'])
        metadata = next(x for x in expected['images'] if x['id'] == entry['imageID'])
        assert raw == (root / metadata['relativePath']).read_bytes()
        assert len(raw) == entry['byteCount'] == metadata['byteCount']
        assert hashlib.sha256(raw).hexdigest() == entry['sha256'] == metadata['checksum']
    assert set(package.namelist()) == {'manifest.json', manifest['dataFile']['path'], *[x['path'] for x in media]}

# Legacy Date-typed fields use Unix seconds in export; newer transfer structs encode
# reference-date Double fields themselves. Normalize only the explicit Date locations.
legacy_dates = {
 'entries':['createdAt','occurredAt','updatedAt'], 'entryPins':['pinnedAt'],
 'habits':['createdAt','updatedAt'], 'links':['createdAt'],
 'habitLifecycleEvents':['createdAt','occurredAt'], 'habitLogs':['createdAt','occurredAt'],
 'goals':['createdAt','updatedAt'], 'goalEvents':['createdAt','occurredAt'],
 'weeklyReviews':['createdAt','updatedAt','periodStart','periodEnd'],
 'tags':['createdAt','updatedAt'], 'entryFollowUps':['createdAt','updatedAt'],
 'images':['createdAt','updatedAt'], 'weightRecords':['createdAt','updatedAt','recordedAt'],
 'habitPlanRevisions':['createdAt']}
for group, keys in legacy_dates.items():
    for item in expected[group]:
        for key in keys:
            if key in item and item[key] is not None: item[key] += 978307200
for item in expected['entrySources']: item['source']['capturedAt'] += 978307200
assert transfer == expected
confirmed = [x for x in transfer['netWorthSnapshots'] if x['confirmed']]
assert len(confirmed) == 1
asset = sum(x['cents'] for x in confirmed[0]['items'] if x['side']=='asset')
liability = sum(x['cents'] for x in confirmed[0]['items'] if x['side']=='liability')
assert asset == 1234567 and liability == 23456 and asset-liability == 1211111
assert any(x.get('inputText') == 'unfinished..input' for s in transfer['netWorthSnapshots'] if not s['confirmed'] for x in s['items'])

scratch = Path(tempfile.mkdtemp(prefix='PGOS-V16Independent-', dir='/private/tmp'))
shutil.copytree(root/'Store', scratch/'Store')
connection = sqlite3.connect(scratch/'Store/PersonalGrowthOS.sqlite')
try:
    schema = plistlib.loads(connection.execute('SELECT Z_PLIST FROM Z_METADATA').fetchone()[0])
    assert schema['NSStoreModelVersionIdentifiers'] == ['16.0.0']
    receipt_ids = {str(uuid.UUID(bytes=row[0])).upper() for row in connection.execute('SELECT ZID FROM ZCAPTUREIMPORTRECEIPT')}
    assert receipt_ids == {x['id'] for x in transfer['captureReceipts']}
    assert connection.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
finally: connection.close()
assert hashes() == before
result = {'status':'PASS','schema':'16.0.0','backupVersion':12,'frozenFiles':len(before),
          'captureReceipts':2,'originalImages':1,'netMinor':1211111,
          'fullTransferEquality':'PASS after explicit Date epoch normalization',
          'sqliteIntegrity':'ok','frozenHashUnchanged':True,'openedOnlyCopy':str(scratch),
          'limits':['Representative synthetic fixture, not all 39 entities', 'No Sync schema migration or cloud operation']}
print(json.dumps(result,indent=2))
