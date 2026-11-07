#!/usr/bin/env python3
"""Verify private, paired fault-window evidence. Never grants full G1 acceptance.

Input: prepared plans plus results/STAGE/report.json (or boundary.json for
intentional exits). Copy iPhone originals into their matching stage directory.
"""
import argparse
import base64
import hashlib
import json
import re
from pathlib import Path


def canonical(v):
    return json.dumps(v, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()


def digest(v):
    return hashlib.sha256(v).hexdigest()


def require(value, message):
    if not value:
        raise ValueError(message)


def read(path):
    require(not path.is_symlink() and path.is_file(), 'Expected regular evidence file')
    data = path.read_bytes()
    require(len(data) <= 32000000, 'Evidence exceeds bound')
    return json.loads(data)


def snapshot(v):
    return v['snapshot']


def facts(v):
    envelopes = snapshot(v)['envelopes']
    require(len({e['object'] for e in envelopes}) == len(envelopes), 'Duplicate object envelope')
    mutations = [m for e in envelopes for m in e['mutations']]
    require(len({m['id'] for m in mutations}) == len(mutations), 'Duplicate mutation')
    require(all(m['object'] == e['object'] for e in envelopes for m in e['mutations']), 'Object mismatch')
    return {m['id']: m for m in mutations}


def complete(v):
    require(v.get('snapshotComplete') is True and v.get('unavailableImages') == [], 'Incomplete snapshot')
    for e in snapshot(v)['envelopes']:
        for m in e['mutations']:
            if 'imageHash' in m:
                raw = base64.b64decode(snapshot(v)['images'][m['imageHash']], validate=True)
                require(len(raw) == m['imageBytes'] and digest(raw) == m['imageHash'], 'Original mismatch')


def verify(plans, results):
    manifest = read(plans/'manifest.json')
    dependency = [s for s in manifest if s['name'].startswith('00-')]
    stages = [s for s in manifest if not s['name'].startswith('00-')]
    require(len(dependency)==3, 'Missing dependency batch')
    require(len(stages) == 24 and len({s['name'] for s in stages}) == 24, 'Incomplete suite')
    truth = {}
    for stage in stages:
        for command in stage['plan']['commands']:
            if 'mutation' in command and command['action'] != 'crashBeforeSave':
                mutation = command['mutation']
                require(mutation['id'] not in truth, 'Duplicate planned mutation')
                truth[mutation['id']] = mutation
    def check_snapshot(value):
        actual = facts(value)
        require(all(key in truth and mutation == truth[key] for key,mutation in actual.items()), 'Content differs from fixed plan truth')
        declared = {m['imageHash']:m['imageBytes'] for m in actual.values() if 'imageHash' in m}
        images = snapshot(value)['images']
        require(set(images).issubset(declared), 'Unexpected image')
        for hash_, encoded in images.items():
            raw=base64.b64decode(encoded,validate=True)
            require(digest(raw)==hash_ and len(raw)==declared[hash_], 'Image digest/length mismatch')
        missing=sorted(set(declared)-set(images))
        require(value.get('unavailableImages')==missing, 'Missing-image declaration mismatch')
        if 'snapshotComplete' in value:
            require(value['snapshotComplete'] is (not missing), 'False complete snapshot')
        if 'projections' in value:
            projections=value['projections']
            require(set(projections)=={m['object'] for m in actual.values()}, 'Projection objects mismatch')
            for object_, projection in projections.items():
                mutations=[m for m in actual.values() if m['object']==object_]
                parents={p for m in mutations for p in m['parents']}
                heads=sorted(m['id'] for m in mutations if m['id'] not in parents)
                require(len(heads)==1, 'Unexpected fault-suite graph shape')
                unavailable=any(m.get('imageHash') in missing for m in mutations)
                require(projection.get('complete') is (not unavailable), 'Incorrect projection completeness')
                require(projection['candidates']==heads and projection['state']==('missing_image' if unavailable else 'ready'), 'Projection state mismatch')
                require(projection.get('preview')==(None if unavailable else actual[heads[0]]), 'Projection preview mismatch')
    def exact_through(value, number):
        expected = {}
        for stage in stages:
            if int(stage['name'][:2]) > number or stage['plan']['dataset'] != stages[0]['plan']['dataset']:
                continue
            for command in stage['plan']['commands']:
                if command['action'] in ('save','crashAfterSave','editDuringSend'):
                    mutation = command['mutation']; expected[mutation['id']] = mutation
        require(facts(value) == expected, 'Missing or extra facts against independent fixed plan truth')
    reports, boundaries = {}, {}
    source_a = None
    def check_observation(value, plan, command, nonce=None):
        nonlocal source_a
        require(value['commandID']==command['id'] and value['commandDigest']==digest(canonical(command)) and value['planID']==plan['id'], 'Fault command identity mismatch')
        require(value['dataset']==plan['dataset'] and value['runID']==plan['runID'], 'Fault context mismatch')
        require(re.fullmatch('[0-9a-f]{64}',value.get('sourceAccountHash','')) and isinstance(value.get('processNonce'),str) and bool(value['processNonce']) and type(value.get('processID')) is int and value['processID'] > 0, 'Fault identity absent')
        if source_a is None: source_a=value['sourceAccountHash']
        require(value['sourceAccountHash']==source_a, 'Fault account changed')
        if nonce is not None: require(value['processNonce']==nonce, 'Fault from another process')
        provenance = 'actualCloudKitCallback' if command['action'] in ('crashOnFetch','crashOnState','crashWithImageLease','editDuringSend','restoreIsolation') else 'localTransactionOrFileFault'
        require(value['provenance']==provenance, 'Fault provenance mismatch')
        check_snapshot(value)

    account_a = None
    for stage in stages:
        name, plan = stage['name'], stage['plan']
        raw = (plans/name/'SyncLab-Probe-Plan.json').read_bytes()
        require(json.loads(raw) == plan, 'Plan changed')
        if stage.get('expectedExit') is not None:
            value = read(results/name/'boundary.json')
            command = plan['commands'][-1]
            point = {73:'beforeSaveCommit',74:'afterSaveCommit',75:'afterFetchedInstall',76:'afterFetchedState',77:'assetLeaseBeforeACK'}[stage['expectedExit']]
            require(value['point'] == point and value['commandID'] == command['id'] and value['commandDigest'] == digest(canonical(command)), 'Wrong crash boundary')
            require(value['planID'] == plan['id'] and value['runID'] == plan['runID'] and value['dataset'] == plan['dataset'], 'Wrong boundary identity')
            if stage['expectedExit'] in (75,76,77):
                require(value['provenance'] == 'actualCloudKitCallback', 'Local seam cannot prove real cloud boundary')
            check_observation(value,plan,command)
            boundaries[name] = value
            continue
        report = read(results/name/'report.json')
        require(report['planID'] == plan['id'] and report['runID'] == plan['runID'] and report['dataset'] == plan['dataset'] and report['planDigest'] == digest(raw), 'Wrong report identity')
        require(report['completedAllCommands'] is True and len(report['results']) == len(plan['commands']), 'Incomplete command execution')
        require(len({v.get('processNonce') for v in report['results']})==1, 'Plan mixed process lifetimes')
        require(len({v.get('accountFingerprint') for v in report['results']})==1, 'Plan mixed accounts')
        for command, value in zip(plan['commands'], report['results']):
            require(value['id'] == command['id'] and value['commandDigest'] == digest(canonical(command)) and value['planID'] == plan['id'], 'Wrong command evidence')
            require(value['status'] == 'PASS' and value['halted'] is False and value.get('errorCode') is None, 'Command failed')
            require(value['dataset'] == plan['dataset'] and value['runID'] == plan['runID'], 'Command context mismatch')
            require(value['platform'] == stage['device'], 'Wrong device')
            require(isinstance(value.get('processNonce'),str) and bool(value['processNonce']) and type(value.get('processID')) is int and value['processID']>0, 'Missing process identity')
            check_snapshot(value)
            if command['action']=='openCached': require(value['accountSource']=='cachedPartitionNotCurrentAccount', 'Cache mislabelled live')
            if command['action']=='connect': require(value['accountSource']=='liveCloudKit', 'Connect identity unverified')
            observations=value.get('faultObservations',[])
            require(len({o['point'] for o in observations})==len(observations), 'Duplicate fault point')
            for observation in observations:
                source_plan, source_command, nonce = plan, command, value['processNonce']
                if command['action']=='inspectFaults':
                    source = command['faultSource']
                    source_plan = next(s['plan'] for s in stages if s['plan']['id']==source['planID'])
                    source_command = next(c for c in source_plan['commands'] if c['id']==source['commandID'])
                    nonce=None
                    require(source['commandDigest']==digest(canonical(source_command)), 'Wrong inspect source')
                check_observation(observation,source_plan,source_command,nonce)
            fp = value['accountFingerprint']
            require(isinstance(fp,str) and re.fullmatch('[0-9a-f]{64}',fp), 'Missing account fingerprint')
            if account_a is None:
                account_a = fp
            require((fp != account_a) if name.startswith('22-') else (fp == account_a), 'Account isolation mismatch')
        reports[name] = report['results']
    def r(prefix):
        return reports[next(n for n in reports if n.startswith(prefix+'-'))]
    def b(prefix):
        return boundaries[next(n for n in boundaries if n.startswith(prefix+'-'))]
    for crash, recovery in [('03','04'),('06','07'),('08','09'),('10','11'),('13','14')]:
        boundary = b(crash); values = r(recovery)
        exact_through(boundary,int(crash))
        require(values[0]['processNonce'] != boundary['processNonce'], 'Recovery reused old process')
        observed = values[1]['faultObservations']
        require(boundary in observed and all(o['processNonce']==boundary['processNonce'] for o in observed), 'Recovery does not retain exact process boundary')
        if crash=='06': require(isinstance(boundary.get('checkpointHash'),str) and re.fullmatch('[0-9a-f]{64}',boundary['checkpointHash']), 'No persisted SDK state hash')
        if crash=='13':
            image=truth['probe-lease-image']
            expected={'image-'+image['imageHash']:digest(canonical(image['imageBytes']))}
            require({o['point'] for o in observed}=={'assetBatchPrepared','assetLeaseBeforeACK'} and all(o['recordDigests']==expected for o in observed),'Asset lease record proof absent')
        require(snapshot(values[2]) == snapshot(boundary), 'Local content changed across crash')
        require(values[2]['checkpointHash'] == boundary.get('checkpointHash') if 'checkpointHash' in values[2] else boundary.get('checkpointHash') is None, 'Checkpoint changed before reconnect')
        if crash != '08':
            require(values[2]['pendingKeys'] == boundary['pendingKeys'], 'Outbox changed across crash')
    require('probe-transaction-08' not in facts(r('09')[-1]), 'Uncommitted fact survived')
    require('probe-transaction-10' in facts(r('11')[-1]), 'Committed fact lost')
    inflight = next(v for v in r('12') if v['id'] == 'probe-f12-edit')['faultObservations']
    by_point = {v['point']:v for v in inflight}
    require(set(by_point) == {'oldBatchPrepared','newEditBeforeACK','oldACKBeforeCommit','newVersionStillPending'}, 'Missing in-flight phases')
    require(all(v['provenance'] == 'actualCloudKitCallback' for v in inflight), 'In-flight local seam')
    require('object-probe-inflight-old' in by_point['newVersionStillPending']['pendingKeys'], 'New version lost at old ACK')
    old = truth['probe-inflight-old']
    old_payload = {'version':1,'object':old['object'],'mutations':[old]}
    expected_digests={'object-probe-inflight-old':digest(canonical(old_payload))}
    require(by_point['oldBatchPrepared']['recordDigests'] == by_point['oldACKBeforeCommit']['recordDigests'] == expected_digests, 'ACK did not match fixed old batch')
    for point in ['newEditBeforeACK','oldACKBeforeCommit','newVersionStillPending']:
        exact_through(by_point[point],12)
        require(facts(by_point[point]).get('probe-inflight-new')==truth['probe-inflight-new'], 'New edit absent before/at old ACK')
    for mac, phone in [('14','15'),('18','17'),('23','24')]:
        left,right=r(mac)[-1],r(phone)[-1]
        complete(left);complete(right)
        exact_through(left,int(mac));exact_through(right,int(mac))
        require(snapshot(left)==snapshot(right) and left['pendingKeys']==[] and right['pendingKeys']==[], 'Paired cloud convergence failed')
    image_result=r('15')[-1]
    image_points={v['point']:v for v in image_result.get('faultObservations',[])}
    expected_image_points={'imageBaseline-0','imageMissing-0','imageMissingRepaired-0','imageTruncated-0','imageTruncatedRepaired-0'}
    require(set(image_points)==expected_image_points,'Image fault phases absent')
    image_hash=truth['probe-lease-image']['imageHash']
    for point,value in image_points.items():
        exact_through(value,15)
        require(value['unavailableImages']==([image_hash] if point in ('imageMissing-0','imageTruncated-0') else []),'Image fault not observed or repaired')
    offline = r('16')[-1]
    require(offline['accountSource']=='cachedPartitionNotCurrentAccount' and offline['events']==[], 'Offline plan used a live engine')
    require('object-probe-phone-offline' in offline['pendingKeys'] and 'probe-phone-offline' in facts(r('18')[-1]), 'Offline record not received')
    # Physical network-off is a separately recorded Owner action, never inferred here.
    restore=r('20')[-1]
    require('EXPECTED_RESTORE_FENCE_OBSERVED' in restore['events'] and snapshot(restore)['envelopes']==[], 'Old restore receiver accepted content')
    restore_points={v['point']:v for v in restore['faultObservations']}
    require(set(restore_points)=={'restoreTargetGated','oldReceiverFencedBeforeInstall','restoreGateSurvivedReopen'},'Restore phases absent')
    for point in ['restoreTargetGated','restoreGateSurvivedReopen']:
        value=restore_points[point]
        require(facts(value)=={'probe-restore-target':truth['probe-restore-target']} and value.get('checkpointHash') is None and value.get('networkStopped') is True,'Restore target missing or ungated')
    require(facts(restore_points['oldReceiverFencedBeforeInstall'])=={} and restore_points['oldReceiverFencedBeforeInstall'].get('networkStopped') is True,'Old receiver not fenced')
    account_change=r('21')[-2]
    require('EXPECTED_ACCOUNT_FENCE_OBSERVED' in account_change['events'] and 'ACCOUNT_CHANGED_REOPEN_REQUIRED' in account_change['events'], 'Actual account event absent')
    account_points={v['point']:v for v in account_change.get('faultObservations',[])}
    require(set(account_points)=={'beforeAccountChange','accountChangeFenced'}, 'Account-change phases absent')
    for point,value in account_points.items():
        exact_through(value,21)
        require('object-probe-account-a-pending' in value['pendingKeys'],'A queue lost at account boundary')
    require(account_points['accountChangeFenced'].get('networkStopped') is True,'Account change did not fence receiver')
    require(snapshot(r('22')[2])['envelopes']==[] and r('22')[2]['pendingKeys']==[], 'A facts leaked into B')
    require('object-probe-account-a-pending' in r('23')[1]['pendingKeys'], 'A queue lost during account switch')
    require('probe-account-a-pending' in facts(r('24')[-1]), 'A record not received after return')
    recovery = verify_dependencies(dependency,plans,results,account_a)
    summary = {'status':'PASS', 'scope':'Fixed fault-window evidence only; not full G1 or Production acceptance',
               'physicalNetworkOff':'REQUIRES_OWNER_ACTION_RECORD', 'stages':27}
    if recovery is not None:
        summary['dependencySeedRecovery'] = recovery
    return summary


def dependency_report(plan, raw, report, account, device, seed_failure=False):
    """Validate one original report; only the exact seed CK_4 stop has an exception."""
    require(report['planID']==plan['id'] and report['planDigest']==digest(raw) and report['dataset']==plan['dataset'] and report['runID']==plan['runID'], 'Dependency identity')
    rows=report['results']
    if seed_failure:
        require([c['action'] for c in plan['commands']]==['connect']+['save']*12+['sync','sync','snapshot'], 'Unexpected failed seed plan')
        require(report['completedAllCommands'] is False and report.get('errorCode')=='CK_4' and len(rows)==14, 'Unexpected seed failure boundary')
    else:
        require(report['completedAllCommands'] is True and len(rows)==len(plan['commands']), 'Dependency incomplete')
    require(len({v.get('processNonce') for v in rows})==1 and all(isinstance(v.get('processNonce'),str) and bool(v['processNonce']) and type(v.get('processID')) is int and v['processID']>0 for v in rows),'Dependency process identity')
    for index,(command,value) in enumerate(zip(plan['commands'],rows)):
        require(value.get('planID')==plan['id'] and value.get('dataset')==plan['dataset'] and value.get('runID')==plan['runID'],'Dependency nested context')
        if command['action']=='connect': require(value.get('accountSource')=='liveCloudKit','Dependency connect unverified')
        require(value['commandDigest']==digest(canonical(command)) and value['id']==command['id'], 'Dependency command identity')
        if seed_failure and index==13:
            require(value['status']=='FAIL' and value['halted'] is False and value.get('errorCode')=='CK_4', 'Seed did not stop on CK_4 sync')
        else:
            require(value['status']=='PASS' and value['halted'] is False and value.get('errorCode') is None, 'Dependency command failed')
        require(value['accountFingerprint']==account and value['platform']==device, 'Dependency account/device mismatch')
    return rows


def dependency_seed_recovery(stage, original, plans, results, account):
    """Read-only supplement; never replaces the failed seed report or its writes."""
    name='00-mac-dependency-recover'
    raw=(plans/name/'SyncLab-Probe-Plan.json').read_bytes()
    plan=json.loads(raw)
    expected={'version':1, 'id':'probe-r7-dependency-recover-001',
              'dataset':stage['plan']['dataset'], 'runID':stage['plan']['runID'],
              'commands':[{'id':'probe-r7-dependency-recover-'+suffix,'action':action}
                          for suffix,action in [('connect','connect'),('sync','sync'),('drain','sync'),('snapshot','snapshot')]]}
    require(plan==expected, 'Recovery is not the fixed read-only seed supplement')
    require(plan['id']!=stage['plan']['id'] and not ({c['id'] for c in plan['commands']} & {c['id'] for c in stage['plan']['commands']}), 'Recovery reused original identities')
    report=read(results/name/'report.json')
    require(report.get('errorCode') is None, 'Recovery report error')
    recovered=dependency_report(plan,raw,report,account,'macOS')
    require(recovered[0]['processNonce']!=original[0]['processNonce'], 'Seed recovery reused original process')
    truth={}
    for command,value in zip(stage['plan']['commands'][:13],original[:13]):
        if command['action']=='save':
            mutation=command['mutation'];require(mutation['id'] not in truth,'Duplicate seed mutation')
            truth[mutation['id']]=mutation
        require(facts(value)==truth and snapshot(value)['images']=={}, 'Original seed prefix content changed')
        complete(value)
    for value in recovered:
        require(facts(value)==truth and snapshot(value)['images']=={}, 'Recovery lost or added seed facts')
        complete(value)
    require(recovered[-1]['pendingKeys']==[], 'Recovered seed outbox not drained')
    return recovered, {'originalStatus':'FAIL','originalError':'CK_4','recoveryPlanID':plan['id'],
                       'originalReportSHA256':digest((results/stage['name']/'report.json').read_bytes()),
                       'recoveryPlanSHA256':digest(raw),
                       'recoveryReportSHA256':digest((results/name/'report.json').read_bytes())}


def verify_dependencies(stages,plans,results,account):
    require([s['name'] for s in stages]==['00-mac-dependency-seed','00-phone-dependency-repair','00-mac-dependency-fetch'], 'Dependency stage order')
    reports=[]; recovered_seed=None; recovery_summary=None
    for stage in stages:
        plan=stage['plan']; raw=(plans/stage['name']/'SyncLab-Probe-Plan.json').read_bytes()
        require(json.loads(raw)==plan,'Dependency plan changed')
        report=read(results/stage['name']/'report.json')
        recovering=stage['name']=='00-mac-dependency-seed' and report['completedAllCommands'] is False
        rows=dependency_report(plan,raw,report,account,stage['device'],seed_failure=recovering)
        if recovering:
            recovered_seed,recovery_summary=dependency_seed_recovery(stage,rows,plans,results,account)
        reports.append(rows)
    seed={c['mutation']['id']:c['mutation'] for c in stages[0]['plan']['commands'] if 'mutation' in c}
    final={**seed,**{c['mutation']['id']:c['mutation'] for c in stages[1]['plan']['commands'] if 'mutation' in c}}
    def dependency_projection(value, expected, repaired):
        require(facts(value)==expected,'Dependency fixed fact truth mismatch')
        groups={m['object'] for m in expected.values()}
        require(set(value['projections'])==groups,'Dependency projection objects mismatch')
        permanent={'deleted-child','dep-a','dep-b','cause'}
        incomplete=permanent if repaired else permanent|{'missing','trans-mid','trans-root','head'}
        for object_ in groups:
            rows=[m for m in expected.values() if m['object']==object_]
            suffix=object_.removeprefix('probe-batch-')
            parents={p for m in rows for p in m['parents']}
            heads=sorted(m['id'] for m in rows if m['id'] not in parents)
            if suffix=='cause': heads=sorted(m['id'] for m in rows)
            state='staged' if suffix in incomplete else ('deleted' if suffix=='deleted' else 'ready')
            projection=value['projections'][object_]
            require(projection.get('state')==state and projection.get('candidates')==heads and projection.get('complete') is (state in ('ready','deleted')),'Dependency projection truth mismatch')
            preview=expected[heads[0]] if state=='ready' else None
            require(projection.get('preview')==preview,'Dependency preview fell back or changed')
    before=reports[1][2]
    seed_final=recovered_seed[-1] if recovered_seed is not None else reports[0][-1]
    if recovered_seed is not None:
        dependency_projection(reports[0][12],seed,False)
        for value in recovered_seed:
            dependency_projection(value,seed,False)
    dependency_projection(seed_final,seed,False)
    dependency_projection(before,seed,False)
    require(snapshot(reports[0][0])['envelopes']==[] and snapshot(reports[1][0])['envelopes']==[],'Dependency clients not initially empty')
    require(any('ACK_EXACT_AND_RESCHEDULED' in value['events'] for value in reports[1]),'New image has no SDK ACK trace')
    require(facts(seed_final)==facts(before)==seed,'Dependency initial truth missing')
    for name in ['deleted-child','missing','trans-mid','trans-root','dep-a','dep-b','head','cause']:
        require(before['projections']['probe-batch-'+name]['state']=='staged' and before['projections']['probe-batch-'+name].get('preview') is None,'Invalid dependency published')
    require(before['projections']['probe-batch-deleted']['state']=='deleted','Delete intent lost')
    for value in [reports[1][-1],reports[2][-1]]:
        complete(value)
        dependency_projection(value,final,True)
        require(facts(value)==final and value['pendingKeys']==[],'Dependency repaired truth missing')
        for name in ['missing','trans-mid','trans-root','trans-leaf','head','head-dependency','new-image']:
            require(value['projections']['probe-batch-'+name]['state']=='ready','Repaired dependency not ready')
        for name in ['deleted-child','dep-a','dep-b','cause']:
            require(value['projections']['probe-batch-'+name]['state']=='staged','Permanent invalid dependency published')
    require(snapshot(reports[1][-1])==snapshot(reports[2][-1]),'New phone original not received by Mac')
    image=next(c['mutation']['imageHash'] for c in stages[1]['plan']['commands'] if c.get('mutation',{}).get('imageHash'))
    require(any('image-'+image in v['pendingKeys'] for v in reports[1]),'No genuinely new image pending')
    return recovery_summary


def redact(value):
    if isinstance(value, dict):
        return {k:redact(v) for k,v in value.items() if k not in {'accountFingerprint','sourceAccountHash'}}
    if isinstance(value,list):
        return [redact(v) for v in value]
    return value


if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('plans',type=Path);p.add_argument('results',type=Path)
    a=p.parse_args()
    print(json.dumps(verify(a.plans,a.results),indent=2))
