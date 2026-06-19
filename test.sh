#!/usr/bin/env bash
# quotabar test suite — feeds crafted JSON to statusline.sh and checks output.
# Run:  bash test.sh        (needs bash + node)
SL="$(cd "$(dirname "$0")" && pwd)/statusline.sh"
TMP="$(mktemp -d)" || { echo "cannot create temp dir (read-only FS?)"; exit 1; }
trap 'rm -rf "$TMP"' EXIT
export XDG_CACHE_HOME="$TMP/xdg"   # 모든 호출을 임시 캐시로 격리 — 실제 ~/.cache/quotabar 절대 안 건드림(출력 캐시 + cc-limits 스냅샷 포함)
pass=0; fail=0
G=$'\033[32m'; RED=$'\033[31m'; Z=$'\033[0m'
ok(){  pass=$((pass+1)); printf "  ${G}PASS${Z} %s\n" "$1"; }
bad(){ fail=$((fail+1)); printf "  ${RED}FAIL${Z} %s\n       got: |%s|\n" "$1" "$2"; }
has(){ case "$2" in *"$1"*) return 0;; *) return 1;; esac; }

FUT=4102444800   # 2100 (window always in the future, never expired)
CC='{"session_id":"t","rate_limits":{"five_hour":{"used_percentage":15,"resets_at":'$FUT'},"seven_day":{"used_percentage":74,"resets_at":'$FUT'}}}'

# fake Codex rollout whose token_count event is $1 minutes old
fake(){ rm -rf "$TMP/cx"; mkdir -p "$TMP/cx/2026/06/16"
  node -e 'const fs=require("fs");const ts=new Date(Date.now()-(+process.argv[1])*60000).toISOString();fs.writeFileSync(process.argv[2],JSON.stringify({timestamp:ts,type:"event_msg",payload:{rate_limits:{primary:{used_percent:7,resets_at:'$FUT'},secondary:{used_percent:16,resets_at:'$FUT'}}}})+"\n")' "$1" "$TMP/cx/2026/06/16/rollout-z.jsonl"; }

# shared env: no color, no cache, ignore the real user config
run(){ env NO_COLOR=1 CC_USAGE_CACHE_TTL=0 CC_USAGE_CONFIG=/dev/null "$@" bash "$SL"; }

o=$(printf '%s' "$CC" | run)
{ has "CC 5h" "$o" && has "74%" "$o"; } && ok "default shows CC 5h + 7d %" || bad "default" "$o"

o=$(printf '%s' "$CC" | run)
{ has "CC 5h" "$o" && ! has "CC 7d" "$o"; } && ok "provider tag shown once per line" || bad "dedup" "$o"

o=$(printf '%s' "$CC" | run CC_USAGE_SEGMENTS=5h CC_USAGE_STYLE=ascii)
{ has "#" "$o" && ! has "▰" "$o"; } && ok "ascii style uses #/-" || bad "ascii" "$o"

o=$(printf '%s' "$CC" | run CC_USAGE_SEGMENTS=5h CC_USAGE_TAG_CC=Claude)
has "Claude 5h" "$o" && ok "custom provider tag" || bad "custom tag" "$o"

o=$(printf '%s' '{}' | run CC_USAGE_SEGMENTS=5h,7d)
[ -z "$o" ] && ok "missing rate_limits -> empty (no crash)" || bad "missing rl" "$o"

o=$(printf '%s' '{"rate_limits":{"five_hour":{"used_percentage":"x","resets_at":'$FUT'},"seven_day":{"used_percentage":74,"resets_at":'$FUT'}}}' | run CC_USAGE_SEGMENTS=5h,7d)
{ ! has "NaN" "$o" && has "74%" "$o"; } && ok "garbage % -> segment hidden, no NaN" || bad "garbage %" "$o"

o=$(printf '%s' '{"cost":{"total_cost_usd":"1.25"}}' | run CC_USAGE_SEGMENTS=cost)
has '$1.25' "$o" && ok "cost as string -> no crash" || bad "cost string" "$o"

fake 5
o=$(printf '%s' "$CC" | run CC_USAGE_SEGMENTS='5h,7d;cx5h,cx7d' CC_USAGE_CODEX_DIR="$TMP/cx")
has "Cx 5h" "$o" && ok "fresh Codex -> full Cx row" || bad "codex fresh" "$o"

fake 240
o=$(printf '%s' "$CC" | run CC_USAGE_SEGMENTS='5h,7d;cx5h,cx7d' CC_USAGE_CODEX_DIR="$TMP/cx")
{ has "Cx idle" "$o" && ! has "Cx 5h" "$o"; } && ok "stale Codex -> collapses to 'Cx idle'" || bad "codex stale" "$o"

fake 240
o=$(printf '%s' "$CC" | run CC_USAGE_SEGMENTS='5h,7d;cx5h,cx7d' CC_USAGE_CODEX_DIR="$TMP/cx" CC_USAGE_STALE_MIN=0)
has "Cx 5h" "$o" && ok "STALE_MIN=0 -> never collapses" || bad "stale off" "$o"

fake 240   # first session: no rate_limits + CC segments configured + stale Codex -> no lonely 'Cx idle'
o=$(printf '%s' '{}' | run CC_USAGE_SEGMENTS='5h,7d;cx5h,cx7d' CC_USAGE_CODEX_DIR="$TMP/cx")
[ -z "$o" ] && ok "missing rate_limits + stale Codex -> empty (no lonely 'Cx idle')" || bad "lonely idle" "$o"

fake 240   # Codex-only config (no 5h/7d) keeps standalone 'Cx idle' even without rate_limits
o=$(printf '%s' '{}' | run CC_USAGE_SEGMENTS='cx5h,cx7d' CC_USAGE_CODEX_DIR="$TMP/cx")
has "Cx idle" "$o" && ok "Codex-only + stale -> standalone 'Cx idle' kept" || bad "codex-only idle" "$o"

e=$(printf '%s' "$CC" | run CC_USAGE_DEBUG=1 2>&1 >/dev/null)
{ has "[quotabar debug]" "$e" && has "rate_limits:" "$e"; } && ok "--debug dumps diagnostics to stderr" || bad "debug" "$e"

WARN=$'\033[38;2;198;156;43m'; CRIT=$'\033[38;2;188;58;52m'   # deep gold/red bar fill (truecolor); NO_COLOR= forces color on
o=$(printf '%s' "$CC" | env NO_COLOR= CC_USAGE_CACHE_TTL=0 CC_USAGE_CONFIG=/dev/null CC_USAGE_SEGMENTS=7d bash "$SL")   # 74% -> warn
has "$WARN" "$o" && ok "past WARN -> deep gold bar" || bad "warn color" "$o"
o=$(printf '%s' "$CC" | env NO_COLOR= CC_USAGE_CACHE_TTL=0 CC_USAGE_CONFIG=/dev/null CC_USAGE_SEGMENTS=5h bash "$SL")   # 15% -> neutral
{ ! has "$WARN" "$o" && ! has "$CRIT" "$o"; } && ok "below WARN -> neutral bar (no warn/crit color)" || bad "low neutral" "$o"
o=$(printf '%s' "$CC" | env NO_COLOR= CC_USAGE_CACHE_TTL=0 CC_USAGE_CONFIG=/dev/null CC_USAGE_SEGMENTS=7d CC_USAGE_THRESHOLD=off bash "$SL")
{ ! has "$WARN" "$o"; } && ok "threshold=off -> no level color" || bad "threshold off" "$o"

rm -rf "$TMP/cxbig"; mkdir -p "$TMP/cxbig/2026/06/16"
node -e 'const fs=require("fs");const line=JSON.stringify({timestamp:new Date().toISOString(),payload:{rate_limits:{primary:{used_percent:42,resets_at:'$FUT'},secondary:{used_percent:42,resets_at:'$FUT'}}}});const pad=JSON.stringify({payload:{blob:"x".repeat(300000)}});fs.writeFileSync(process.argv[1],line+"\n"+pad+"\n")' "$TMP/cxbig/2026/06/16/rollout-b.jsonl"
o=$(printf '%s' "$CC" | run CC_USAGE_SEGMENTS=cx5h CC_USAGE_CODEX_DIR="$TMP/cxbig")
has "Cx 5h" "$o" && ok "large Codex session (>256KB after) -> rate_limits still found" || bad "codex big file" "$o"

o=$(printf '%s' "$CC" | run CC_USAGE_SEGMENTS=5h,sep,7d)
has "│" "$o" && ok "sep -> divider │" || bad "sep divider" "$o"

o=$(printf '%s' "$CC" | run COLUMNS=200 CC_USAGE_SEGMENTS=5h CC_USAGE_SEGMENTS_WIDE=5h,sep,7d CC_USAGE_WIDE_AT=120)
has "│" "$o" && ok "wide terminal -> WIDE layout" || bad "responsive wide" "$o"
o=$(printf '%s' "$CC" | run COLUMNS=80 CC_USAGE_SEGMENTS=5h CC_USAGE_SEGMENTS_WIDE=5h,sep,7d CC_USAGE_WIDE_AT=120)
{ ! has "│" "$o"; } && ok "narrow terminal -> base layout" || bad "responsive narrow" "$o"

# empty output must NOT be cached: first-session (no rate_limits) then data arrives
# within TTL -> bars show immediately, not a cached blank held for TTL seconds.
CDIR="$TMP/cache"; rm -rf "$CDIR"
crun(){ env XDG_CACHE_HOME="$CDIR" CC_USAGE_CACHE_TTL=5 CC_USAGE_CONFIG=/dev/null CC_USAGE_SEGMENTS=5h NO_COLOR=1 bash "$SL"; }
printf '%s' '{"session_id":"q"}' | crun >/dev/null
o=$(printf '%s' '{"session_id":"q","rate_limits":{"five_hour":{"used_percentage":12,"resets_at":'$FUT'}}}' | crun)
has "12%" "$o" && ok "empty output not cached -> normalizes instantly within TTL" || bad "empty cached" "$o"

# update notifier (opt-in). default off: no upgrade marker.
o=$(printf '%s' "$CC" | run CC_USAGE_SEGMENTS=5h)
{ ! has "⬆" "$o"; } && ok "update off (default) -> no ⬆ marker" || bad "update default" "$o"

# update available flag -> shows '⬆ vX' marker
UDIR="$TMP/upd"; rm -rf "$UDIR"; mkdir -p "$UDIR/quotabar"
printf '%s\n' "$(date +%s)" > "$UDIR/quotabar/.update-check"   # recent -> no background check
printf '9.9.9\n' > "$UDIR/quotabar/.update-available"
o=$(printf '%s' "$CC" | env XDG_CACHE_HOME="$UDIR" CC_USAGE_CACHE_TTL=0 CC_USAGE_CONFIG=/dev/null CC_USAGE_SEGMENTS=5h NO_COLOR=1 CC_USAGE_UPDATE=on bash "$SL")
has "⬆ v9.9.9" "$o" && ok "update available -> shows '⬆ v9.9.9'" || bad "update marker" "$o"

# regression: a recent .update-check WITHOUT trailing newline must still throttle
# (read returns 1 on no-newline EOF; a bad '|| _ul=0' would refire every render and rewrite the file).
TDIR="$TMP/throttle"; rm -rf "$TDIR"; mkdir -p "$TDIR/quotabar"
stamp="$(date +%s)"; printf '%s' "$stamp" > "$TDIR/quotabar/.update-check"   # NO newline, recent
printf '%s' "$CC" | env XDG_CACHE_HOME="$TDIR" CC_USAGE_CACHE_TTL=0 CC_USAGE_CONFIG=/dev/null CC_USAGE_SEGMENTS=5h NO_COLOR=1 CC_USAGE_UPDATE=on bash "$SL" >/dev/null
after="$(cat "$TDIR/quotabar/.update-check")"
[ "$after" = "$stamp" ] && ok "throttle holds on no-newline timestamp (no per-render refire)" || bad "throttle refire" "got:|$after| want:|$stamp|"

# CC_USAGE_UPDATE_DAYS controls the interval (hermetic: fake curl on PATH so no network fires).
FB="$TMP/fakebin"; mkdir -p "$FB"; printf '#!/bin/sh\nexit 1\n' > "$FB/curl"; chmod +x "$FB/curl"
krun(){ env PATH="$FB:$PATH" XDG_CACHE_HOME="$KDIR" CC_USAGE_CACHE_TTL=0 CC_USAGE_CONFIG=/dev/null CC_USAGE_SEGMENTS=5h NO_COLOR=1 CC_USAGE_UPDATE=on "$@" bash "$SL"; }
# stamp 3 days old; checking-on-fire rewrites .update-check to ~now (parent does this synchronously before the bg curl)
KDIR="$TMP/days7"; rm -rf "$KDIR"; mkdir -p "$KDIR/quotabar"; old=$(( $(date +%s) - 3*86400 )); printf '%s\n' "$old" > "$KDIR/quotabar/.update-check"
printf '%s' "$CC" | krun CC_USAGE_UPDATE_DAYS=7 >/dev/null
[ "$(cat "$KDIR/quotabar/.update-check")" = "$old" ] && ok "UPDATE_DAYS=7 -> 3-day-old check does NOT refire" || bad "days7 refire" "rewrote"
KDIR="$TMP/days1"; rm -rf "$KDIR"; mkdir -p "$KDIR/quotabar"; printf '%s\n' "$old" > "$KDIR/quotabar/.update-check"
printf '%s' "$CC" | krun CC_USAGE_UPDATE_DAYS=1 >/dev/null
[ "$(cat "$KDIR/quotabar/.update-check")" != "$old" ] && ok "UPDATE_DAYS=1 -> 3-day-old check DOES refire" || bad "days1 no refire" "unchanged"

# false-like values must NOT enable the notifier (only explicit truthy on/1/true/yes)
FUDIR="$TMP/falseupd"; rm -rf "$FUDIR"; mkdir -p "$FUDIR/quotabar"
printf '%s\n' "$(date +%s)" > "$FUDIR/quotabar/.update-check"; printf '9.9.9\n' > "$FUDIR/quotabar/.update-available"
o=$(printf '%s' "$CC" | env XDG_CACHE_HOME="$FUDIR" CC_USAGE_CACHE_TTL=0 CC_USAGE_CONFIG=/dev/null CC_USAGE_SEGMENTS=5h NO_COLOR=1 CC_USAGE_UPDATE=false bash "$SL")
{ ! has "⬆" "$o"; } && ok "CC_USAGE_UPDATE=false -> treated as off (no ⬆)" || bad "false enables" "$o"

# CC_USAGE_DEBUG must not flag the new update keys as unknown typos (recent stamp -> no network)
DDIR="$TMP/dbg"; rm -rf "$DDIR"; mkdir -p "$DDIR/quotabar"; printf '%s\n' "$(date +%s)" > "$DDIR/quotabar/.update-check"
e=$(printf '%s' "$CC" | env XDG_CACHE_HOME="$DDIR" CC_USAGE_CACHE_TTL=0 CC_USAGE_CONFIG=/dev/null CC_USAGE_SEGMENTS=5h NO_COLOR=1 CC_USAGE_DEBUG=1 CC_USAGE_UPDATE=on CC_USAGE_UPDATE_DAYS=7 bash "$SL" 2>&1 >/dev/null)
{ ! has "unknown CC_USAGE_* keys" "$e"; } && ok "debug: update keys not flagged as unknown" || bad "debug unknown keys" "$e"

# unwritable cache must not leak shell redirection errors to stderr (read-only cache dir)
RODIR="$TMP/ro"; rm -rf "$RODIR"; mkdir -p "$RODIR/quotabar"; chmod 555 "$RODIR/quotabar"
e=$(printf '%s' "$CC" | env XDG_CACHE_HOME="$RODIR" CC_USAGE_CACHE_TTL=0 CC_USAGE_CONFIG=/dev/null CC_USAGE_SEGMENTS=5h NO_COLOR=1 CC_USAGE_UPDATE=on bash "$SL" 2>&1 >/dev/null)
chmod 755 "$RODIR/quotabar" 2>/dev/null
{ ! has "Permission denied" "$e" && ! has "Read-only" "$e"; } && ok "unwritable cache -> no stderr leak from update stamp" || bad "stderr leak" "$e"

# a stale .update-available equal to the running version must NOT show ⬆ (and gets cleared)
VDIR="$TMP/staleupd"; rm -rf "$VDIR"; mkdir -p "$VDIR/quotabar"
selfver=$(sed -n 's/^VER="\([0-9.]*\)".*/\1/p' "$SL")
printf '%s\n' "$(date +%s)" > "$VDIR/quotabar/.update-check"; printf '%s\n' "$selfver" > "$VDIR/quotabar/.update-available"
o=$(printf '%s' "$CC" | env XDG_CACHE_HOME="$VDIR" CC_USAGE_CACHE_TTL=0 CC_USAGE_CONFIG=/dev/null CC_USAGE_SEGMENTS=5h NO_COLOR=1 CC_USAGE_UPDATE=on bash "$SL")
{ ! has "⬆" "$o" && [ ! -f "$VDIR/quotabar/.update-available" ]; } && ok "stale update marker (== current version) hidden and cleared" || bad "stale marker shown" "$o"

# an OLDER cached version than the running one must NOT show (no downgrade prompt)
ODIR="$TMP/oldupd"; rm -rf "$ODIR"; mkdir -p "$ODIR/quotabar"
printf '%s\n' "$(date +%s)" > "$ODIR/quotabar/.update-check"; printf '0.0.1\n' > "$ODIR/quotabar/.update-available"
o=$(printf '%s' "$CC" | env XDG_CACHE_HOME="$ODIR" CC_USAGE_CACHE_TTL=0 CC_USAGE_CONFIG=/dev/null CC_USAGE_SEGMENTS=5h NO_COLOR=1 CC_USAGE_UPDATE=on bash "$SL")
{ ! has "⬆" "$o"; } && ok "older cached version -> no downgrade ⬆ prompt" || bad "downgrade shown" "$o"

# --- context-as-fraction + effort segment (+ purple gradient at max) ---
o=$(printf '%s' '{"context_window":{"total_input_tokens":396176,"context_window_size":1000000,"used_percentage":40}}' | run CC_USAGE_SEGMENTS=ctx)
{ has "396k/1M" "$o" && ! has "%" "$o" && ! has "▰" "$o"; } && ok "ctx -> token fraction 396k/1M (no bar/%)" || bad "ctx fraction" "$o"

o=$(printf '%s' '{"context_window":{"used_percentage":40}}' | run CC_USAGE_SEGMENTS=ctx)
has "40%" "$o" && ok "ctx -> falls back to % when token fields absent" || bad "ctx fallback" "$o"

o=$(printf '%s' '{"effort":{"level":"xhigh"}}' | run CC_USAGE_SEGMENTS=effort)
has "xhigh effort" "$o" && ok "effort -> '<level> effort'" || bad "effort text" "$o"

# purple gradient only when effort=max (color ON)
grun(){ env NO_COLOR= CC_USAGE_CACHE_TTL=0 CC_USAGE_CONFIG=/dev/null CC_USAGE_SEGMENTS=effort bash "$SL"; }   # NO_COLOR= forces color on (hermetic)
o=$(printf '%s' '{"effort":{"level":"max"}}' | grun)
has "38;2;203;166;247" "$o" && ok "effort=max -> purple gradient" || bad "max gradient" "$o"
o=$(printf '%s' '{"effort":{"level":"xhigh"}}' | grun)
{ ! has "38;2;" "$o"; } && ok "effort=xhigh -> no gradient (plain dim)" || bad "xhigh gradient leak" "$o"

# ctx with zero usage (session start) is hidden, not a spurious "0/1M"
o=$(printf '%s' '{"context_window":{"total_input_tokens":0,"context_window_size":1000000,"used_percentage":0}}' | run CC_USAGE_SEGMENTS=ctx)
[ -z "$o" ] && ok "ctx -> hidden at zero usage (no spurious 0/1M)" || bad "ctx zero shown" "$o"

# session start / long idle: CC configured but rate_limits absent -> blank (no lonely model/Cx/effort)
o=$(printf '%s' '{"model":{"display_name":"Opus 4.8"},"effort":{"level":"max"},"context_window":{"total_input_tokens":5000,"context_window_size":1000000}}' | run CC_USAGE_SEGMENTS='5h,7d;cx5h,cx7d;model,effort,ctx')
[ -z "$o" ] && ok "CC not-ready (start/idle) -> blank (nothing lonely)" || bad "not-ready blank" "$o"

# stale Codex on a one-line divider layout: 'Cx idle' renders IN PLACE (between dividers), no doubled '│ │'
fake 240
o=$(printf '%s' "$CC" | run CC_USAGE_SEGMENTS='5h,7d,sep,cx5h,cx7d,sep,model' CC_USAGE_CODEX_DIR="$TMP/cx")
{ has "Cx idle" "$o" && ! has "│  │" "$o"; } && ok "stale Codex (divider layout) -> 'Cx idle' in place, no double divider" || bad "stale divider" "$o"

# empty cx segments must not leave a dangling/double divider (no Codex data)
o=$(printf '%s' "$CC" | run CC_USAGE_SEGMENTS='5h,7d,sep,cx5h,cx7d,sep,model' CC_USAGE_CODEX_DIR="$TMP/none")
{ ! has "│  │" "$o"; } && ok "absent cx -> divider cleanup (no doubled │)" || bad "double divider" "$o"

# ===== standalone mode (--standalone / --tmux) + symmetric CC snapshot =====
ESC=$'\033'
SC="$TMP/scache"   # hermetic cache namespace (controls the CC snapshot)
srun(){ env XDG_CACHE_HOME="$SC" NO_COLOR=1 CC_USAGE_CACHE_TTL=0 CC_USAGE_CONFIG=/dev/null CC_USAGE_CODEX_DIR="$TMP/cx" "$@" bash "$SL" --standalone </dev/null; }
# plant a CC snapshot $1 minutes old (33% / 77%)
ccsnap(){ mkdir -p "$SC/quotabar"; node -e 'const fs=require("fs");fs.writeFileSync(process.argv[1],JSON.stringify({five_hour:{used_percentage:33,resets_at:'$FUT'},seven_day:{used_percentage:77,resets_at:'$FUT'},ts:Date.now()-(+process.argv[2])*60000}))' "$SC/quotabar/cc-limits.json" "$1"; }

# Codex fresh, no CC snapshot -> Codex only (CC segments cleaned away, no dangling divider)
rm -rf "$SC"; fake 5
o=$(srun)
{ has "Cx 5h" "$o" && ! has "CC" "$o" && ! has "│" "$o"; } && ok "standalone: Codex only when no CC snapshot" || bad "standalone codex-only" "$o"

# standalone must NOT read stdin: CC comes from snapshot, never the piped JSON
rm -rf "$SC"; fake 5
o=$(printf '%s' "$CC" | env XDG_CACHE_HOME="$SC" NO_COLOR=1 CC_USAGE_CACHE_TTL=0 CC_USAGE_CONFIG=/dev/null CC_USAGE_CODEX_DIR="$TMP/cx" bash "$SL" --standalone)
{ has "Cx 5h" "$o" && ! has "74%" "$o"; } && ok "standalone ignores stdin (CC not from piped JSON)" || bad "standalone stdin leak" "$o"

# CC mode writes the snapshot file (so standalone can read it later)
rm -rf "$SC"
printf '%s' "$CC" | env XDG_CACHE_HOME="$SC" CC_USAGE_CACHE_TTL=0 CC_USAGE_CONFIG=/dev/null NO_COLOR=1 CC_USAGE_SEGMENTS=5h,7d bash "$SL" >/dev/null
{ [ -f "$SC/quotabar/cc-limits.json" ] && has '"five_hour"' "$(cat "$SC/quotabar/cc-limits.json")"; } && ok "CC mode writes cc-limits snapshot" || bad "snapshot not written" "$(ls "$SC/quotabar" 2>&1)"

# symmetric: fresh CC snapshot + fresh Codex -> BOTH show in standalone (divider between)
rm -rf "$SC"; fake 5; ccsnap 0
o=$(srun)
{ has "CC 5h" "$o" && has "33%" "$o" && has "Cx 5h" "$o" && has "│" "$o"; } && ok "standalone: CC(snapshot) + Codex(files) both shown (symmetric)" || bad "standalone both" "$o"

# stale CC snapshot -> CC hidden, Codex still shows (divider cleaned)
rm -rf "$SC"; fake 5; ccsnap 99
o=$(srun CC_USAGE_STALE_MIN=30)
{ ! has "CC" "$o" && has "Cx 5h" "$o" && ! has "│" "$o"; } && ok "standalone: stale CC snapshot hidden" || bad "standalone stale CC" "$o"

# stale Codex + no CC snapshot -> empty (disappears)
rm -rf "$SC"; fake 240
o=$(srun)
{ [ -z "$o" ]; } && ok "standalone + stale Codex + no CC -> empty (disappears)" || bad "standalone empty" "$o"

# --tmux -> tmux #[fg=...] markup, NO raw ANSI escape (color ON; both providers)
rm -rf "$SC"; fake 5; ccsnap 0
o=$(env XDG_CACHE_HOME="$SC" NO_COLOR= CC_USAGE_CACHE_TTL=0 CC_USAGE_CONFIG=/dev/null CC_USAGE_CODEX_DIR="$TMP/cx" bash "$SL" --standalone --tmux </dev/null)
{ has "#[fg=" "$o" && ! has "$ESC" "$o"; } && ok "standalone --tmux -> #[fg=...] markup, no raw ESC" || bad "tmux markup" "$o"

# standalone suppresses the update hint (else empty-on-idle is defeated)
rm -rf "$SC"; mkdir -p "$SC/quotabar"; fake 5
printf '%s\n' "$(date +%s)" > "$SC/quotabar/.update-check"; printf '9.9.9\n' > "$SC/quotabar/.update-available"
o=$(env XDG_CACHE_HOME="$SC" NO_COLOR=1 CC_USAGE_CACHE_TTL=0 CC_USAGE_CONFIG=/dev/null CC_USAGE_CODEX_DIR="$TMP/cx" CC_USAGE_UPDATE=on bash "$SL" --standalone </dev/null)
{ ! has "⬆" "$o"; } && ok "standalone -> update hint suppressed" || bad "standalone upd hint leak" "$o"

# --watch: foreground loop renders standalone in place, never reads stdin, and is terminable.
rm -rf "$SC"; fake 5
o=$(env XDG_CACHE_HOME="$SC" NO_COLOR=1 CC_USAGE_CACHE_TTL=0 CC_USAGE_CONFIG=/dev/null CC_USAGE_CODEX_DIR="$TMP/cx" CC_USAGE_WATCH_SECS=1 timeout 2 bash "$SL" --watch </dev/null 2>&1); rc=$?
{ { [ "$rc" -eq 124 ] || [ "$rc" -eq 0 ]; } && has $'\r\033[K' "$o" && has "Cx 5h" "$o"; } && ok "--watch -> in-place standalone render, terminable" || bad "watch" "rc=$rc out=$o"

# debug: mode line (with ccSnapAge) + STANDALONE/TMUX not flagged as unknown keys
rm -rf "$SC"; fake 5; ccsnap 0
e=$(env XDG_CACHE_HOME="$SC" NO_COLOR=1 CC_USAGE_CACHE_TTL=0 CC_USAGE_CONFIG=/dev/null CC_USAGE_CODEX_DIR="$TMP/cx" CC_USAGE_DEBUG=1 bash "$SL" --standalone --tmux </dev/null 2>&1 >/dev/null)
{ has "mode: standalone=true" "$e" && has "ccSnapAgeMin=" "$e" && ! has "unknown CC_USAGE_* keys" "$e"; } && ok "standalone --debug: mode line + ccSnapAge + no unknown-key warning" || bad "standalone debug" "$e"

# --setup: env-aware setup helper. tmux present -> tmux config; absent -> install advice.
YB="$TMP/yestmux"; mkdir -p "$YB"; printf '#!/bin/sh\n' > "$YB/tmux"; chmod +x "$YB/tmux"
o=$(PATH="$YB:$PATH" bash "$SL" --setup 2>&1)
{ has "status-right" "$o" && has "standalone" "$o"; } && ok "--setup (tmux present) -> tmux status-right config" || bad "setup tmux-present" "$o"
NB="$TMP/notmux"; mkdir -p "$NB"; ln -sf "$(command -v find)" "$NB/" 2>/dev/null
o=$(PATH="$NB" /bin/bash "$SL" --setup 2>&1)
{ has "install tmux" "$o" && ! has "status-right" "$o"; } && ok "--setup (no tmux) -> recommends installing tmux" || bad "setup no-tmux" "$o"

# B: CC_USAGE_TMUX_DEDUP — in tmux ($TMUX set) the CC statusline drops quota (tmux bar shows it); plain terminal keeps full
CCM='{"session_id":"t","rate_limits":{"five_hour":{"used_percentage":16,"resets_at":'$FUT'}},"model":{"display_name":"Opus 4.8"}}'
o=$(printf '%s' "$CCM" | env NO_COLOR=1 CC_USAGE_CACHE_TTL=0 CC_USAGE_CONFIG=/dev/null CC_USAGE_SEGMENTS=5h,model TMUX=/tmp/x CC_USAGE_TMUX_DEDUP=on bash "$SL")
{ ! has "16%" "$o" && has "Opus" "$o"; } && ok "tmux dedup ON + in tmux -> quota dropped, session info kept" || bad "dedup in-tmux" "$o"
o=$(printf '%s' "$CCM" | env -u TMUX NO_COLOR=1 CC_USAGE_CACHE_TTL=0 CC_USAGE_CONFIG=/dev/null CC_USAGE_SEGMENTS=5h,model CC_USAGE_TMUX_DEDUP=on bash "$SL")
has "16%" "$o" && ok "tmux dedup ON + plain terminal -> full (quota kept)" || bad "dedup plain" "$o"
o=$(printf '%s' "$CCM" | env NO_COLOR=1 CC_USAGE_CACHE_TTL=0 CC_USAGE_CONFIG=/dev/null CC_USAGE_SEGMENTS=5h,model TMUX=/tmp/x bash "$SL")
has "16%" "$o" && ok "tmux dedup OFF (default) -> full even in tmux" || bad "dedup off default" "$o"

# guard: the node -e '...' script must contain NO single quotes (a stray ' breaks the bash wrapper -> empty output)
inner=$(awk '/\| node -e/{f=1;next} f&&$0=="\x27)"{f=0} f' "$SL")
{ ! printf '%s' "$inner" | grep -q "'"; } && ok "node -e block has no stray single quotes (bash wrapper intact)" || bad "stray single quote in node block" "$(printf '%s' "$inner" | grep -n "'" | head -3)"

echo ""
printf "%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
