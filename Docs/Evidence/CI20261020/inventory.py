import json,subprocess,datetime,pathlib,collections
root=pathlib.Path('/private/tmp/pgos-ci-contrast-20261020')
def git(*args):return subprocess.check_output(['git',*args],text=True).strip()
def cmd(*args):return subprocess.run(args,capture_output=True,text=True)
def commits(*args):return git('rev-list',*args).splitlines()
remote=[x for p in json.loads((root/'remote-branch-pages.json').read_text()) for x in p]
prs=[x for p in json.loads((root/'pr-pages.json').read_text()) for x in p]
prdata=[{k:p[k] for k in ['number','state','draft','merged_at','closed_at','html_url','merge_commit_sha']} | {'head':{'ref':p['head']['ref'],'sha':p['head']['sha']},'base':{'ref':p['base']['ref'],'sha':p['base']['sha']}} for p in prs]
locals={}
for line in git('for-each-ref','--format=%(refname:short)\t%(objectname)\t%(upstream:short)','refs/heads').splitlines():
 b,sha,up=(line+'\t').split('\t')[:3];locals[b]={'sha':sha,'upstream':up or None}
worktrees=[]
for block in git('worktree','list','--porcelain').split('\n\n'):
 d={}
 for line in block.splitlines():
  k,_,v=line.partition(' ');d[k]=v or True
 path=d.get('worktree');d['exists']=pathlib.Path(path).is_dir()
 status=cmd('git','-C',path,'status','--porcelain=v1') if d['exists'] else None
 d['statusReturnCode']=status.returncode if status else None
 d['statusError']=status.stderr.strip() if status and status.returncode else None
 d['status']=status.stdout.splitlines() if status and status.returncode==0 else None
 worktrees.append(d)
tags=git('for-each-ref','--format=%(refname:short)\t%(*objectname)\t%(objectname)','refs/tags').splitlines()
rem={x['name']:x['commit']['sha'] for x in remote}
names=sorted(set(rem)|set(locals));candidate=rem['codex/usage-remediation-20261017'];base=rem['codex/time-investment-v1'];main=rem['main']
alltips={n:(locals[n]['sha'] if n in locals else rem[n]) for n in names}
rows=[]
for name in names:
 local=locals.get(name);sha=rem.get(name) or local['sha'];lp=local['sha'] if local else None
 association=[p for p in prdata if p['head']['ref']==name]; dependents=[p for p in prdata if p['base']['ref']==name and p['state']=='open']
 upstream=local['upstream'] if local else None
 aheadbehind=None
 if upstream and cmd('git','rev-parse','--verify',upstream).returncode==0:
  a,b=map(int,git('rev-list','--left-right','--count',lp+'...'+upstream).split());aheadbehind={'ahead':a,'behind':b}
 unpushed=commits(lp,'--not',rem[name]) if lp and name in rem else (git('rev-list',lp,'--not','--remotes=origin').splitlines() if lp else [])
 rel={}
 for label,ref in [('main',main),('integrationCandidate',candidate),('actualPRBase',base)]:
  a,b=map(int,git('rev-list','--left-right','--count',sha+'...'+ref).split())
  rel[label]={'referenceSHA':ref,'branchOnlyCount':a,'referenceOnlyCount':b,'isAncestor':cmd('git','merge-base','--is-ancestor',sha,ref).returncode==0,'mergeBase':git('merge-base',sha,ref),'treeIdentical':cmd('git','diff','--quiet',sha,ref).returncode==0,'branchOnlyCommits':commits(sha,'--not',ref)}
 otherTips=[v for k,v in list(rem.items())+[(k,v['sha']) for k,v in locals.items()] if k!=name]
 unique=commits(sha,'--not',*otherTips)
 localUnique=commits(lp,'--not',*otherTips) if lp else []
 cherry=git('cherry',candidate,sha).splitlines() if not rel['integrationCandidate']['isAncestor'] else []
 docrefs=cmd('rg','-n','-F','--glob','!**/CI20261020/**','--glob','!CI_DEVICE_BRANCH_CLEANUP_20261020_BRANCH_INVENTORY_ZH.md','--',name,'Docs','DEVELOPMENT_CONTRACT.md','ci_scripts').stdout.splitlines()
 tagrefs=[];reachableTags=[]
 for t in tags:
  tag,deref,obj=t.split('\t');target=deref or obj
  if cmd('git','merge-base','--is-ancestor',sha,target).returncode==0:tagrefs.append({'tag':tag,'target':target})
  if cmd('git','merge-base','--is-ancestor',target,sha).returncode==0:reachableTags.append({'tag':tag,'target':target})
 changedPaths=git('diff','--name-only',rel['integrationCandidate']['mergeBase'],sha).splitlines()
 fileCoverage=[{'path':p,'identicalInCandidate':cmd('git','diff','--quiet',sha,candidate,'--',p).returncode==0} for p in changedPaths]
 occupied=[w for w in worktrees if w.get('branch')=='refs/heads/'+name]
 dirty=any(w['status'] for w in occupied if w['status'] is not None)
 if name=='main' or name=='codex/usage-remediation-20261017':cat='必须保留'
 elif dependents:cat='叠加链基底'
 elif dirty or unpushed:cat='含未同步/独有工作'
 elif (name not in rem and rel['integrationCandidate']['isAncestor']) or (cherry and fileCoverage and all(p['identicalInCandidate'] for p in fileCoverage)):cat='疑似重复待确认'
 elif unique:cat='含未同步/独有工作'
 elif any(p['state']=='open' for p in association):cat='必须保留'
 elif name not in rem and rel['integrationCandidate']['treeIdentical']:cat='疑似重复待确认'
 elif rel['integrationCandidate']['isAncestor']:cat='合并后候选'
 elif cherry and all(x.startswith('-') for x in cherry):cat='疑似重复待确认'
 else:cat='信息不足'
 row={'branch':name,'remoteSHA':rem.get(name),'remoteProtected':next((r['protected'] for r in remote if r['name']==name),None),'local':local,'lastCommit':json.loads(git('show','-s','--format={"date":"%cI","subject":%s}',sha)) if False else {'date':git('show','-s','--format=%cI',sha),'subject':git('show','-s','--format=%s',sha)},'upstreamAheadBehind':aheadbehind,'unpushedCommits':unpushed,'exclusiveToOtherBranchTips':unique,'localExclusiveToOtherBranchTips':localUnique,'relations':rel,'cherryAgainstCandidate':cherry,'changedPathCoverageInCandidate':fileCoverage,'secondaryUnsynchronizedOrDirty':bool(dirty or unpushed),'worktrees':occupied,'prs':association,'openDependentPRs':dependents,'tagsContainingBranchTip':tagrefs,'tagsReachableFromBranch':reachableTags,'documentReferences':docrefs,'classification':cat,'retainedReference':{'candidate':candidate,'remoteBranch':name if name in rem else None,'localBranch':name if local else None},'preconditions':'只读清点不授权删除；未来须Owner逐条批准固定SHA，重新核对ref/工作树/未推送工作/PR依赖，先保存未同步内容。'+('须先按依赖链合并所有后续开放PR至main并验证最终差异。' if dependents else '候选完整进入main且验证实际合并结果/补丁等价后方可考虑。')}
 rows.append(row)
report={'capturedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'scope':'read-only; fetch --no-prune; no deletion, retarget, tag, reset or cleanup','apiPages':{'branches':len(json.loads((root/'remote-branch-pages.json').read_text())),'prs':len(json.loads((root/'pr-pages.json').read_text()))},'remoteBranchCount':len(rem),'localBranchCount':len(locals),'unionBranchCount':len(names),'openPRCount':sum(p['state']=='open' for p in prdata),'openDraftCount':sum(p['state']=='open' and p['draft'] for p in prdata),'references':{'main':main,'candidate':candidate,'base':base,'localCheckout':git('rev-parse','HEAD')},'classificationCounts':dict(collections.Counter(r['classification'] for r in rows)),'branches':rows,'pullRequests':prdata,'worktrees':worktrees,'tags':tags}
(root/'branch-inventory.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:v for k,v in report.items() if k not in ['branches','pullRequests','worktrees','tags']},ensure_ascii=False))
