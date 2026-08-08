#!/usr/bin/env python3
"""
Generate APT/Sileo repository metadata from a .deb package.
Produces: Packages, Packages.gz, Packages.bz2, Packages.xz, Release
"""

import os
import sys
import hashlib
import subprocess
import gzip
import bz2
import lzma
import shutil


def run_cmd(cmd, check=True):
    result = subprocess.run(cmd, capture_output=True, text=True)
    if check and result.returncode != 0:
        print(f"ERROR: {' '.join(cmd)}\n{result.stderr}", file=sys.stderr)
        sys.exit(1)
    return result


def get_deb_control(deb_path):
    """Extract full control file from .deb using dpkg-deb -f"""
    result = run_cmd(['dpkg-deb', '-f', deb_path], check=True)
    return result.stdout.strip()


def file_hash(filepath, algorithm):
    h = hashlib.new(algorithm)
    with open(filepath, 'rb') as f:
        while True:
            chunk = f.read(65536)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def file_size(filepath):
    return os.path.getsize(filepath)


def generate_packages(deb_path, repo_root):
    """Generate Packages file with proper APT format."""
    control = get_deb_control(deb_path)
    size = file_size(deb_path)
    md5 = file_hash(deb_path, 'md5')
    sha256 = file_hash(deb_path, 'sha256')

    deb_name = os.path.basename(deb_path)
    rel_path = f"pool/main/iphoneos-arm64/{deb_name}"

    packages_content = f"""{control}
Filename: {rel_path}
Size: {size}
MD5sum: {md5}
SHA256: {sha256}
"""

    packages_path = os.path.join(repo_root, 'Packages')
    with open(packages_path, 'w') as f:
        f.write(packages_content)

    # Compress
    with open(packages_path, 'rb') as src:
        data = src.read()

    with open(os.path.join(repo_root, 'Packages.gz'), 'wb') as f:
        f.write(gzip.compress(data))

    with open(os.path.join(repo_root, 'Packages.bz2'), 'wb') as f:
        f.write(bz2.compress(data))

    with open(os.path.join(repo_root, 'Packages.xz'), 'wb') as f:
        f.write(lzma.compress(data))

    print(f"[generate-repo] Packages generated ({size} bytes)")
    print(f"[generate-repo] MD5:    {md5}")
    print(f"[generate-repo] SHA256: {sha256}")
    return packages_content


def generate_release(repo_root):
    """Generate Release file with MD5Sum and SHA256 sections."""
    files = [
        ('Packages', os.path.join(repo_root, 'Packages')),
        ('Packages.gz', os.path.join(repo_root, 'Packages.gz')),
        ('Packages.bz2', os.path.join(repo_root, 'Packages.bz2')),
        ('Packages.xz', os.path.join(repo_root, 'Packages.xz')),
    ]

    md5_lines = []
    sha256_lines = []

    for name, path in files:
        if os.path.exists(path):
            sz = file_size(path)
            md5 = file_hash(path, 'md5')
            sha256 = file_hash(path, 'sha256')
            md5_lines.append(f" {md5} {sz:>16} {name}")
            sha256_lines.append(f" {sha256} {sz:>16} {name}")

    md5_block = "\n".join(md5_lines) if md5_lines else ""
    sha256_block = "\n".join(sha256_lines) if sha256_lines else ""

    release_content = f"""Origin: aosaid3224 Repo
Label: aosaid3224
Suite: stable
Version: 1.0
Codename: ios
Architectures: iphoneos-arm64
Components: main
Description: AppData Manager Official Repo - Dopamine 3.0 / Rootless Compatible
MD5Sum:
{md5_block}
SHA256:
{sha256_block}
"""

    release_path = os.path.join(repo_root, 'Release')
    with open(release_path, 'w') as f:
        f.write(release_content)

    print("[generate-repo] Release generated")
    return release_content


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <deb-file> <repo-root>", file=sys.stderr)
        sys.exit(1)

    deb_path = sys.argv[1]
    repo_root = sys.argv[2]

    if not os.path.isfile(deb_path):
        print(f"ERROR: .deb not found: {deb_path}", file=sys.stderr)
        sys.exit(1)

    # Create pool directory
    pool_dir = os.path.join(repo_root, 'pool', 'main', 'iphoneos-arm64')
    os.makedirs(pool_dir, exist_ok=True)

    # Copy .deb into pool
    deb_name = os.path.basename(deb_path)
    dest = os.path.join(pool_dir, deb_name)
    shutil.copy2(deb_path, dest)
    print(f"[generate-repo] Copied {deb_name} to pool/")

    # Generate metadata
    generate_packages(deb_path, repo_root)
    generate_release(repo_root)

    print("[generate-repo] Repository generation complete!")
