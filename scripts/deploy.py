#!/usr/bin/env python3
"""Deploy the Snapshots v2 plugin into the local grandMA3 onPC plugin DataPool.

Idempotent + destructive: the destination is rmtree'd then re-created, so stale
files from a previous deploy never linger. Snapshots is a MULTI-FILE ComponentLua
plugin whose manifest (Snapshots.xml) references a nested FileName
(`lib/version.lua`). That relative path MUST resolve on-console, so we PRESERVE the
`lib/` (and `lib/vendor/`) subdirectory structure under the plugin dir — only the
entry point + manifest sit at the plugin root.

Destinations:
    macOS:   ~/MALightingTechnology/gma3_library/datapools/plugins/Snapshots
    Windows: %PROGRAMDATA%\\MALightingTechnology\\gma3_library\\datapools\\plugins\\Snapshots
    override: $MA3_PLUGINS_DIR/Snapshots

Usage:
    python3 scripts/deploy.py                          # deploy to the default location
    python3 scripts/deploy.py --dry-run                # print the plan without copying
    MA3_PLUGINS_DIR=/path python3 scripts/deploy.py    # override the plugins dir

Multi-file dev-loop caveat: ReloadAllPlugins does NOT pick up sub-module edits —
restart onPC fully after each deploy (HowGrandMA3PluginStructureWorks.md §11.7).
"""

import argparse
import os
import shutil
import sys
from pathlib import Path

PLUGIN_NAME = "Snapshots"

# Whitelist — repo-root-relative; each item is copied to the SAME relative path
# under dest so the manifest's nested FileName="lib/version.lua" resolves.
# Everything not listed (.git, dev-only dirs, scripts, tests, README.md,
# .DS_Store) is excluded by construction.
SOURCES = [
    "Snapshots.xml",
    "Snapshots.lua",
    "lib",                   # the WHOLE plugin lib tree (all ComponentLua modules + vendor/json.lua).
                             # A directory whitelist entry (per the deploy contract) so every current
                             # AND future lib/*.lua + lib/ui/*.lua module deploys — the previous
                             # per-file list silently dropped every module added after Phase 1.
]

# Declared for parity with the siblings even though the explicit-file whitelist
# already excludes noise.
IGNORE = shutil.ignore_patterns(".DS_Store", ".git", "__pycache__", "*.pyc")


def resolve_dest() -> Path:
    override = os.environ.get("MA3_PLUGINS_DIR")           # override FIRST
    if override:
        return Path(override).expanduser() / PLUGIN_NAME
    if sys.platform == "darwin":
        return (Path.home() / "MALightingTechnology" / "gma3_library"
                / "datapools" / "plugins" / PLUGIN_NAME)
    if sys.platform == "win32":
        programdata = os.environ.get("PROGRAMDATA")
        if not programdata:
            raise RuntimeError("PROGRAMDATA not set; cannot locate gma3_library on Windows")
        return (Path(programdata) / "MALightingTechnology" / "gma3_library"
                / "datapools" / "plugins" / PLUGIN_NAME)
    raise RuntimeError(
        f"grandMA3 onPC is macOS or Windows only (sys.platform={sys.platform!r}). "
        "Set MA3_PLUGINS_DIR to deploy elsewhere."
    )


def deploy(repo_root: Path, dest: Path, dry_run: bool) -> None:
    missing = [s for s in SOURCES if not (repo_root / s).exists()]
    if missing:
        raise RuntimeError(f"missing source items: {', '.join(missing)}")

    if dry_run:
        print(f"[dry-run] would replace {dest}")
        for name in SOURCES:
            print(f"[dry-run]   {name}")
        return

    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists():
        shutil.rmtree(dest)          # destructive + idempotent: no stale files survive
    dest.mkdir()
    for rel in SOURCES:
        src = repo_root / rel
        target = dest / rel
        target.parent.mkdir(parents=True, exist_ok=True)   # PRESERVE the tree (do NOT flatten)
        if src.is_dir():
            shutil.copytree(src, target, ignore=IGNORE)     # whole subtree; IGNORE drops noise
        else:
            shutil.copy2(src, target)
        print(f"  {rel}")
    print(f"deployed to {dest}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Deploy the Snapshots plugin to the local grandMA3 plugins dir."
    )
    parser.add_argument("--dry-run", action="store_true", help="print the plan without copying")
    args = parser.parse_args()
    try:
        repo_root = Path(__file__).resolve().parent.parent
        dest = resolve_dest()
        deploy(repo_root, dest, args.dry_run)
        if not args.dry_run:
            print("Done. Restart MA3 onPC to pick up multi-file changes (§11.7).")
        return 0
    except RuntimeError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
