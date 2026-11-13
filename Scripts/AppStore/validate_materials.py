#!/usr/bin/env python3
"""Validate checked-in release fields, policy parity, manifests and static links."""
from pathlib import Path
from html.parser import HTMLParser
import json, plistlib, hashlib
root=Path(__file__).resolve().parents[2]
report={'metadata':{},'manifests':{},'pages':{},'policies':{}}
for path in sorted((root/'Release/AppStore/Metadata').glob('*.json')):
    data=json.loads(path.read_text())
    counts={}
    for key,limit in [('name',30),('subtitle',30),('promotionalText',170),('description',4000)]:
        counts[key]=len(data[key]);assert 0<counts[key]<=limit,(path,key,counts[key])
    for key,limit in [('keywords',100),('reviewNotes',4000)]:
        counts[key+'Bytes']=len(data[key].encode());assert 0<counts[key+'Bytes']<=limit,(path,key)
    report['metadata'][path.stem]=counts
for target in ['PersonalGrowthOS','ShareExtension','ImportantDaysWidget']:
    p=root/target/'PrivacyInfo.xcprivacy';d=plistlib.loads(p.read_bytes())
    assert d['NSPrivacyTracking'] is False and not d['NSPrivacyCollectedDataTypes']
    report['manifests'][target]=d['NSPrivacyAccessedAPITypes']
class Links(HTMLParser):
    def __init__(self):super().__init__();self.links=[];self.text=[]
    def handle_starttag(self,tag,attrs):
        for k,v in attrs:
            if k in ('href','src'):self.links.append(v)
        assert tag not in ('script','iframe','form'),tag
    def handle_data(self,s):self.text.append(s)
site=root/'Release/AppStore/Website/dist'
for path in sorted(site.glob('*.html')):
    parser=Links();parser.feed(path.read_text())
    for link in parser.links:
        if not link.startswith(('https://','mailto:','#')):assert (site/link.split('#')[0]).is_file(),(path,link)
    report['pages'][path.name]={'localLinksValid':True,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    if path.stem.startswith(('privacy-','support-')):
        text=(root/'PersonalGrowthOS/ReleaseInformation'/(path.stem+'.txt')).read_text()
        assert all(line in ''.join(parser.text) for line in text.splitlines() if line.strip()),path
        report['policies'][path.stem]={'offlineAndWebTextEqual':True,'sha256':hashlib.sha256(text.encode()).hexdigest()}
print(json.dumps(report,ensure_ascii=False,indent=2))
