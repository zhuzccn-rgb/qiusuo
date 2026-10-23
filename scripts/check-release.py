#!/usr/bin/env python3
"""Check the files Git would publish, without printing matched secret values."""
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
BLOCKED_PARTS = {'.specstory', '.cursor', '.codex', '.vscode', 'xcuserdata', 'recordings', 'transcripts', 'private'}
BLOCKED_SUFFIXES = {'.sqlite', '.db', '.caf', '.wav', '.m4a', '.mp3', '.mp4', '.mov', '.pdf', '.zip', '.pem', '.key', '.p12'}
SECRET_PATTERNS = {
    'private-key': re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
    'github-token': re.compile(rb'(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})'),
    'provider-token': re.compile(rb'\bsk-(?:proj-|ant-)?[A-Za-z0-9_-]{24,}\b'),
    'aws-access-id': re.compile(rb'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b'),
}

def files_to_check():
    probe = subprocess.run(['git', '-C', str(ROOT), 'rev-parse', '--show-toplevel'], capture_output=True, text=True)
    if probe.returncode == 0 and Path(probe.stdout.strip()).resolve() == ROOT:
        result = subprocess.run(['git', '-C', str(ROOT), 'ls-files', '-z', '--cached', '--others', '--exclude-standard'], capture_output=True, check=True)
        return sorted(set(Path(p) for p in result.stdout.decode().split('\0') if p))
    # Before initialization, emulate .gitignore using a temporary Git index-free repository.
    import tempfile
    with tempfile.TemporaryDirectory(prefix='qiusuo-scan-') as tmp:
        subprocess.run(['git', 'init', '-q', tmp], check=True)
        result = subprocess.run(['git', '--git-dir', str(Path(tmp) / '.git'), '--work-tree', str(ROOT), 'ls-files', '-z', '--others', '--exclude-standard'], capture_output=True, check=True)
        return sorted(Path(p) for p in result.stdout.decode().split('\0') if p)

def main():
    findings = []
    paths = files_to_check()
    for relative in paths:
        p = ROOT / relative
        if not p.exists():
            findings.append((str(relative), 'missing tracked file'))
            continue
        if p.is_symlink():
            findings.append((str(relative), 'symlink requires manual review'))
            continue
        if set(relative.parts) & BLOCKED_PARTS or p.suffix.lower() in BLOCKED_SUFFIXES or p.name.startswith('.env'):
            findings.append((str(relative), 'private-file category'))
        blob = p.read_bytes()
        if len(blob) > 10_000_000:
            findings.append((str(relative), 'unexpected file over 10 MB'))
        for label, pattern in SECRET_PATTERNS.items():
            if pattern.search(blob):
                findings.append((str(relative), label))
    for name in ['LICENSE', 'README.md', 'README.zh-CN.md', 'docs/PRIVACY.md', 'docs/RESPONSIBLE_USE.md', 'THIRD_PARTY_NOTICES.md', 'third_party/MathJax/LICENSE']:
        if not (ROOT / name).is_file():
            findings.append((name, 'required release file missing'))
    for path, category in findings:
        print(f'FAIL {path}: {category}')
    if findings:
        return 1
    print(f'PASS: checked {len(paths)} publishable files; no configured secret/private-file patterns found.')
    print('This is a targeted check, not a guarantee. Review the complete diff before publishing.')
    return 0

if __name__ == '__main__':
    sys.exit(main())
