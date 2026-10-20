import sys,time,pathlib,subprocess,json
name=sys.argv[1];root=pathlib.Path('/private/tmp/pgos-ci-contrast-20261020');log=pathlib.Path('/private/tmp/pgos-ui-20261020-evidence')/(name+'.log');end=log.with_suffix('.record.json');target=root/(name+'-press-png');target.mkdir(exist_ok=True);offset=0;n=0;records=[];started=time.monotonic()
while time.monotonic()-started<300 and not end.exists():
 if log.exists():
  with log.open() as f:f.seek(offset);lines=f.readlines();offset=f.tell()
  for line in lines:
   if ' Button for 2.0 seconds' in line:
    n+=1
    for i in range(1):
     time.sleep(.18)
     path=target/f'press-{n:02}-{i}.png';now=time.time()
     p=subprocess.run(['xcrun','simctl','io','834F841F-D0EA-4240-8EF1-3008ADEEEC2A','screenshot',str(path)],capture_output=True)
     records.append({'event':line.strip(),'epoch':now,'path':str(path),'exit':p.returncode})
 time.sleep(.03)
(root/(name+'-press-png.json')).write_text(json.dumps(records,ensure_ascii=False,indent=2))
print('native screenshot captures',len(records))
