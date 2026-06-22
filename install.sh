#!/usr/bin/env bash
# quotabar installer
#   curl -fsSL https://raw.githubusercontent.com/mangomandu/quotabar/main/install.sh | bash
# Copies the statusline script + a default config into your Claude Code dir,
# and adds a statusLine entry to settings.json (idempotent, backs up first).
set -euo pipefail

REPO="${CC_USAGE_REPO:-mangomandu/quotabar}"
BRANCH="${CC_USAGE_BRANCH:-main}"
RAW="https://raw.githubusercontent.com/$REPO/$BRANCH"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
HOOKS="$CLAUDE_DIR/hooks"

command -v node >/dev/null 2>&1 || { echo "✗ node is required (the statusline parses JSON with node). Install Node.js first."; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "✗ curl is required to download the files."; exit 1; }

mkdir -p "$HOOKS"

# Download into a temp file, validate, then atomically rename — so an interrupted/failed
# transfer can never leave a truncated live statusline.sh or a partial config behind.
echo "→ Downloading statusline.sh"
sl_tmp="$HOOKS/.statusline.sh.tmp.$$"
curl -fsSL "$RAW/statusline.sh" -o "$sl_tmp"
grep -q '^# quotabar v' "$sl_tmp" || { echo "✗ download looks corrupt (missing quotabar header) — aborting"; rm -f "$sl_tmp"; exit 1; }
chmod +x "$sl_tmp"
mv "$sl_tmp" "$HOOKS/statusline.sh"

if [ ! -f "$CLAUDE_DIR/cc-usage.conf" ]; then
  echo "→ Installing default config"
  cf_tmp="$CLAUDE_DIR/.cc-usage.conf.tmp.$$"
  curl -fsSL "$RAW/cc-usage.conf" -o "$cf_tmp"
  [ -s "$cf_tmp" ] || { echo "✗ config download failed — aborting"; rm -f "$cf_tmp"; exit 1; }
  mv "$cf_tmp" "$CLAUDE_DIR/cc-usage.conf"
else
  echo "→ Keeping your existing $CLAUDE_DIR/cc-usage.conf"
fi

SETTINGS="$CLAUDE_DIR/settings.json"
[ -f "$SETTINGS" ] && cp "$SETTINGS" "$SETTINGS.bak.$(date +%s 2>/dev/null || echo bak)" 2>/dev/null || true

node -e '
const fs=require("fs");
const p=process.argv[1], hook=process.argv[2];
// POSIX single-quote the path: handles spaces, $, backticks, ", and \ alike. `--` guards a leading dash.
const cmd="bash -- \x27"+hook.replace(/\x27/g,"\x27\\\x27\x27")+"\x27";
// commands we recognize as "ours" (so re-running migrates legacy forms instead of refusing): the new
// single-quoted form, the old unquoted `bash <path>`, and the interim double-quoted `bash "<path>"`.
const ours=[cmd, "bash "+hook, "bash \""+hook+"\""];
let s={};
try{ s=JSON.parse(fs.readFileSync(p,"utf8")) }
catch(e){
  if(e.code!=="ENOENT"){   // file exists but is not valid JSON (hand-edited?) -> never overwrite it
    console.log("! "+p+" exists but is not valid JSON — leaving it untouched.");
    console.log("  Add this statusLine entry yourself:\n    "+cmd);
    process.exit(0);
  }
}
const cur=s.statusLine && s.statusLine.command;
if(cur && ours.indexOf(cur)<0){
  console.log("! settings.json already has a different statusLine. Left it unchanged.");
  console.log("  To use this one, set statusLine.command to:\n    "+cmd);
} else {
  s.statusLine={type:"command", command:cmd, padding:0};
  fs.writeFileSync(p, JSON.stringify(s,null,2)+"\n");
  console.log("✓ statusLine wired up in "+p);
}
' "$SETTINGS" "$HOOKS/statusline.sh"

echo ""
echo "✓ Done. Open a new Claude Code session (or refresh) to see it."
echo "  Customize: edit $CLAUDE_DIR/cc-usage.conf"
