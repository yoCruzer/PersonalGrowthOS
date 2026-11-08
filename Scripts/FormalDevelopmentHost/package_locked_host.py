#!/usr/bin/env python3
"""Build a new, unprovisioned Mac-only locked host; never sign or access CloudKit."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import stat
import subprocess
import sys

MANIFEST_SHA256 = "0e382fc3909736e6158093989a48cd67ba19c0f07967bb2b89b87f6c5cce6955"
BUNDLE = "com.yocruzer.PersonalGrowthOS.FormalSyncProbe"
TEAM = "83SKX2PM7B"
CONTAINER = "iCloud.com.yocruzer.PersonalGrowthOS"
APP = "FormalSyncProbe.app"
EXECUTABLE = "FormalDevelopmentHost"
MAX_SOURCE_FILE = 1_048_576
MAX_SOURCES = 16_777_216

class Rejected(Exception):
    pass

def digest(data):
    return hashlib.sha256(data).hexdigest()

def directory(path, create=False):
    """Walk absolute components with held dirfds; never follow a symlink."""
    value = os.fspath(path)
    if not value.startswith('/') or any(p in ('', '.', '..') for p in value.split('/')[1:]):
        raise Rejected('PATH_REJECTED')
    parts = value.split('/')[1:]
    current = os.open('/', os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        for index, part in enumerate(parts):
            if create and index == len(parts) - 1:
                os.mkdir(part, 0o700, dir_fd=current)
            following = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=current)
            os.close(current)
            current = following
        return current
    except BaseException:
        os.close(current)
        raise

def binding(path, fd):
    current = directory(path)
    try:
        a, b = os.fstat(fd), os.fstat(current)
        if (a.st_dev, a.st_ino) != (b.st_dev, b.st_ino):
            raise Rejected('DIRECTORY_CHANGED')
    finally:
        os.close(current)

def read_at(fd, name, limit=MAX_SOURCE_FILE):
    child = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
    try:
        before = os.fstat(child)
        if not stat.S_ISREG(before.st_mode) or before.st_size > limit:
            raise Rejected('FILE_REJECTED')
        chunks, count = [], 0
        while part := os.read(child, min(65536, limit + 1 - count)):
            chunks.append(part); count += len(part)
            if count > limit:
                raise Rejected('FILE_LIMIT')
        after = os.fstat(child)
        if (before.st_size, before.st_mtime_ns, before.st_ctime_ns) != (after.st_size, after.st_mtime_ns, after.st_ctime_ns) or count != before.st_size:
            raise Rejected('FILE_CHANGED')
        return b''.join(chunks)
    finally:
        os.close(child)

def write_at(fd, name, data, executable=False):
    child = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o700 if executable else 0o600, dir_fd=fd)
    try:
        view = memoryview(data)
        while view:
            count = os.write(child, view)
            if count <= 0: raise Rejected('SHORT_WRITE')
            view = view[count:]
        os.fsync(child)
    finally:
        os.close(child)
    os.fsync(fd)

def make_child(fd, name):
    os.mkdir(name, 0o700, dir_fd=fd)
    return os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)

def snapshot(package_fd):
    result = {'Package.swift': read_at(package_fd, 'Package.swift')}
    if digest(result['Package.swift']) != MANIFEST_SHA256:
        raise Rejected('UNREVIEWED_PACKAGE_MANIFEST')
    def walk(fd, prefix):
        for name in sorted(os.listdir(fd)):
            info = os.stat(name, dir_fd=fd, follow_symlinks=False)
            if stat.S_ISLNK(info.st_mode): raise Rejected('SOURCE_SYMLINK')
            if stat.S_ISDIR(info.st_mode):
                child = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
                try: walk(child, prefix + name + '/')
                finally: os.close(child)
            elif stat.S_ISREG(info.st_mode) and name.endswith('.swift'):
                result[prefix + name] = read_at(fd, name)
            else:
                raise Rejected('UNEXPECTED_SOURCE_ENTRY')
            if sum(map(len, result.values())) > MAX_SOURCES: raise Rejected('SOURCE_BUDGET')
    for name in ('Sources', 'Tests'):
        child = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=package_fd)
        try: walk(child, name + '/')
        finally: os.close(child)
    return result

def copy_snapshot(fd, files):
    for name, data in files.items():
        parts = name.split('/')
        current = os.dup(fd)
        try:
            for part in parts[:-1]:
                try: os.mkdir(part, 0o700, dir_fd=current)
                except FileExistsError: pass
                following = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=current)
                os.close(current); current = following
            write_at(current, parts[-1], data)
        finally: os.close(current)

def run(output):
    if sys.platform != 'darwin': raise Rejected('MACOS_REQUIRED')
    # Fixed repository location; no arbitrary package/manifest execution input.
    package = Path(os.path.abspath(__file__)).parents[2] / 'Packages/SyncFoundation'
    if output.is_relative_to(package): raise Rejected('OUTPUT_INSIDE_SOURCE_PACKAGE')
    script_fd = directory(Path(os.path.abspath(__file__)).parent)
    try: trusted = json.loads(read_at(script_fd, 'trusted-source-sha256.json', 65_536))
    finally: os.close(script_fd)
    source_fd = directory(package)
    try:
        files = snapshot(source_fd)
        hashes = {name: digest(data) for name, data in sorted(files.items())}
        if hashes != trusted: raise Rejected('UNREVIEWED_SWIFT_SOURCE')
        destination = directory(output, create=True)
        source_copy = None
        try:
            source_copy = make_child(destination, 'source-snapshot')
            copy_snapshot(source_copy, files)
            def verify_compiler_input():
                binding(output / 'source-snapshot', source_copy)
                if snapshot(source_copy) != files: raise Rejected('COMPILER_INPUT_CHANGED')
            verify_compiler_input()
            build = make_child(destination, 'build')
            os.close(build)
            binding(output, destination)
            command = ['/usr/bin/xcrun', 'swift', 'build', '--package-path', str(output / 'source-snapshot'),
                       '--scratch-path', str(output / 'build'), '--disable-automatic-resolution',
                       '--product', EXECUTABLE, '--configuration', 'debug']
            # Pinned Package.swift has no external package dependencies; no fetch/update path.
            logfd = os.open('build.log', os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=destination)
            with os.fdopen(logfd, 'wb') as log:
                result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=False)
                log.flush(); os.fsync(log.fileno())
            binding(output, destination)
            verify_compiler_input()
            if result.returncode: raise Rejected('BUILD_FAILED')
            if snapshot(source_fd) != files: raise Rejected('SOURCE_CHANGED')
            binding(package, source_fd)
            # Query the actual SwiftPM product path instead of assuming a backend layout.
            lookup = subprocess.run(command + ['--show-bin-path'], capture_output=True, check=True)
            verify_compiler_input()
            product_dir = Path(lookup.stdout.decode().strip())
            if not product_dir.is_relative_to(output / 'build'): raise Rejected('BUILD_PATH_REJECTED')
            product_fd = directory(product_dir)
            try: binary = read_at(product_fd, EXECUTABLE, 134_217_728)
            finally: os.close(product_fd)
            app = make_child(destination, APP)
            try:
                contents = make_child(app, 'Contents')
                try:
                    macos = make_child(contents, 'MacOS')
                    try: write_at(macos, EXECUTABLE, binary, executable=True)
                    finally: os.close(macos)
                    info = {'CFBundleIdentifier': BUNDLE, 'CFBundleName': 'FormalSyncProbe',
                            'CFBundleDisplayName': 'Formal Sync Probe (Locked)', 'CFBundleExecutable': EXECUTABLE,
                            'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1', 'CFBundleShortVersionString': '0.1',
                            'LSMinimumSystemVersion': '14.0', 'LSUIElement': True,
                            'CFBundleSupportedPlatforms': ['MacOSX'], 'NSHighResolutionCapable': True}
                    write_at(contents, 'Info.plist', plistlib.dumps(info, sort_keys=True))
                    write_at(contents, 'PkgInfo', b'APPL????')
                finally: os.close(contents)
            finally: os.close(app)
            entitlements = {'com.apple.application-identifier': TEAM + '.' + BUNDLE,
                            'com.apple.developer.team-identifier': TEAM,
                            'com.apple.developer.icloud-container-identifiers': [CONTAINER],
                            'com.apple.developer.icloud-services': ['CloudKit'],
                            'com.apple.developer.icloud-container-environment': 'Development',
                            'com.apple.security.app-sandbox': True,
                            'com.apple.security.network.client': True}
            # Candidate is outside .app: NOT embedded/applied, not authorization evidence.
            entitlement_bytes = plistlib.dumps(entitlements, sort_keys=True)
            write_at(destination, 'candidate.entitlements', entitlement_bytes)
            receipt = {'formatVersion': 1, 'status': 'UNPROVISIONED_NO_DEVELOPER_SIGNATURE',
                       'bundle': BUNDLE, 'container': CONTAINER, 'environment': 'Development',
                       'candidateRegistration': 'NOT_ESTABLISHED_BY_PACKAGING',
                       'buildCommand': command, 'buildExitCode': result.returncode,
                       'sourceSHA256': {name: digest(data) for name, data in sorted(files.items())},
                       'binarySHA256': digest(binary), 'infoSHA256': digest(plistlib.dumps(info, sort_keys=True)),
                       'candidateEntitlementsSHA256': digest(entitlement_bytes),
                       'packagingCloudOperations': 0, 'appExecutionPerformed': False,
                       'expectedContractUnverifiedByPackaging': 'LOCKED_HOST_NOT_READY',
                       'cloudRunAuthorized': False, 'p0Passed': False,
                       'developerSigningPerformed': False, 'embeddedProfile': False,
                       'linkerAdHocSignature': 'PRESERVED_IF_PRESENT_NOT_DEVELOPER_SIGNING',
                       'limitations': ['Host runtime behavior requires separate inspect/preflight evidence', 'No actual container/account/profile qualification',
                                       'Private immutable source/output leases required; no malicious ABA defense']}
            verify_compiler_input()
            write_at(destination, 'packaging.json', (json.dumps(receipt, indent=2, sort_keys=True) + '\n').encode())
            binding(output, destination)
            print('UNPROVISIONED_NO_DEVELOPER_SIGNATURE; appExecutionPerformed=false; packagingCloudOperations=0')
        finally:
            if source_copy is not None: os.close(source_copy)
            os.close(destination)
    finally: os.close(source_fd)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, help='Absolute NEW directory with existing real parent directories')
    args = parser.parse_args()
    try:
        # Validate raw input before Path removes dot/trailing components.
        fd = directory(os.path.dirname(args.output)); os.close(fd)
        if not args.output.startswith('/') or any(p in ('', '.', '..') for p in args.output.split('/')[1:]):
            raise Rejected('PATH_REJECTED')
        run(Path(args.output))
    except (Rejected, OSError, subprocess.SubprocessError, UnicodeError) as error:
        label = str(error) if isinstance(error, Rejected) else type(error).__name__
        print('PACKAGING_REJECTED: ' + label, file=sys.stderr)
        return 1
    return 0

if __name__ == '__main__':
    sys.exit(main())
