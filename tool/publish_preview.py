"""Publish verified preview assets after CI and installed-APK checks succeed."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

TAG = 'v0.1.0-preview.1'
REPO = 'mizanurofcl55-hue/FLOW-SHARE'


def gh(*args):
    return subprocess.check_output(['gh', *args], text=True)


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def prepare_assets(root, out):
    names = {
        'android': {
            'app-arm64-v8a-debug.apk': 'FlowShare-0.1.0-Android-arm64-Preview.apk',
            'app-armeabi-v7a-debug.apk': 'FlowShare-0.1.0-Android-armv7-Preview.apk',
            'app-x86_64-debug.apk': 'FlowShare-0.1.0-Android-x86_64-Preview.apk',
            'android-runtime-dependencies.txt': 'Android-runtime-dependencies.txt',
        },
        'windows': {'FlowShare-windows-preview.zip': 'FlowShare-0.1.0-Windows-x64-Preview.zip'},
        'macos': {'FlowShare-macos-unsigned-preview.tar.gz': 'FlowShare-0.1.0-macOS-Unsigned-Preview.tar.gz'},
        'ios': {'FlowShare-ios-unsigned-preview.tar.gz': 'FlowShare-0.1.0-iOS-Unsigned-Developer-Build.tar.gz'},
    }
    out.mkdir(exist_ok=True)
    for platform, mapping in names.items():
        folder = root / f'FlowShare-{platform}-preview'
        sums = {}
        for line in (folder / 'SHA256SUMS.txt').read_text().splitlines():
            expected, name = line.split('  ', 1)
            assert Path(name).name == name, 'Unsafe artifact name'
            assert name not in sums, 'Duplicate checksum entry'
            sums[name] = expected
        for source_name, public_name in mapping.items():
            source = folder / source_name
            assert source.is_file() and not source.is_symlink(), source_name
            assert source.stat().st_size > 0, f'Empty artifact: {source_name}'
            assert digest(source) == sums[source_name], f'Checksum mismatch: {source_name}'
            shutil.copy2(source, out / public_name)
    return {path.name: digest(path) for path in sorted(out.iterdir())}


def main():
    assert os.environ['GITHUB_REPOSITORY'] == REPO, 'Unexpected repository'
    sha = os.environ['BUILD_SHA']
    run_id = os.environ['BUILD_RUN_ID']
    # A published version is immutable; subsequent CI runs cannot replace it.
    releases = json.loads(gh('api', f'repos/{REPO}/releases?per_page=100'))
    existing = next((item for item in releases if item['tag_name'] == TAG), None)
    if existing and not existing['draft']:
        print(f'{TAG} is already published; existing assets remain unchanged.')
        return
    if existing:
        assert existing['target_commitish'] == sha, 'Draft belongs to another source commit'
    out = Path('public-release')
    hashes = prepare_assets(Path('release-artifacts'), out)
    provenance = {
        'repository': REPO, 'version': TAG, 'source_commit': sha,
        'build_run': f'https://github.com/{REPO}/actions/runs/{run_id}',
        'android_smoke_run': f"https://github.com/{REPO}/actions/runs/{os.environ.get('SMOKE_RUN_ID', os.environ['GITHUB_RUN_ID'])}",
        'status': 'LAN/hotspot preview; physical interoperability and production signing pending',
        'sha256': hashes,
    }
    (out / 'build-provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
    hashes['build-provenance.json'] = digest(out / 'build-provenance.json')
    (out / 'SHA256SUMS.txt').write_text(''.join(f'{value}  {name}\n' for name, value in sorted(hashes.items())))
    hashes['SHA256SUMS.txt'] = digest(out / 'SHA256SUMS.txt')
    body = Path('docs/releases/v0.1.0-preview.1.md').read_text()
    body += (f"\n\n## Verification for these downloads\n\nSource: `{sha}`. "
             f"[Four-platform build and automated tests]({provenance['build_run']}) · "
             f"[Android installed-APK test]({provenance['android_smoke_run']}).\n")
    Path('release-notes.md').write_text(body)
    if not existing:
        gh('release', 'create', TAG, '--repo', REPO, '--target', sha, '--draft', '--prerelease',
           '--title', 'FlowShare 0.1.0 — LAN / Hotspot Preview', '--notes-file', 'release-notes.md')
    gh('release', 'upload', TAG, *[str(out / name) for name in sorted(hashes)], '--repo', REPO, '--clobber')
    # A draft may have no Git tag yet, so the by-tag endpoint can return 404.
    releases = json.loads(gh('api', f'repos/{REPO}/releases?per_page=100'))
    release = next(item for item in releases if item['tag_name'] == TAG)
    remote = {asset['name']: asset for asset in release['assets']}
    assert set(remote) == set(hashes), 'Release asset list mismatch'
    for name, value in hashes.items():
        assert remote[name]['size'] == (out / name).stat().st_size, f'Wrong asset size: {name}'
        assert remote[name]['digest'] == f'sha256:{value}', f'Wrong uploaded digest: {name}'
    gh('release', 'edit', TAG, '--repo', REPO, '--draft=false', '--prerelease',
       '--notes-file', 'release-notes.md')
    print(f'Published https://github.com/{REPO}/releases/tag/{TAG}')


if __name__ == '__main__':
    main()
