# Changelog

## v1.0.1

**Fixed**
- First session (before any message): Claude Code hasn't populated `rate_limits`
  yet, so the CC bars are empty — the stale-Codex collapse used to render a lonely
  `Cx idle` on its own line. Now suppressed when CC segments are configured but
  empty (normalizes on first input). Codex-only setups still show standalone `Cx idle`.

## v1.0.0

First stable release. A one-file (`bash` + `node`) Claude Code statusline for AI
coding **usage limits**, audited for security and per-render cost.

**Shows**
- Claude Code 5-hour & weekly rate limits, as colored bars with reset countdowns.
- Codex 5h / weekly limits read from the local session files, side by side.
- Optional: context %, model, session cost.

**Layout & looks**
- Ships configured for both providers by default — Claude Code + Codex, brand-colored (Claude terra cotta / Codex blue), two rows, collapsing to one line on wide terminals. Codex rows auto-hide when no Codex session data exists, so the default is safe for Claude-Code-only users.
- `CC_USAGE_SEGMENTS` with `,` (same line) / `;` (new line); items `5h 7d cx5h cx7d ctx model cost sep`.
- Responsive: `CC_USAGE_SEGMENTS_WIDE` + `CC_USAGE_WIDE_AT` switch layouts by terminal `COLUMNS`.
- Free-form labels (`CC_USAGE_TAG_*`) and tag colors (`CC_USAGE_TAGCOLOR_*`) — names, 256-index, `#hex`, `rgb()`; built-in `claude`/`codex` brand colors.
- Bars neutral → yellow past `WARN` → red past `CRIT`; `%` always white; `CC_USAGE_THRESHOLD=off` to disable; `ascii`/`NO_COLOR` modes.
- Reset as `relative` / `clock` / `both`; stale Codex collapses to `Cx idle` (`CC_USAGE_STALE_MIN`).

**Lightweight**
- Per-session output cache (`CC_USAGE_CACHE_TTL`): ~6 ms / cache hit (no Node), ~32 ms / miss.
- No daemon, no timer, no network. Verified ~5× lighter than `ccusage` (Verdikt: PASS, 100% of paired trials).

**Hardened**
- Config-loader `eval` cannot be injected (keys sanitized; values never eval'd).
- All rendered data stripped of terminal control chars (no ANSI/OSC injection).
- Symlink-safe Codex walk, sanitized cache paths, bounded reads / regexes / bar width / percent.

**Quality**
- 20-assertion test suite (`test.sh`); `CC_USAGE_DEBUG` / `--debug` diagnostics.
- Audited three independent ways: an adversarial review agent, OpenAI Codex, and Verdikt.
