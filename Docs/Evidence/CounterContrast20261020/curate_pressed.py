from pathlib import Path
import json,re,hashlib,shutil
from PIL import Image
from collections import Counter
root=Path('/private/tmp/pgos-ci-contrast-20261020');out=Path('Docs/Evidence/CounterContrast20261020');manifest=json.loads((out/'manifest.json').read_text());samples=json.loads((out/'samples.json').read_text());frame=r'\{\{([\d.]+), ([\d.]+)\}, \{([\d.]+), ([\d.]+)\}\}'
for style in ['light','dark']:
 folder=root/('press2-'+style+'-attachments');tests=json.loads((folder/'manifest.json').read_text());attachments=[a for t in tests for a in t['attachments']]
 captures=json.loads((root/('contrast-press2-'+style+'-press-png.json')).read_text())
 for i,(size,icon) in enumerate([('default','increase'),('default','decrease'),('maxAX','increase'),('maxAX','decrease')],1):
  name='contrast-press-'+size+('-zero' if icon=='increase' else '-one')+'-AX_'
  a=next(a for a in attachments if a['suggestedHumanReadableName'].startswith(name));text=(folder/a['exportedFileName']).read_text();w=re.search(r'Window \(Main\).*?'+frame,text);ww,wh=float(w.group(3)),float(w.group(4))
  line=next(z for z in text.splitlines() if "identifier: 'today-habit-每天喝水几次-"+icon+"'" in z);x,y,w,h=map(float,re.search(frame,line).groups())
  expected=(16,59,93) if style=='light' else (255,255,255);bg=(230,236,242) if style=='light' else (40,55,68)
  options=[]
  for record in captures:
   p=Path(record['path'])
   if not p.name.startswith(f'press-{i:02}-'):continue
   im=Image.open(p).convert('RGB');sx,sy=im.width/ww,im.height/wh;point=(int((x+w/2)*sx),int((y+h/2)*sy));color=im.getpixel(point);delta=sum((a-b)**2 for a,b in zip(color,expected));options.append((delta,p,record,color,point,im,sx,sy))
  delta,src,record,fg,point,im,sx,sy=min(options,key=lambda t:t[0]);assert delta<20,(style,size,icon,[(x[0],x[3]) for x in options])
  roi=[int(x*sx),int(y*sy),int((x+w)*sx),int((y+h)*sy)];colors=Counter(im.crop(roi).get_flattened_data());assert colors[fg]>20;assert colors[bg]>100
  bgpoint=next((px,py) for py in range(roi[1],roi[3]) for px in range(roi[0],roi[2]) if im.getpixel((px,py))==bg)
  target=out/(style+'-'+size+'-pressed-'+icon+'.png');shutil.copyfile(src,target)
  (out/(style+'-'+size+'-pressed-'+icon+'-AX.txt')).write_text(text)
  manifest.append(dict(file=target.name,source=str(src),sha256=hashlib.sha256(src.read_bytes()).hexdigest(),kind='original simctl framebuffer PNG captured during real production button hold; no video frame conversion',capture=record,xcresult=str(root/('contrast-press2-'+style+'.xcresult'))))
  samples.append(dict(file=target.name,icon=icon,state='pressed enabled',appearance=style+'-'+size,roi=roi,foreground=list(fg),background=list(bg),foregroundPixel=list(point),backgroundPixel=list(bgpoint),solidForegroundPixels=colors[fg],solidBackgroundPixels=colors[bg],actualAXFrame=[x,y,w,h]))
  print(target.name,fg,colors[fg])
(out/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n');(out/'samples.json').write_text(json.dumps(samples,ensure_ascii=False,indent=2)+'\n')
