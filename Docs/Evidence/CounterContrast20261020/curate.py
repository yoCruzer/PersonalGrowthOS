from pathlib import Path
import json,hashlib,re,shutil
root=Path('/private/tmp/pgos-ci-contrast-20261020');out=Path('Docs/Evidence/CounterContrast20261020');out.mkdir(parents=True,exist_ok=True);manifest=[];samples=[]
from PIL import Image
from collections import Counter
corners=[('light2','zh-default','light-default'),('light2','contrast-zh-AX-light','light-maxAX'),('dark','contrast-zh-default-dark','dark-default'),('dark','zh-AX-dark','dark-maxAX')]
frame=r'\{\{([\d.]+), ([\d.]+)\}, \{([\d.]+), ([\d.]+)\}\}'
for folder,prefix,label in corners:
 directory=root/(folder+'-attachments');tests=json.loads((directory/'manifest.json').read_text());attachments=[a for t in tests for a in t['attachments']]
 for suffix,key in [('Today-daily-zero','Today-daily-zero'),('Today-每周锻炼几次-one','Today-weekly-one'),('Growth-每周锻炼几次-zero','Growth-weekly-zero'),('Growth-每周锻炼几次-one','Growth-weekly-one'),('Detail-每周锻炼几次-one','Detail-weekly-one'),('Growth-这是一个真正很长需要合理换行的每周习惯名称-full-title','long-name')]:
  match=[a for a in attachments if a['suggestedHumanReadableName'].startswith(prefix+'-'+suffix+'_') and a['exportedFileName'].endswith('.png')]
  if not match:continue
  a=match[0];src=directory/a['exportedFileName'];target=out/(label+'-'+key+'.png');shutil.copyfile(src,target)
  ax=next(a for a in attachments if a['suggestedHumanReadableName'].startswith(prefix+'-'+suffix+'-AX_'))
  axtext=(directory/ax['exportedFileName']).read_text();(out/(label+'-'+key+'-AX.txt')).write_text(axtext)
  manifest.append(dict(file=target.name,source=str(src),attachment=a,xcresult=str(root/(folder+'.xcresult')),sha256=hashlib.sha256(src.read_bytes()).hexdigest(),kind='original XCUIApplication screenshot; direct byte copy'))
  if key in ['Growth-weekly-zero','Growth-weekly-one']:
   im=Image.open(src).convert('RGB');window=re.search(r'Window \(Main\).*?'+frame,axtext);ww,wh=float(window.group(3)),float(window.group(4));sx,sy=im.width/ww,im.height/wh
   for icon in ['increase','decrease']:
    line=next(z for z in axtext.splitlines() if "identifier: 'habit-overview-每周锻炼几次-counter-"+icon+"'" in z)
    m=re.search(frame,line);x,y,w,h=map(float,m.groups());roi=[int(x*sx),int(y*sy),int((x+w)*sx),int((y+h)*sy)]
    enabled='Disabled' not in line
    colors=Counter(im.crop(roi).get_flattened_data());fg=(23,79,120) if label.startswith('light') else (213,234,254);bg=(230,236,242) if label.startswith('light') else (40,55,68)
    if enabled:
     point=(int((x+w/2)*sx),int((y+h/2)*sy));fg=im.getpixel(point)
     assert colors[fg]>20,(target,roi,point,colors.most_common(6));assert colors[bg]>100
     bgpoint=next((px,py) for py in range(roi[1],roi[3]) for px in range(roi[0],roi[2]) if im.getpixel((px,py))==bg)
     samples.append(dict(file=target.name,icon=icon,state='enabled',appearance=label,roi=roi,foreground=list(fg),background=list(bg),foregroundPixel=list(point),backgroundPixel=list(bgpoint),solidForegroundPixels=colors[fg],solidBackgroundPixels=colors[bg],actualAXFrame=[x,y,w,h]))
   print(label,key,im.size)
src=root/'light-first-attachments/71F75453-EB78-4D9E-9182-A51CAD88FC78.png';target=out/'real-App-settings-material.png';shutil.copyfile(src,target);manifest.append(dict(file=target.name,source=str(src),sha256=hashlib.sha256(src.read_bytes()).hexdigest(),xcresult=str(root/'light.xcresult'),kind='original production App screenshot; no product settings fix'))
(out/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n');(out/'samples.json').write_text(json.dumps(samples,ensure_ascii=False,indent=2)+'\n')
print('original PNG',len(manifest),'enabled samples',len(samples))
