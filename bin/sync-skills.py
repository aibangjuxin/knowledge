#!/usr/bin/env python3
"""Link externally managed skills (hermes / opencode / ...) into Codex's native skill roots.

Codex only scans a fixed set of roots and has no config.toml key for adding more:

    ~/.codex/skills          (recursive, category sub-folders allowed)
    ~/.agents/skills         (recursive)
    ~/.codex/plugins/cache/**
    <repo>/.codex/skills, <repo>/.agents/skills

Symlinks inside those roots ARE followed, so a symlink farm is the only persistent
way to expose foreign skill trees. This script rebuilds that farm.

Usage:
    sync-skills.py                    # plan + apply
    sync-skills.py --dry-run          # report only
    sync-skills.py --prune            # also drop links whose target disappeared
    sync-skills.py --force            # link names that already exist in native roots
    sync-skills.py --source DIR       # override sources (repeatable)
    sync-skills.py --dest DIR         # override destination (default ~/.codex/skills/external)

Env overrides:
    CODEX_HOME             (default ~/.codex)
    SYNC_SKILLS_SOURCES    colon-separated source roots
    SYNC_SKILLS_DEST       destination directory
"""

import argparse
import datetime
import errno
import json
import os
import re
import sys
from pathlib import Path

CODEX_HOME = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex"))
DEFAULT_DEST = CODEX_HOME / "skills" / "external"
DEFAULT_SOURCES = [
    Path.home() / ".hermes" / "profiles",
    Path.home() / ".config" / "opencode" / "skills",
]
NATIVE_ROOTS = [
    CODEX_HOME / "skills",
    Path.home() / ".agents" / "skills",
    CODEX_HOME / "plugins" / "cache",
]
SKIP_DIRS = {".archive", ".hub", ".locks", ".curator_backups", ".git", "node_modules", "__pycache__"}
LOCK_FILE = CODEX_HOME / ".sync-skills.lock"

NAME_RE = re.compile(r"^name:\s*(.+?)\s*$", re.M)


def frontmatter_name(path: Path):
    """Return (name, error). Only the `name:` key of the YAML frontmatter is needed."""
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        return None, str(exc)
    if not text.lstrip().startswith("---"):
        return None, "no frontmatter"
    end = text.find("\n---", 3)
    if end == -1:
        return None, "unterminated frontmatter"
    match = NAME_RE.search(text[:end])
    if not match:
        return None, "frontmatter has no `name:`"
    name = match.group(1).strip().strip('"\'')
    if not name:
        return None, "empty `name:`"
    return name, None


def collect_source_skills(source: Path):
    """Walk one source root and return [(name|None, skill_dir, error)]."""
    found = []
    if not source.exists():
        return found
    if (source / "SKILL.md").is_file():
        candidates = [source]
    else:
        candidates = []
        for dirpath, dirnames, filenames in os.walk(source):
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
            if "SKILL.md" in filenames:
                candidates.append(Path(dirpath))
    for skill_dir in candidates:
        name, error = frontmatter_name(skill_dir / "SKILL.md")
        found.append((name, skill_dir, error))
    return found


def native_skill_names(dest: Path):
    """Names already provided by Codex's own roots (used for de-duplication)."""
    names = {}
    for root in NATIVE_ROOTS:
        if not root.exists():
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            current = Path(dirpath)
            if current == dest or dest in current.parents:
                continue
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
            if "SKILL.md" in filenames:
                name, error = frontmatter_name(current / "SKILL.md")
                if name:
                    names.setdefault(name, current)
    return names


def resolve_sources(specs):
    """Expand `.../hermes/profiles` into every profile's skills directory."""
    sources = []
    for spec in specs:
        path = Path(spec).expanduser()
        if path.is_dir() and path.name == "profiles":
            sources.extend(sorted(p for p in path.glob("*/skills") if p.is_dir()))
        else:
            sources.append(path)
    return sources


def acquire_lock():
    """Best-effort single-instance lock so cron and manual runs cannot overlap."""
    try:
        import fcntl
    except ImportError:
        return None
    try:
        LOCK_FILE.parent.mkdir(parents=True, exist_ok=True)
        handle = LOCK_FILE.open("w")
        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return handle
    except OSError as exc:
        if exc.errno in (errno.EACCES, errno.EAGAIN):
            print("another sync-skills run is in progress, exiting", file=sys.stderr)
            sys.exit(0)
        return None


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--source", action="append", default=[], help="skill root to import (repeatable)")
    parser.add_argument("--dest", default=os.environ.get("SYNC_SKILLS_DEST", str(DEFAULT_DEST)))
    parser.add_argument("--dry-run", action="store_true", help="report only, do not touch the filesystem")
    parser.add_argument("--prune", action="store_true", help="remove links whose target no longer exists")
    parser.add_argument("--force", action="store_true", help="link names that already exist in native roots")
    parser.add_argument("--quiet", action="store_true")
    parser.add_argument("--json", action="store_true", help="emit a machine-readable summary")
    args = parser.parse_args()

    lock = acquire_lock()

    dest = Path(args.dest).expanduser()
    if args.source:
        sources = resolve_sources(args.source)
    elif os.environ.get("SYNC_SKILLS_SOURCES"):
        sources = resolve_sources(os.environ["SYNC_SKILLS_SOURCES"].split(os.pathsep))
    else:
        sources = resolve_sources([str(p) for p in DEFAULT_SOURCES])
    native = native_skill_names(dest)

    linked, skipped_dup, skipped_native, invalid, missing = [], [], [], [], []
    seen = {}
    for source in sources:
        if not source.exists():
            missing.append(source)
            continue
        for name, skill_dir, error in collect_source_skills(source):
            if error:
                invalid.append((skill_dir, error))
                continue
            if name in seen:
                skipped_dup.append((name, skill_dir, seen[name]))
                continue
            seen[name] = skill_dir
            if name in native and not args.force:
                skipped_native.append((name, skill_dir, native[name]))
                continue
            linked.append((name, skill_dir))

    removed = []
    if not args.dry_run:
        dest.mkdir(parents=True, exist_ok=True)
        for name, skill_dir in linked:
            link = dest / name
            if link.is_symlink():
                if os.readlink(link) == str(skill_dir):
                    continue
                link.unlink()
            elif link.exists():
                print(f"skip (real dir in place): {link}", file=sys.stderr)
                continue
            link.symlink_to(skill_dir)
        if args.prune:
            for entry in dest.iterdir():
                if entry.is_symlink() and not entry.exists():
                    entry.unlink()
                    removed.append(entry.name)

    summary = {
        "generatedAt": datetime.datetime.now().isoformat(timespec="seconds"),
        "dest": str(dest),
        "sources": [str(s) for s in sources],
        "linked": {name: str(path) for name, path in linked},
        "linkedCount": len(linked),
        "skippedDuplicate": len(skipped_dup),
        "skippedNative": len(skipped_native),
        "invalidCount": len(invalid),
        "removed": removed,
        "missingSources": [str(s) for s in missing],
        "invalid": [{"path": str(p), "error": e} for p, e in invalid],
    }
    if not args.dry_run:
        (dest / ".sync-manifest.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")

    if args.json:
        print(json.dumps(summary, indent=2))
    elif not args.quiet:
        print(f"dest            : {dest}")
        print(f"sources         : {', '.join(str(s) for s in sources)}")
        print(f"linked          : {len(linked)}")
        print(f"skipped (dup)   : {len(skipped_dup)}")
        print(f"skipped (native): {len(skipped_native)}")
        print(f"invalid         : {len(invalid)}")
        if removed:
            print(f"pruned          : {len(removed)}")
        for path, error in invalid[:10]:
            print(f"    ! {path}  ({error})")
        for source in missing:
            print(f"    ? missing source: {source}")

    if lock is not None:
        lock.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
