#!/usr/bin/env python3
"""Copy original XCTest PNGs without alteration; verify Apple's dimensions/alpha."""
import hashlib,json,re,shutil,struct,sys
from pathlib import Path
root=Path(__file__).resolve().parents[2]
export=Path(sys.argv[1]);dest=root/'Release/AppStore/Screenshots';out=[]
for case in json.loads((export/'manifest.json').read_text()):
    for a in case['attachments']:
        match=re.match(r'AppStore-(zh-Hans|en-US)-(0[1-5])_',a['suggestedHumanReadableName'])
        if not match:continue
        lang,index=match.groups();p=export/a['exportedFileName'];data=p.read_bytes()
        assert data[:8]==b'\x89PNG\r\n\x1a\n'
        width,height,depth,color=struct.unpack('>IIBB',data[16:26])
        assert (width,height)==(1206,2622),(p,width,height)
        assert color==2,(p,'Must be RGB with no alpha channel',color)
        q=dest/lang/(index+'-'+['today','timeline','capture','growth','library'][int(index)-1]+'.png');q.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,q)
        out.append({'file':str(q.relative_to(root)),'dimensions':[width,height],'pngColorType':color,'sha256':hashlib.sha256(data).hexdigest(),'attachment':a['suggestedHumanReadableName']})
assert len(out)==10,len(out)
(dest/'manifest.json').write_text(json.dumps(sorted(out,key=lambda x:x['file']),ensure_ascii=False,indent=2)+'\n')
print('10 original RGB PNGs exported, 1206×2622, two localizations, no image alteration.')
