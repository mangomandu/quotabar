#!/usr/bin/env bash
# quotabar test suite — feeds crafted JSON to statusline.sh and checks output.
# Run:  bash test.sh        (needs bash + node)
SL="$(cd "$(dirname "$0")" && pwd)/statusline.sh"
TMP="$(mktemp -d)" || { echo "cannot create temp dir (read-only FS?)"; exit 1; }
trap 'rm -rf "$TMP"' EXIT
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

# session start: rate_limits absent + model configured -> show ONLY the model
o=$(printf '%s' '{"model":{"display_name":"Opus 4.8"}}' | run CC_USAGE_SEGMENTS='5h,7d;cx5h,cx7d;model,effort,ctx')
{ has "Opus 4.8" "$o" && ! has "▰" "$o" && ! has "Cx" "$o"; } && ok "session start -> model only (no bars/Cx)" || bad "session start model" "$o"

# stale Codex on a one-line divider layout: 'Cx idle' renders IN PLACE (between dividers), no doubled '│ │'
fake 240
o=$(printf '%s' "$CC" | run CC_USAGE_SEGMENTS='5h,7d,sep,cx5h,cx7d,sep,model' CC_USAGE_CODEX_DIR="$TMP/cx")
{ has "Cx idle" "$o" && ! has "│   │" "$o"; } && ok "stale Codex (divider layout) -> 'Cx idle' in place, no double divider" || bad "stale divider" "$o"

# empty cx segments must not leave a dangling/double divider (no Codex data)
o=$(printf '%s' "$CC" | run CC_USAGE_SEGMENTS='5h,7d,sep,cx5h,cx7d,sep,model' CC_USAGE_CODEX_DIR="$TMP/none")
{ ! has "│   │" "$o"; } && ok "absent cx -> divider cleanup (no doubled │)" || bad "double divider" "$o"

# guard: the node -e '...' script must contain NO single quotes (a stray ' breaks the bash wrapper -> empty output)
inner=$(awk '/\| node -e/{f=1;next} f&&$0=="\x27)"{f=0} f' "$SL")
{ ! printf '%s' "$inner" | grep -q "'"; } && ok "node -e block has no stray single quotes (bash wrapper intact)" || bad "stray single quote in node block" "$(printf '%s' "$inner" | grep -n "'" | head -3)"

echo ""
printf "%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
