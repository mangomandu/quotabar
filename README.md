# quotabar

A tiny [Claude Code](https://claude.com/claude-code) statusline that shows your AI coding **usage limits** — the 5-hour and weekly quota you actually care about on flat-rate plans — as colored bars. It tracks **[Claude Code](https://claude.com/claude-code) and [Codex](https://github.com/openai/codex) side by side**, plus context %, model, and session cost.

> It installs as a Claude Code statusline (that's the host), and additionally reads Codex's local session data so both agents' limits show in one place.

No dependencies beyond `bash` + `node` (which Claude Code already needs). One file.

```
CC 5h  ▰▰▱▱▱▱▱▱▱▱   16%  · 3h08m   CC 7d  ▰▰▰▰▰▰▰▱▱▱   69%  · 1d7h
```

Run both Claude Code and Codex? Show them together:

```
✿ 5h  ▰▰▱▱▱▱▱▱▱▱   16%  · 3h08m   ✿ 7d  ▰▰▰▰▰▰▰▱▱▱   69%  · 1d7h     ← Claude Code
⬢ 5h  ▱▱▱▱▱▱▱▱▱▱    4%  · 2h45m   ⬢ 7d  ▰▰▱▱▱▱▱▱▱▱   16%  · 4d15h    ← Codex
```

Bars turn **yellow** past 50% and **red** past 80%.

## Why

`ccusage` and similar tools show the **dollar cost**. But on a flat-rate plan what bites you is the **limit %** and **when it resets** — and that data now arrives in the statusline's stdin. This shows exactly that, and is the only one that folds in Codex too.

## Requirements

- `bash` and `node` (Claude Code already uses Node)
- Works on Linux, macOS, and WSL

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/mangomandu/quotabar/main/install.sh | bash
```

This drops `statusline.sh` into `~/.claude/hooks/`, adds a default `~/.claude/cc-usage.conf`, and wires up `statusLine` in `~/.claude/settings.json` (backing it up first). Open a new Claude Code session to see it.

<details>
<summary>Manual install</summary>

1. Copy `statusline.sh` to `~/.claude/hooks/statusline.sh` (`chmod +x` it).
2. Copy `cc-usage.conf` to `~/.claude/cc-usage.conf`.
3. Add to `~/.claude/settings.json`:
   ```json
   "statusLine": { "type": "command", "command": "bash ~/.claude/hooks/statusline.sh", "padding": 0 }
   ```
</details>

## I only use Claude Code (no Codex)

Nothing to do — that's the default. You'll just see the two Claude Code rows (`5h`, `7d`); the Codex rows only appear if Codex session data exists on your machine. If you ever want to be explicit, keep this line in your config:

```
CC_USAGE_SEGMENTS=5h,7d
```

## Customize

Edit **one file** — `~/.claude/cc-usage.conf` (no JSON). One `KEY=value` per line; `#` starts a comment. Save, then trigger any statusline refresh (type a message) to apply. Every key can also be set as an environment variable, which takes precedence.

**What to show & layout — `CC_USAGE_SEGMENTS`**
`,` puts items on the same line, `;` starts a new line. Items: `5h 7d` (Claude Code), `cx5h cx7d` (Codex), `ctx`, `model`, `cost`.
```
CC_USAGE_SEGMENTS=5h,7d              # default: Claude Code on one line
CC_USAGE_SEGMENTS=5h,7d;cx5h,cx7d    # Claude Code row + Codex row
CC_USAGE_SEGMENTS=5h,7d;cx5h,cx7d;ctx,cost
```

**Labels — four free slots**
Head = `[provider tag] [window tag]`. Defaults are plain text; put any text or emoji.
```
CC_USAGE_TAG_CC=✿        # "CC" slot   (default: CC)
CC_USAGE_TAG_CX=⬢        # "Cx" slot   (default: Cx)
CC_USAGE_TAG_5H=⏳        # "5h" slot   (default: 5h)
CC_USAGE_TAG_7D=📅        # "7d" slot   (default: 7d)
CC_USAGE_TAGCOLOR_CC=orange   # color a monochrome symbol (✿ ⬢ ● ◆ …); name or 256-index
CC_USAGE_TAGCOLOR_CX=purple   # (color emoji like 🟧 ignore this — they carry their own color)
```

**Reset display — `CC_USAGE_RESET`**: `relative` (`4h00m`) · `clock` (`→18:40`) · `both`

**Appearance**: `CC_USAGE_BARS` (cells) · `CC_USAGE_WARN`/`CC_USAGE_CRIT` (% thresholds) · `CC_USAGE_STYLE=ascii` (bars as `#-`) · `NO_COLOR=1`

See [`cc-usage.conf`](./cc-usage.conf) for the annotated template.

## How it works

On each render Claude Code pipes a JSON blob to the statusline command. This script reads `rate_limits` (`five_hour` / `seven_day`, with `used_percentage` and an epoch `resets_at`), plus `context_window`, `cost`, and `model`. For Codex, it reads the newest session rollout under `~/.codex/sessions/**/rollout-*.jsonl` and pulls the last `rate_limits` event (`primary` = 5h, `secondary` = weekly). All rendering is done in an embedded `node` one-liner.

## Notes & limitations

- **Codex freshness**: Codex values reflect the last time Codex ran (that's when it writes the data). The reset countdown stays accurate; the % is last-known.
- **Terminal glyphs**: some terminals force emoji presentation on symbols like ☁, ignoring color. Stick to plain dingbats (`✿ ⬢ ● ◆`) for reliable custom colors, or use colored emoji squares (🟧 🟪).
- **Refresh cadence**: Claude Code re-runs the statusline on activity (throttled), so the % tracks near-real-time, not as a live ticking counter.

## License

MIT
