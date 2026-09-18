"""Build and verify addon source packages from saved Git versions. No live deployment."""
import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import subprocess
import tarfile
import tempfile
import zipfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def git(repo, *args):
    return subprocess.check_output(['git', '-c', f'safe.directory={repo}', '-C', str(repo), *args])


def safe_path(name):
    p = PurePosixPath(name)
    if (not name.startswith('addons/') or '\\' in name or ':' in name or
            p.is_absolute() or '..' in p.parts or '.' in p.parts or str(p) != name):
        raise ValueError(f'Unsafe package path: {name}')
    return p


def build(repo, output, revision='HEAD'):
    repo = Path(repo).resolve()
    commit = git(repo, 'rev-parse', '--verify', f'{revision}^{{commit}}').decode().strip()
    # Archive reads committed blobs, never unsaved working files or ignored settings.
    archive = git(repo, 'archive', '--format=tar', commit, 'addons')
    files = {}
    with tarfile.open(fileobj=io.BytesIO(archive)) as source:
        for member in source:
            if member.isdir():
                continue
            safe_path(member.name)
            if not member.isfile():
                raise ValueError('Links and special files are not supported.')
            files[member.name] = source.extractfile(member).read()
    if not files:
        raise ValueError('No committed addons found.')
    manifest = {
        'format': 'ffxi-addon-source-package-v1', 'source_commit': commit,
        'scope': 'committed addon source; includes documentation and tests',
        'deployment': 'not-deployed', 'loaded_clients': 'not-verified',
        'partyops_build': 'not-paired', 'game_behavior': 'not-verified',
        'files': {name: {'sha256': digest(data), 'bytes': len(data)}
                  for name, data in sorted(files.items())},
    }
    encoded = json.dumps(manifest, sort_keys=True, indent=2).encode() + b'\n'
    # Exclusive creation prevents accidentally replacing a reviewed package.
    with zipfile.ZipFile(output, 'x', compression=zipfile.ZIP_DEFLATED) as target:
        for name, data in [('manifest.json', encoded), *sorted(files.items())]:
            info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            target.writestr(info, data)
    return verify(output)


def verify(package):
    with zipfile.ZipFile(package) as source:
        names = source.namelist()
        if len(names) != len(set(names)):
            raise ValueError('Duplicate archive entries.')
        manifest = json.loads(source.read('manifest.json'))
        if manifest.get('format') != 'ffxi-addon-source-package-v1':
            raise ValueError('Unknown package format.')
        expected = manifest['files']
        if set(names) != {'manifest.json', *expected} or not expected:
            raise ValueError('Package inventory mismatch.')
        for name, evidence in expected.items():
            safe_path(name)
            data = source.read(name)
            if len(data) != evidence['bytes'] or digest(data) != evidence['sha256']:
                raise ValueError(f'Package content mismatch: {name}')
    return manifest


def materialize(package, destination):
    """Only used inside rehearsal-created temporary directories."""
    verify(package)
    with zipfile.ZipFile(package) as source:
        for name in source.namelist():
            if name == 'manifest.json':
                continue
            relative = safe_path(name)
            target = destination.joinpath(*relative.parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(source.read(name))


def rehearse(candidate, previous):
    new, old = verify(candidate), verify(previous)
    with tempfile.TemporaryDirectory(prefix='ffxi-release-rehearsal-') as tmp:
        root = Path(tmp)
        materialize(previous, root / 'previous')
        materialize(candidate, root / 'candidate')
        materialize(previous, root / 'rollback')
        for name, expected in old['files'].items():
            assert digest((root / 'rollback' / name).read_bytes()) == expected['sha256']
        assert set(p.relative_to(root / 'rollback').as_posix()
                   for p in (root / 'rollback').rglob('*') if p.is_file()) == set(old['files'])
    return {'result': 'PASS', 'candidate': new['source_commit'],
            'previous': old['source_commit'], 'scope': 'package restoration in temporary folders only'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    create = commands.add_parser('build')
    create.add_argument('repo'); create.add_argument('output'); create.add_argument('--revision', default='HEAD')
    check = commands.add_parser('verify'); check.add_argument('package')
    rehearsal = commands.add_parser('rehearse')
    rehearsal.add_argument('candidate'); rehearsal.add_argument('previous')
    args = parser.parse_args()
    if args.command == 'build':
        result = build(args.repo, args.output, args.revision)
    elif args.command == 'verify':
        result = verify(args.package)
    else:
        result = rehearse(args.candidate, args.previous)
    print(json.dumps({k: v for k, v in result.items() if k != 'files'}, indent=2))
