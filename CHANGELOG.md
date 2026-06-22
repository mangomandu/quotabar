# Changelog

## v1.2.5

**install.sh** — follow-up hardening from a second review of the v1.2.4 changes.
- The wired `statusLine.command` now POSIX single-quotes the script path
  (`bash -- '<path>'`), so a path with spaces, `$`, backticks, `"`, or `'` can't be
  reinterpreted by the shell when Claude Code runs it.
- Re-running the installer **migrates** the older unquoted (`bash <path>`) and interim
  double-quoted (`bash "<path>"`) commands to the safe form, instead of refusing them
  as "a different statusLine" and forcing a manual edit.

## v1.2.4

Bug-fix pass from a second Codex audit.

**Fixed**
- Codex bars no longer blank when you start a fresh Codex session: rollout files are
  scanned newest-first and quotabar uses the most recent one that actually carries a
  `rate_limits` event (up to the 8 newest), instead of only reading the single newest
  file — which a brand-new session leaves without limits yet, hiding the prior session's.
- `--update` now runs `bash -n` on the downloaded file before replacing itself, so a
  download truncated mid-script (which still has the version header) can't clobber the
  installed copy.
- A successful render can no longer exit non-zero: an unwritable cache dir produced
  correct output but a failing exit status.
- `EPOCHSECONDS` is trusted only on bash 5+ (where it's a dynamic builtin); on older
  bash — where a same-named env var would be a frozen value — it falls back to `date`,
  so TTL/throttle math can't freeze.

**install.sh**
- Downloads land in a temp file and are validated before an atomic rename, so an
  interrupted transfer can't leave a truncated `statusline.sh` or a partial config.
- A `settings.json` that exists but isn't valid JSON is left untouched (it used to be
  silently overwritten with a fresh `{}`, discarding the user's settings).
- The wired `statusLine.command` quotes the script path, so a config dir containing
  spaces still works.

**Quality**
- Test suite at **52 assertions** (added the multi-rollout fallback regression).

## v1.2.3

**Changed**
- Cache-hit render is now fork-free where the shell allows it: stdin is read with
  `$(</dev/stdin)` and the cache file with `$(<file)` (no `cat`), and the time check
  uses the `EPOCHSECONDS` builtin (bash 5+) with a `date` fallback — so the common
  path spawns no helper processes on a modern bash (and one fewer everywhere else).
  Output is byte-identical to before.

**Added**
- `--update` now verifies the downloaded file actually carries the `# quotabar v…`
  header before overwriting itself — a 404 page or truncated download can no longer
  clobber the installed script.
- `CC_USAGE_DEBUG` warns when a Codex rollout file is found but no `rate_limits`
  could be parsed (an early signal that Codex changed its session format), instead
  of silently showing empty Codex bars.

**Quality**
- Test suite at **51 assertions** (was 41): added a `node --check` syntax guard for
  the inline program, plus coverage for `RESET=clock`/`both`, custom `CC_USAGE_BARS`
  width, the reset countdown, multi-row (`;`) layout, `cost` as a number, tag colors
  (named + `#hex`), and the new Codex format guard.
- CI: GitHub Actions runs `bash test.sh` on Linux and macOS for every push/PR.

## v1.2.2

**Changed**
- Layout-aware spacing: the one-line (wide) layout is tighter — single spaces around
  bars and no `%` padding — while the multi-row layout keeps its wider spacing and an
  aligned `%` column. (Pure formatting; no render-cost change.)

## v1.2.1

**Changed**
- When Claude Code hasn't provided `rate_limits` — at session start, or after a long
  idle when the session goes cold — the statusline now goes **fully blank** instead of
  showing a lone model name. It repopulates the instant activity resumes (empty output
  isn't cached, so no lag).

## v1.2.0

**Added**
- `effort` segment — shows `<level> effort` (Claude Code's reasoning-effort level); when
  the level is `max`, the word `max` gets a subtle purple gradient.
- `ctx` reads `context_window` token counts: shows a compact fraction like `544k/1M`
  (used / window) instead of bar+%, hidden at zero usage (no spurious `0/1M` at session
  start). Falls back to `%` when token fields are absent.

**Changed**
- Bar fill: deeper, less-garish gold (warn) / red (crit) truecolor instead of bright ANSI.
- Session start (before `rate_limits` arrives): show only the model name (if configured)
  rather than a partial, cluttered line — the full statusline appears once data is ready.
- Stale Codex renders `Cx idle` **in place** (where the Cx segment sits), not appended to
  the line end — so it works in one-line / divider layouts.
- Dividers self-clean: leading/trailing/consecutive `│` are dropped, so an empty Codex
  slot no longer leaves a dangling or doubled divider.

**Quality**
- 41-assertion test suite, incl. a guard that the `node -e` script carries no stray single
  quotes (which would silently break the bash wrapper and blank the statusline).
- Verdikt: render cost unchanged at cache hit (common path runs identical code), +0.34 ms
  at cache miss. Codex review: clean.

## v1.1.0

**Added**
- Optional update notifier (`CC_USAGE_UPDATE=on`, default **off**). When on, quotabar
  checks GitHub for a newer version at most once every `CC_USAGE_UPDATE_DAYS` days
  (default **7**) — in a detached background process that never blocks the render —
  and appends a compact `⬆ vX.Y.Z` marker when one is available.
- `statusline.sh --update` — manual one-shot self-update (downloads the latest over
  itself; works any time, no notifier needed).

**Performance (Verdikt-gated)**
- Default (off): **+0.05 ms** vs v1.0.2 — effectively zero; non-users pay nothing.
- Turned on: **+0.13 ms** steady-state render (within a 1.0 ms non-inferiority margin
  on 100% of 80 sealed-holdout paired renders). The hot path is a single timestamp
  read — render cost is independent of the check interval; only one detached request
  fires per interval. A first cut accidentally refired the background check every
  render (a `read` no-newline-EOF gotcha); Verdikt caught it (+1.9 ms → FAIL) before ship.
- Test suite at 31 assertions (incl. throttle, interval, and truthy-gate regression guards).

## v1.0.2

**Fixed**
- Empty output is no longer cached. A first-session blank (before `rate_limits`
  arrives) used to be held for the cache TTL, delaying the bars by up to ~2s after
  the first message. Now blanks skip the cache, so the statusline normalizes the
  instant data arrives. (Builds on the v1.0.1 lonely-`Cx idle` fix.)

**Quality**
- Adversarial pass: ANSI/control-char injection (model/cost/tag), session-id path
  traversal, and config `eval` injection all confirmed blocked; malformed/empty
  JSON and out-of-range inputs degrade without crashing. Test suite at 21 assertions.

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
- 18-assertion test suite (`test.sh`); `CC_USAGE_DEBUG` / `--debug` diagnostics.
- Audited three independent ways: an adversarial review agent, OpenAI Codex, and Verdikt.
