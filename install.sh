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

echo "→ Downloading statusline.sh"
curl -fsSL "$RAW/statusline.sh" -o "$HOOKS/statusline.sh"
chmod +x "$HOOKS/statusline.sh"

if [ ! -f "$CLAUDE_DIR/cc-usage.conf" ]; then
  echo "→ Installing default config"
  curl -fsSL "$RAW/cc-usage.conf" -o "$CLAUDE_DIR/cc-usage.conf"
else
  echo "→ Keeping your existing $CLAUDE_DIR/cc-usage.conf"
fi

SETTINGS="$CLAUDE_DIR/settings.json"
[ -f "$SETTINGS" ] && cp "$SETTINGS" "$SETTINGS.bak.$(date +%s 2>/dev/null || echo bak)" 2>/dev/null || true

node -e '
const fs=require("fs");
const p=process.argv[1], cmd=process.argv[2];
let s={};
try{ s=JSON.parse(fs.readFileSync(p,"utf8")) }catch(e){}
if(s.statusLine && s.statusLine.command && s.statusLine.command!==cmd){
  console.log("! settings.json already has a different statusLine. Left it unchanged.");
  console.log("  To use this one, set statusLine.command to:\n    "+cmd);
} else {
  s.statusLine={type:"command", command:cmd, padding:0};
  fs.writeFileSync(p, JSON.stringify(s,null,2)+"\n");
  console.log("✓ statusLine wired up in "+p);
}
' "$SETTINGS" "bash $HOOKS/statusline.sh"

echo ""
echo "✓ Done. Open a new Claude Code session (or refresh) to see it."
echo "  Customize: edit $CLAUDE_DIR/cc-usage.conf"
