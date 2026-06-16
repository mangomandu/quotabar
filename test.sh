#!/usr/bin/env bash
# quotabar test suite — feeds crafted JSON to statusline.sh and checks output.
# Run:  bash test.sh        (needs bash + node)
SL="$(cd "$(dirname "$0")" && pwd)/statusline.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
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

e=$(printf '%s' "$CC" | run CC_USAGE_DEBUG=1 2>&1 >/dev/null)
{ has "[quotabar debug]" "$e" && has "rate_limits:" "$e"; } && ok "--debug dumps diagnostics to stderr" || bad "debug" "$e"

GREEN=$'\033[32m'; YEL=$'\033[33m'
o=$(printf '%s' "$CC" | env CC_USAGE_CACHE_TTL=0 CC_USAGE_CONFIG=/dev/null CC_USAGE_SEGMENTS=7d bash "$SL")   # 74%
has "$YEL" "$o" && ok "past WARN -> yellow bar" || bad "warn color" "$o"
o=$(printf '%s' "$CC" | env CC_USAGE_CACHE_TTL=0 CC_USAGE_CONFIG=/dev/null CC_USAGE_SEGMENTS=5h bash "$SL")   # 15%
{ ! has "$GREEN" "$o" && ! has "$YEL" "$o"; } && ok "below WARN -> neutral bar (no green/yellow)" || bad "low neutral" "$o"
o=$(printf '%s' "$CC" | env CC_USAGE_CACHE_TTL=0 CC_USAGE_CONFIG=/dev/null CC_USAGE_SEGMENTS=7d CC_USAGE_THRESHOLD=off bash "$SL")
{ ! has "$YEL" "$o"; } && ok "threshold=off -> no level color" || bad "threshold off" "$o"

rm -rf "$TMP/cxbig"; mkdir -p "$TMP/cxbig/2026/06/16"
node -e 'const fs=require("fs");const line=JSON.stringify({timestamp:new Date().toISOString(),payload:{rate_limits:{primary:{used_percent:42,resets_at:'$FUT'},secondary:{used_percent:42,resets_at:'$FUT'}}}});const pad=JSON.stringify({payload:{blob:"x".repeat(300000)}});fs.writeFileSync(process.argv[1],line+"\n"+pad+"\n")' "$TMP/cxbig/2026/06/16/rollout-b.jsonl"
o=$(printf '%s' "$CC" | run CC_USAGE_SEGMENTS=cx5h CC_USAGE_CODEX_DIR="$TMP/cxbig")
has "Cx 5h" "$o" && ok "large Codex session (>256KB after) -> rate_limits still found" || bad "codex big file" "$o"

o=$(printf '%s' "$CC" | run CC_USAGE_SEGMENTS=5h,sep,7d)
has "│" "$o" && ok "sep -> divider │" || bad "sep divider" "$o"

echo ""
printf "%d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
