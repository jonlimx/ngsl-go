"""Prepare a checked, reproducible Kokoro asset pack without touching app data.

Uses a locally cached public model, or downloads the pinned official archive.
No credentials, other apps' data, or system voice configuration are accessed.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import tarfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def verify_model(directory, manifest):
    for item in manifest['files']:
        path = Path(directory) / item['path']
        if not path.is_file() or path.stat().st_size != item['bytes'] or sha256(path) != item['sha256']:
            raise ValueError('Kokoro model file is missing or mismatched: ' + item['path'])


def check_pack(path, manifest):
    with zipfile.ZipFile(path) as archive:
        expected = {item['path']: item for item in manifest['files']}
        if len(archive.namelist()) != len(expected) or set(archive.namelist()) != set(expected):
            raise ValueError('Kokoro archive file list does not match the pinned manifest')
        for name, item in expected.items():
            if archive.getinfo(name).file_size != item['bytes']:
                raise ValueError('Kokoro archive size mismatch: ' + name)
            digest = hashlib.sha256()
            with archive.open(name) as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b''):
                    digest.update(block)
            if digest.hexdigest() != item['sha256']:
                raise ValueError('Kokoro archive content mismatch: ' + name)


def download_model(manifest):
    cache = ROOT / '.build-resources'
    cache.mkdir(exist_ok=True)
    archive_path = cache / 'kokoro-multi-lang-v1_0.tar.bz2'
    if not archive_path.exists() or sha256(archive_path) != manifest['archiveSha256']:
        pending = archive_path.with_suffix('.pending')
        print('Downloading the pinned official Kokoro model (first build only).', flush=True)
        try:
            with urllib.request.urlopen(manifest['source'], timeout=60) as source, pending.open('wb') as target:
                shutil.copyfileobj(source, target, length=1024 * 1024)
            if sha256(pending) != manifest['archiveSha256']:
                raise ValueError('Official Kokoro archive checksum mismatch; refusing to use it')
            pending.replace(archive_path)
        finally:
            pending.unlink(missing_ok=True)
    output = cache / 'kokoro-multi-lang-v1_0'
    output.mkdir(exist_ok=True)
    # Extract only named regular files; never follow archive links or paths.
    expected = {item['path'] for item in manifest['files']}
    found = set()
    with tarfile.open(archive_path, 'r:bz2') as archive:
        for member in archive:
            parts = PurePosixPath(member.name).parts
            if len(parts) < 2 or '..' in parts or member.name.startswith('/'):
                continue
            relative = '/'.join(parts[1:])
            if relative not in expected:
                continue
            if not member.isfile():
                raise ValueError('Model archive contains a link/non-file: ' + relative)
            destination = output / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            with archive.extractfile(member) as source, destination.open('wb') as target:
                shutil.copyfileobj(source, target)
            found.add(relative)
    if found != expected:
        raise ValueError('Official model archive is incomplete')
    return output


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--model', type=Path)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    manifest_path = ROOT / 'data/kokoro_model.json'
    manifest = json.loads(manifest_path.read_text())
    output = ROOT / 'app/assets/tts'
    output.mkdir(parents=True, exist_ok=True)
    archive_path = output / 'kokoro.zip'
    if args.check:
        check_pack(archive_path, manifest)
    elif archive_path.exists():
        check_pack(archive_path, manifest)
    else:
        candidates = [args.model, os.environ.get('NGSL_KOKORO_MODEL'),
            ROOT / '.build-resources/kokoro-multi-lang-v1_0',
            Path.home() / '.cache/ngsl-go-tts-models/kokoro-multi-lang-v1_0',
            Path.home() / '.cache/fce-go-tts-models/kokoro-multi-lang-v1_0']
        model = next((Path(p) for p in candidates if p and (Path(p) / 'model.onnx').exists()), None)
        if model is None:
            model = download_model(manifest)
        verify_model(model, manifest)
        pending = archive_path.with_suffix('.pending.zip')
        try:
            with zipfile.ZipFile(pending, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
                for item in manifest['files']:
                    info = zipfile.ZipInfo(item['path'], (1980, 1, 1, 0, 0, 0))
                    info.compress_type = zipfile.ZIP_DEFLATED
                    info.external_attr = 0o100644 << 16
                    with (model / item['path']).open('rb') as source, archive.open(info, 'w', force_zip64=True) as target:
                        shutil.copyfileobj(source, target, length=1024 * 1024)
            check_pack(pending, manifest)
            pending.replace(archive_path)
        finally:
            pending.unlink(missing_ok=True)
    shutil.copyfile(manifest_path, output / 'kokoro_manifest.json')
    print(f'Kokoro offline pack verified: {len(manifest["files"])} files, {archive_path.stat().st_size // 1024 // 1024} MiB')


if __name__ == '__main__':
    main()
