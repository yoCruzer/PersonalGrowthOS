import concurrent.futures,hashlib,json,pathlib,subprocess,zipfile,sys
repo='yoCruzer/PersonalGrowthOS'
root=pathlib.Path('/private/tmp/PGOS-ICloud-Reliability-CI');root.mkdir(exist_ok=True)
def api(path): return json.loads(subprocess.check_output(['gh','api',path]))
def fetch(run):
 info=api(f'repos/{repo}/actions/runs/{run}')
 assert info['head_sha']=='59104222b0ca654ca5cffa8faed3e2f208e91b2e'
 assert info['conclusion']=='success', (run,info['status'],info['conclusion'])
 (root/f'run-{run}.json').write_text(json.dumps(info,indent=2)+'\n')
 items=api(f'repos/{repo}/actions/runs/{run}/artifacts')['artifacts']
 (root/f'artifacts-{run}.json').write_text(json.dumps(items,indent=2)+'\n')
 return items
def download(item):
 archive=root/(item['name']+'.zip')
 if not archive.exists() or 'sha256:'+hashlib.sha256(archive.read_bytes()).hexdigest()!=item['digest']:
  with archive.open('wb') as output:
   subprocess.run(['gh','api',f"repos/{repo}/actions/artifacts/{item['id']}/zip"],stdout=output,check=True)
 digest=hashlib.sha256(archive.read_bytes()).hexdigest()
 assert item['digest']=='sha256:'+digest,(item['name'],item['digest'],digest)
 with zipfile.ZipFile(archive) as z:
  assert z.testzip() is None
  for member in z.infolist():
   p=pathlib.PurePosixPath(member.filename)
   assert not p.is_absolute() and '..' not in p.parts
   assert member.external_attr>>16 & 0o170000 != 0o120000
  target=root/item['name'];target.mkdir(exist_ok=True);z.extractall(target)
 return {'name':item['name'],'artifactID':item['id'],'zipSHA256':digest,'officialDigest':'PASS','zipCRC':'PASS'}
if __name__=='__main__':
 items=[]
 for run in map(int,sys.argv[1:] or [42630679905,42630679938]):items+=fetch(run)
 with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:results=list(pool.map(download,items))
 (root/('zip-verification-'+('-'.join(sys.argv[1:]) or 'all')+'.json')).write_text(json.dumps(results,indent=2)+'\n')
 print(json.dumps(results,indent=2))
