"""Syntax-check every Lua file of a mod with Lua 5.1, then run the test files.

Usage: run_tests.py <mod media/lua dir> <test.lua> [<test.lua> ...]

Needs the lupa package, which bundles Lua 5.1. It lives in the repo's own
environment (.venv, ignored by git). To create it once, from the repo root:
    python3 -m venv .venv && .venv/bin/pip install "lupa==2.8"
Each test file runs in a fresh Lua state. Example, from the repo root:
    .venv/bin/python tests/run_tests.py \
        batman_LiveWireCoupling/Contents/mods/batman_LiveWireCoupling/42.21/media/lua \
        tests/zones_test.lua tests/coupling_range_test.lua tests/screen_range_test.lua
Use the dev copy's media/lua folder to test a dev build.
"""
import pathlib
import sys

from lupa.lua51 import LuaRuntime

mod_lua = pathlib.Path(sys.argv[1])
tests = [pathlib.Path(p) for p in sys.argv[2:]]

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
    fails += lua.execute(test.read_text())
sys.exit(1 if bad or fails else 0)
