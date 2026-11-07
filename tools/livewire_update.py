#!/usr/bin/env python3
"""Check a Live Wire release against the Coupled Inverter Zones add-on.

The add-on replaces whole Live Wire Lua files, so every Live Wire update to
them has to be merged in. This script does the checks that found the 1.7.0 and
1.7.2 breaks, and the merge. From the repo root:

    python3 tools/livewire_update.py              # latest Live Wire tag
    python3 tools/livewire_update.py v1.7.3       # a given tag
    python3 tools/livewire_update.py --merge      # also merge into the dev copy

Report (changes nothing in the add-on):
1. Fetches github.com/cyberbobjr/LiveWire into .livewire (cloned if missing).
2. Base = the Live Wire version the release is built on ("Made for Live Wire
   X.Y.Z" in its mod.info); new = the given tag, else the latest.
3. Lists the add-on's replaced files that changed from base to new; functions
   that Live Wire's new copy of a replaced file defines and the add-on's copy
   lacks (other Live Wire files may call them, as 1.7.2 calls Devices.wired);
   Live Wire names the add-on's files use that the new version removed (as
   1.7.0 removed Defs.SHED_LEVEL); changed Live Wire files that the add-on's own
   files require (they wrap functions from them).
4. Runs the offline tests (tests/*_test.lua) on the release with the new Live
   Wire.

--merge (the dev copy's Lua must match the release's): 3-way merges each
changed replaced file into the dev copy (git merge-file, base and new tags),
checks out .livewire at the new tag and runs the tests on the dev copy. Version
numbers, mod.info, README and zips are left to do by hand.

Exit status: 0 nothing to do, 1 the add-on needs work, 2 error.
"""
import argparse
import io
import pathlib
import re
import subprocess
import sys
import tarfile
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
LW = ROOT / ".livewire"
LW_URL = "https://github.com/cyberbobjr/LiveWire"
LW_MOD = "Contents/mods/batman_LiveWire"
REL_MOD = ROOT / "batman_LiveWireCoupling/Contents/mods/batman_LiveWireCoupling"
DEV_MOD = ROOT / "batman_LiveWireCoupling_dev/Contents/mods/batman_LiveWireCoupling_dev"
PYTHON = ROOT / ".venv/bin/python"
SERVER_LW = pathlib.Path.home() / "pzserver/steamapps/workshop/content/108600/3821807453/mods/batman_LiveWire"

GAME_DIR = re.compile(r"^\d+\.\d+$")                     # 42.21
DEF_FN = re.compile(r"^\s*function\s+([A-Za-z_]\w*(?:[.:][A-Za-z_]\w*)+)\s*\(", re.M)
DEF_FN_SET = re.compile(r"^\s*([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)+)\s*=\s*function\b", re.M)
DEF_SET = re.compile(r"\b([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)+)\s*=(?!=)")
ALIAS_SET = re.compile(r"^\s*LiveWire\.([A-Za-z_]\w*)\s*=\s*([A-Za-z_]\w*)\s*$", re.M)
ALIAS_LOCAL = re.compile(r"^\s*local\s+([\w\s,]+?)\s*=\s*(LiveWire\.\w+(?:\s*,\s*LiveWire\.\w+)*)\s*$", re.M)
ALIAS_FN = re.compile(r"^\s*local\s+function\s+(\w+)\(\)\s*return\s+LiveWire\.(\w+)\s+end", re.M)
REQUIRE = re.compile(r'^\s*require\s*\(?\s*"LiveWire/([\w/]+)"', re.M)


def die(msg):
    print("ERROR: " + msg, file=sys.stderr)
    sys.exit(2)


def git(*args, binary=False):
    r = subprocess.run(["git", "-C", str(LW), *args], capture_output=True)
    if r.returncode != 0:
        die("git " + " ".join(args) + ": " + r.stderr.decode(errors="replace").strip())
    return r.stdout if binary else r.stdout.decode("utf-8", "replace")


def vkey(name):
    return tuple(int(x) for x in re.findall(r"\d+", name))


def game_dir(names):
    """The highest game-version folder (42.21) among `names`."""
    found = sorted((n for n in names if GAME_DIR.match(n)), key=vkey)
    return found[-1] if found else None


def lw_lua_root(tag):
    d = game_dir(git("ls-tree", "--name-only", f"{tag}:{LW_MOD}").split())
    if not d:
        die(f"no game-version folder in {LW_MOD} at {tag}")
    return f"{LW_MOD}/{d}/media/lua"


def lw_tree(tag):
    """{relative path: text} of every Lua file of Live Wire at `tag`."""
    root = lw_lua_root(tag)
    data = git("archive", "--format=tar", tag, root, binary=True)
    out = {}
    with tarfile.open(fileobj=io.BytesIO(data)) as tar:
        for m in tar.getmembers():
            if m.isfile() and m.name.endswith(".lua"):
                out[m.name[len(root) + 1:]] = tar.extractfile(m).read().decode("utf-8", "replace")
    return root, out


def addon_lua(mod):
    d = game_dir([p.name for p in mod.iterdir() if p.is_dir()])
    if not d:
        die(f"no game-version folder in {mod}")
    return mod / d / "media/lua"


def addon_tree(lua):
    return {str(p.relative_to(lua)): p.read_text(encoding="utf-8", errors="replace")
            for p in sorted(lua.rglob("*.lua"))}


def functions(text):
    return {n.replace(":", ".") for n in DEF_FN.findall(text)} | set(DEF_FN_SET.findall(text))


def defined_names(files):
    """Dotted names defined by `files` ({path: text}), also under the LiveWire
    module name of each local table (`LiveWire.Devices = Devices`)."""
    out = set()
    for text in files.values():
        alias = {local: mod for mod, local in ALIAS_SET.findall(text)}
        names = {n.replace(":", ".") for n in DEF_FN.findall(text)} | set(DEF_SET.findall(text))
        for n in names:
            if n.startswith("LiveWire."):
                n = n[len("LiveWire."):]
            out.add(n)
            head, _, rest = n.partition(".")
            if head in alias and rest:
                out.add(alias[head] + "." + rest)
    return out


def referenced_names(text):
    """`Module.name` for LiveWire.Module.name, local aliases (local Defs =
    LiveWire.Defs) and accessor functions (local function R() return
    LiveWire.Registry end)."""
    refs = set(re.findall(r"\bLiveWire\.([A-Z]\w*\.[A-Za-z_]\w*)", text))
    for locals_, mods in ALIAS_LOCAL.findall(text):
        for local, mod in zip([s.strip() for s in locals_.split(",")],
                              [s.strip()[len("LiveWire."):] for s in mods.split(",")]):
            refs |= {mod + "." + n for n in re.findall(r"\b" + local + r"[.:]([A-Za-z_]\w*)", text)}
    for fn, mod in ALIAS_FN.findall(text):
        refs |= {mod + "." + n for n in re.findall(r"\b" + fn + r"\(\)[.:]([A-Za-z_]\w*)", text)}
    return refs


def missing_refs(ours, lw_files, replaced):
    """Names the add-on's files use that neither Live Wire's other files nor the
    add-on's define."""
    defined = defined_names({p: t for p, t in lw_files.items() if p not in replaced}) | defined_names(ours)
    out = {}
    for path, text in ours.items():
        for name in referenced_names(text):
            if name not in defined:
                out.setdefault(name, set()).add(path)
    return out


def run_tests(addon, lw_lua):
    tests = sorted(str(p) for p in (ROOT / "tests").glob("*_test.lua"))
    py = str(PYTHON) if PYTHON.exists() else sys.executable
    r = subprocess.run([py, str(ROOT / "tests/run_tests.py"), str(addon), "--livewire", str(lw_lua), *tests],
                       capture_output=True, text=True)
    lines = [l for l in (r.stdout + r.stderr).splitlines() if not l.startswith("syntax ok")]
    print("\n".join("    " + l for l in lines[-40:]))
    return r.returncode == 0


def extract(tag, dest):
    data = git("archive", "--format=tar", tag, LW_MOD, binary=True)
    with tarfile.open(fileobj=io.BytesIO(data)) as tar:
        tar.extractall(dest, filter="data")
    return pathlib.Path(dest) / lw_lua_root(tag)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("tag", nargs="?", help="Live Wire tag to check (default: the latest)")
    ap.add_argument("--base", help="Live Wire tag the add-on is built on (default: from the release mod.info)")
    ap.add_argument("--addon", type=pathlib.Path, help="add-on mod folder to check (default: the release)")
    ap.add_argument("--merge", action="store_true", help="merge the changes into the dev copy")
    ap.add_argument("--no-tests", action="store_true", help="skip the offline tests")
    ap.add_argument("--no-fetch", action="store_true", help="don't fetch new tags from GitHub")
    args = ap.parse_args()
    if args.merge and args.addon:
        die("--merge always merges the release into the dev copy; don't combine it with --addon")

    if not (LW / ".git").exists():
        print(f"Cloning {LW_URL} into {LW} ...")
        r = subprocess.run(["git", "clone", "--quiet", LW_URL, str(LW)])
        if r.returncode != 0:
            die("clone failed")
    elif not args.no_fetch:
        git("fetch", "--quiet", "--tags", "origin")
    tags = sorted((t for t in git("tag").split() if re.match(r"^v\d+(\.\d+)+$", t)), key=vkey)
    if not tags:
        die("no release tags in .livewire")

    mod = (args.addon or REL_MOD).resolve()
    if args.base:
        base = args.base
    else:
        info = (mod / game_dir([p.name for p in mod.iterdir() if p.is_dir()]) / "mod.info").read_text()
        m = re.search(r"Made for Live Wire (\d+(?:\.\d+)+)", info)
        if not m:
            die(f'no "Made for Live Wire X.Y.Z" in {mod}/.../mod.info; pass --base')
        base = "v" + m.group(1)
    new = args.tag or tags[-1]
    for t in (base, new):
        if t not in tags:
            die(f"no tag {t} in Live Wire (tags: {' '.join(tags[-6:])} ...)")

    print(f"Add-on: {mod.relative_to(ROOT) if mod.is_relative_to(ROOT) else mod}")
    print(f"Built on Live Wire {base}; checking {new} (latest tag {tags[-1]}).")
    sdir = SERVER_LW.is_dir() and game_dir([p.name for p in SERVER_LW.iterdir() if p.is_dir()])
    core = SERVER_LW / str(sdir) / "media/lua/shared/LiveWire/LW_Core.lua"
    if sdir and core.exists():
        m = re.search(r'VERSION\s*=\s*"([^"]+)"', core.read_text())
        if m:
            print(f"The server's Live Wire download is version {m.group(1)}.")
            if vkey(m.group(1)) > vkey(tags[-1]):
                print("  It is newer than the latest GitHub tag: the tag may not be pushed yet.")
    if base == new:
        print("Nothing to do: the add-on is built on this version.")
        return 0

    base_root, base_lw = lw_tree(base)
    new_root, new_lw = lw_tree(new)
    if base_root != new_root:
        print(f"! Live Wire moved its Lua folder: {base_root} -> {new_root}. Check the add-on's folder layout.")
    lua = addon_lua(mod)
    ours = addon_tree(lua)
    replaced = sorted(p for p in ours if p in base_lw or p in new_lw)
    own = sorted(p for p in ours if p not in replaced)
    needs_work = False

    print(f"\nReplaced Live Wire files ({len(replaced)}):")
    changed = []
    for p in replaced:
        if p not in new_lw:
            print(f"  ! {p}: Live Wire {new} no longer has this file")
            needs_work = True
        elif base_lw.get(p) != new_lw[p]:
            changed.append(p)
            print(f"  CHANGED {p}")
        else:
            print(f"  same    {p}")
    if changed:
        needs_work = True

    print(f"\nFunctions Live Wire {new} adds to the replaced files, missing from the add-on's copies:")
    any_missing = False
    for p in replaced:
        if p in new_lw:
            for name in sorted(functions(new_lw[p]) - functions(base_lw.get(p, "")) - functions(ours[p])):
                print(f"  ! {name}  ({p})")
                any_missing = needs_work = True
    if not any_missing:
        print("  none")

    print(f"\nNames the add-on's files use that Live Wire {new} removed:")
    gone = missing_refs(ours, new_lw, set(replaced))
    before = missing_refs(ours, base_lw, set(replaced))
    removed = {n: f for n, f in gone.items() if n not in before}
    for n in sorted(removed):
        print(f"  ! {n}  (used in {', '.join(sorted(removed[n]))})")
    if removed:
        needs_work = True
    else:
        print("  none")

    print("\nLive Wire files the add-on's own files require, changed:")
    req = sorted({r + ".lua" for p in own for r in REQUIRE.findall(ours[p])})
    req_changed = [r for r in req for p in new_lw if p.endswith("/" + r) and base_lw.get(p) != new_lw[p]]
    for r in req_changed:
        print(f"  ? {r}: check the add-on's wrappers of it")
    if not req_changed:
        print("  none" + (f" (of {', '.join(req)})" if req else ""))

    ok = True
    if not args.merge and not args.no_tests:
        print(f"\nOffline tests: {mod.name} with Live Wire {new}:")
        with tempfile.TemporaryDirectory() as td:
            ok = run_tests(lua, extract(new, td))
        print("  PASS" if ok else "  FAIL: the add-on breaks with this Live Wire")
        needs_work = needs_work or not ok

    if args.merge:
        dev_lua = addon_lua(DEV_MOD)
        dev = addon_tree(dev_lua)
        if dev != ours:
            diff = sorted(set(dev) ^ set(ours) | {p for p in dev if p in ours and dev[p] != ours[p]})
            die("the dev copy's Lua differs from the release (" + ", ".join(diff)
                + "): fold or reset it before merging")
        print(f"\nMerging into the dev copy ({DEV_MOD.relative_to(ROOT)}):")
        conflicts = 0
        with tempfile.TemporaryDirectory() as td:
            for p in changed:
                b, n = pathlib.Path(td) / "base.lua", pathlib.Path(td) / "new.lua"
                b.write_text(base_lw.get(p, ""), encoding="utf-8")
                n.write_text(new_lw[p], encoding="utf-8")
                r = subprocess.run(["git", "merge-file", "-L", "add-on", "-L", base, "-L", new,
                                    str(dev_lua / p), str(b), str(n)], capture_output=True, text=True)
                if r.returncode < 0 or r.returncode > 127:
                    die(f"git merge-file failed on {p}: {r.stderr.strip()}")
                conflicts += r.returncode
                print(f"  {p}: " + ("clean" if r.returncode == 0 else f"{r.returncode} conflict(s), marked <<<<<<<"))
        if git("status", "--porcelain").strip():
            die(".livewire has local changes; not checking out the new tag")
        git("-c", "advice.detachedHead=false", "checkout", "--quiet", new)
        print(f"  .livewire is now checked out at {new} (tests use it by default).")
        if conflicts:
            print("  Resolve the conflicts, then run the tests.")
        elif not args.no_tests:
            print(f"\nOffline tests: dev copy with Live Wire {new}:")
            ok = run_tests(dev_lua, LW / new_root)
            print("  PASS" if ok else "  FAIL")
        print("\nLeft to do by hand: the add-on's own changes to the merged files still make sense,"
              f" dev mod.info (modversion, description), dev README, a zip in dist/.")

    print("\nResult: " + ("the add-on needs an update for Live Wire " + new if needs_work
                          else f"Live Wire {new} changes nothing the add-on depends on."))
    if needs_work and not args.merge and not args.addon:
        print(f"To start the dev build: python3 tools/livewire_update.py {new} --merge")
    return 1 if needs_work else 0


if __name__ == "__main__":
    sys.exit(main())
