"""Syntax-check every Lua file of a mod with Lua 5.1, then run the test files.

Usage: run_tests.py <mod media/lua dir> <test.lua> [<test.lua> ...]

Needs the lupa package (pip install lupa), which bundles Lua 5.1. Each test file
runs in a fresh Lua state. Example, from the repo root:
    python3 tests/run_tests.py \
        batman_LiveWireCoupling_dev/Contents/mods/batman_LiveWireCoupling_dev/42.21/media/lua \
        tests/zones_test.lua tests/coupling_range_test.lua
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
