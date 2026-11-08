from pathlib import Path
import importlib.util,json,hashlib,subprocess
root=Path('/private/tmp/PGOS-UnsignedHostReview-rebp7hh1')
script=root/'Repo/Scripts/FormalDevelopmentHost/package_locked_host.py'
spec=importlib.util.spec_from_file_location('packager_red',script);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
real_run=module.subprocess.run; changed=[False]
def injected_run(command,*args,**kwargs):
    if not changed[0] and 'build' in command and '--show-bin-path' not in command:
        source=Path(command[command.index('--package-path')+1])/'Sources/FormalDevelopmentHost/main.swift'
        with source.open('ab') as stream:stream.write(b'\n// Independent synthetic mutation of the actual build snapshot.\n')
        changed[0]=True
    return real_run(command,*args,**kwargs)
module.subprocess.run=injected_run
output=root/'green-output';error=None
try:module.run(output)
except Exception as exc:error=type(exc).__name__+': '+str(exc)
finally:module.subprocess.run=real_run
receipt=json.loads((output/'packaging.json').read_text()) if (output/'packaging.json').exists() else None
actual=hashlib.sha256((output/'source-snapshot/Sources/FormalDevelopmentHost/main.swift').read_bytes()).hexdigest()
expected=receipt['sourceSHA256']['Sources/FormalDevelopmentHost/main.swift'] if receipt else None
result={'scriptSHA256':hashlib.sha256(script.read_bytes()).hexdigest(),'injectedSyntheticSnapshotChange':changed[0],'returnedSuccess':error is None,'error':error,'receiptSourceSHA256':expected,'actualCompiledSnapshotSourceSHA256':actual,'mismatch':actual!=expected,'expected':'Reject mutated build snapshot before publishing successful provenance','result':'FAIL' if error is None and actual!=expected else 'PASS'}
(root/'green-result.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
