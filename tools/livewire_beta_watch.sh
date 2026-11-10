#!/bin/bash
# Daily watch of Live Wire's beta branch for add-on 2.0 (batman_LiveWireCoupling_v2),
# which plugs into the beta's coupling extension point (LiveWire.Coupling). Run by
# josh's crontab once a day; read-only for the add-on (it never edits or commits).
#
# It updates the beta clone (~/PZ_Mods/.livewire-beta) to GitHub's beta branch and,
# when the beta moved, lists the changed files the 2.0 build depends on and runs the
# 2.0 build's offline tests. It also notes any new Live Wire release tag, and whether
# it has the coupling extension point (then: release 2.0, see the v2 RELEASE.md).
# One line per run goes to ~/livewire-beta-watch.log, starting "LIVE WIRE BETA":
#   UNCHANGED          nothing new on the beta
#   CHANGED ... PASS   the beta moved, nothing the 2.0 build uses changed, tests pass
#   CHANGED ... CHECK  the beta moved and files the 2.0 build uses changed: tests pass,
#                      but read the changes (a session)
#   CHANGED ... FAIL   the 2.0 build's tests fail with the new beta (a session)
#   NEW RELEASE TAG    Live Wire tagged a release (CHECK if it has the extension point)
#   FAILED             could not fetch or run; retried the next day
# Details (commits, files, test output) go to ~/livewire-beta-watch-report.log.
# Run it by hand: ~/PZ_Mods/tools/livewire_beta_watch.sh
set -u
REPO=${LWB_REPO:-/home/josh/PZ_Mods}
CLONE=$REPO/.livewire-beta
LOG=${LWB_LOG:-/home/josh/livewire-beta-watch.log}
REPORT=${LWB_REPORT:-/home/josh/livewire-beta-watch-report.log}
TAGS=${LWB_TAGS:-/home/josh/.livewire-beta-watch-tags}   # release tags already seen
V2=$REPO/batman_LiveWireCoupling_v2/Contents/mods/batman_LiveWireCoupling_v2/42.21/media/lua
LUA=Contents/mods/batman_LiveWire/42.21/media/lua
# Live Wire files the 2.0 build registers with, wraps or reads (beyond the files that
# call LiveWire.Coupling, found below).
WATCH="shared/LiveWire/LW_Coupling.lua shared/LiveWire/LW_Extension.lua
shared/LiveWire/LW_Install.lua shared/LiveWire/LW_Anchor.lua shared/LiveWire/LW_Marks.lua
shared/LiveWire/LW_Config.lua client/LiveWire/LW_ContextMenu.lua
client/LiveWire/LW_InverterPanel.lua client/LiveWire/LW_RangeView.lua
client/LiveWire/LW_PumpView.lua"

log() { echo "$(date '+%F %T') LIVE WIRE BETA $*" | tee -a "$LOG"; }

echo "=== $(date '+%F %T')" >>"$REPORT"
if [ ! -d "$CLONE/.git" ]; then
    timeout 300 git clone --quiet --branch beta https://github.com/cyberbobjr/LiveWire "$CLONE" >>"$REPORT" 2>&1 ||
        { log "FAILED, could not clone the beta into $CLONE"; exit 2; }
fi
g() { git -C "$CLONE" "$@"; }
old=$(g rev-parse --short HEAD)
if ! timeout 120 git -C "$CLONE" fetch --quiet --tags origin beta >>"$REPORT" 2>&1; then
    log "FAILED, could not fetch Live Wire from GitHub; retries tomorrow"
    exit 2
fi

# New release tags (vX.Y.Z), and whether they have the coupling extension point.
seed=0
[ -s "$TAGS" ] || seed=1      # first run: record the existing tags quietly
touch "$TAGS"
for t in $(g tag --list 'v*' | sort -V); do
    grep -qx "$t" "$TAGS" && continue
    echo "$t" >>"$TAGS"
    [ "$seed" = 1 ] && continue
    if g cat-file -e "$t:$LUA/shared/LiveWire/LW_Coupling.lua" 2>/dev/null; then
        log "NEW RELEASE TAG $t, WITH the coupling extension point: release add-on 2.0 (batman_LiveWireCoupling_v2/RELEASE.md)"
    else
        log "NEW RELEASE TAG $t, without the coupling extension point"
    fi
done

new=$(g rev-parse --short origin/beta)
if [ "$old" = "$new" ]; then
    log "UNCHANGED at $new"
    exit 0
fi
n=$(g rev-list --count "$old..origin/beta" 2>/dev/null || echo "?")
{
    echo "--- beta $old..$new ($n commit(s))"
    g log --format='%h %ad %s' --date=format:'%F %H:%M' "$old..origin/beta"
} >>"$REPORT" 2>&1
# Files the 2.0 build depends on that changed: the watch list, plus every file that
# calls LiveWire.Coupling in the old or new beta.
callers=$( { g grep -l 'LiveWire\.Coupling\.' "$old" -- "$LUA"; g grep -l 'LiveWire\.Coupling\.' origin/beta -- "$LUA"; } 2>/dev/null |
    sed "s|^[^:]*:||; s|^$LUA/||" | sort -u)
changed=$(g diff --name-only "$old" origin/beta -- "$LUA" | sed "s|^$LUA/||")
hit=$(for f in $WATCH $callers; do grep -qx "$f" <<<"$changed" && echo "$f"; done | sort -u)
g reset --quiet --hard origin/beta
out=$(timeout 600 "$REPO/.venv/bin/python" "$REPO/tests/run_tests.py" "$V2" 2>&1)
rc=$?
printf -- '--- changed files the 2.0 build depends on:\n%s\n--- 2.0 tests\n%s\nexit %s\n' \
    "${hit:-(none)}" "$(grep -v '^syntax ok\|^\[LiveWireCoupling\]' <<<"$out")" "$rc" >>"$REPORT"
total=$(grep -oE '^[0-9]+ passed' <<<"$out" | awk '{s+=$1} END {print s+0}')
files=$(echo $hit | sed 's|[a-z]*/LiveWire/||g')
if [ "$rc" -ne 0 ]; then
    log "CHANGED $old..$new ($n commits): FAIL, the 2.0 build's tests fail with the new beta; needs a session (report: $REPORT)"
elif [ -n "$hit" ]; then
    log "CHANGED $old..$new ($n commits): CHECK, tests pass ($total) but files the 2.0 build uses changed: $files (report: $REPORT)"
else
    log "CHANGED $old..$new ($n commits): PASS, nothing the 2.0 build uses changed, tests pass ($total)"
fi
exit 0
