---
name: quotabar
description: Install, update, troubleshoot, or customize quotabar, a Claude Code statusline that displays Claude Code and Codex usage limits.
---

# quotabar

Use this skill when the user asks about installing, updating, troubleshooting, or customizing
quotabar.

## What quotabar does

quotabar is a Claude Code statusline script. It displays Claude Code rate limits from the
statusline JSON piped on stdin, and Codex limits from local Codex session logs under
`~/.codex/sessions` by default.

It does not call external APIs while rendering the statusline.

## Install

Recommend the repository installer unless the user asks for manual setup:

```bash
curl -fsSL https://raw.githubusercontent.com/mangomandu/quotabar/main/install.sh | bash
```

The installer writes:

- `~/.claude/hooks/statusline.sh`
- `~/.claude/cc-usage.conf`
- a `statusLine` command in `~/.claude/settings.json`

After installing, the user should open a new Claude Code session or send a message so the
statusline refreshes.

## Manual Setup

If the user wants manual setup:

1. Copy `statusline.sh` to `~/.claude/hooks/statusline.sh`.
2. Run `chmod +x ~/.claude/hooks/statusline.sh`.
3. Copy `cc-usage.conf` to `~/.claude/cc-usage.conf`.
4. Add this to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/hooks/statusline.sh",
    "padding": 0
  }
}
```

## Troubleshooting

- If Codex rows do not appear, confirm Codex has run locally and has session files under
  `~/.codex/sessions`.
- If Codex values show `Cx idle`, Codex data is stale. Run Codex again or increase
  `CC_USAGE_STALE_MIN` in `~/.claude/cc-usage.conf`.
- If `node not found` appears, launch Claude Code so its bundled Node is on `PATH`, or install
  Node separately.
- If the statusline does not update, open a new Claude Code session or send a message to trigger a
  statusline render.

## Customization

The main config file is `~/.claude/cc-usage.conf`.

Common settings:

```bash
CC_USAGE_SEGMENTS=5h,7d;cx5h,cx7d
CC_USAGE_STALE_MIN=30
CC_USAGE_STYLE=unicode
```

Use `CC_USAGE_SEGMENTS` to choose which rows and fields are shown.
