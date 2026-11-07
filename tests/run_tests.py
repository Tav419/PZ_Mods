"""Syntax-check every Lua file of a mod with Lua 5.1, then run the test files.

Usage: run_tests.py <mod media/lua dir> [--livewire <Live Wire media/lua dir>] [<test.lua> ...]

Needs the lupa package, which bundles Lua 5.1. It lives in the repo's own
environment (.venv, ignored by git). To create it once, from the repo root:
    python3 -m venv .venv && .venv/bin/pip install "lupa==2.8"
Each test file runs in a fresh Lua state. Example, from the repo root:
    .venv/bin/python tests/run_tests.py \
        batman_LiveWireCoupling/Contents/mods/batman_LiveWireCoupling/42.21/media/lua
Use the dev copy's media/lua folder to test a dev build.

With no test files given, every tests/*_test.lua runs. --livewire points at Live
Wire's own media/lua folder; by default the checkout in .livewire (see the
README). Tests that run Live Wire's own files with the add-on
(link_couple_test.lua) read it as the global LIVEWIRE_LUA.
"""
import pathlib
import re
import sys

from lupa.lua51 import LuaError, LuaRuntime

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent

args = sys.argv[1:]
livewire = None
if "--livewire" in args:
    i = args.index("--livewire")
    livewire = args[i + 1]
    del args[i:i + 2]
if not args:
    sys.exit(__doc__)
mod_lua = pathlib.Path(args[0])
tests = [pathlib.Path(p) for p in args[1:]] or sorted(HERE.glob("*_test.lua"))
if livewire is None:
    lw_mod = ROOT / ".livewire/Contents/mods/batman_LiveWire"
    games = sorted((p for p in lw_mod.glob("*") if re.match(r"^\d+\.\d+$", p.name)),
                   key=lambda p: tuple(int(x) for x in p.name.split(".")))
    if games:
        livewire = str(games[-1] / "media/lua")

bad = 0
for f in sorted(mod_lua.rglob("*.lua")):
    lua = LuaRuntime(unpack_returned_tuples=True)
    ok, err = lua.eval("function(s, n) local f, e = loadstring(s, n); return f ~= nil, e or '' end")(
        f.read_text(), "@" + f.name)
    if not ok:
        bad += 1
        print("SYNTAX ERROR", err)
    else:
        print("syntax ok   ", f.relative_to(mod_lua))

fails = 0
for test in tests:
    print("==", test.name)
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().MOD_LUA = str(mod_lua)
    if livewire:
        lua.globals().LIVEWIRE_LUA = str(livewire)
    try:
        fails += lua.execute(test.read_text())
    except LuaError as e:
        # A Lua error stops that test file only: count it and run the others.
        fails += 1
        print("FAIL: Lua error, the rest of", test.name, "did not run:", str(e).splitlines()[0])
sys.exit(1 if bad or fails else 0)
