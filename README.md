<div align="center">

# quotabar

**Claude Code + Codex usage limits, right in your statusline.**

[English](./README.md) · [한국어](./README.ko.md)

<br>

![quotabar](./assets/demo.png)

<br>

![license MIT](https://img.shields.io/badge/license-MIT-d77757?style=flat-square)
![deps bash + node](https://img.shields.io/badge/deps-bash_%2B_node-5769f7?style=flat-square)
![cache hit ~6ms](https://img.shields.io/badge/cache_hit-~6ms_%2F_3.4MB-d77757?style=flat-square)
![audited 3 ways](https://img.shields.io/badge/audited-3_ways-5769f7?style=flat-square)

</div>

A tiny [Claude Code](https://claude.com/claude-code) statusline that shows the **usage limits** you actually watch on a flat-rate plan — your **5-hour** and **weekly** quota — as colored bars. It tracks **Claude Code and [Codex](https://github.com/openai/codex) side by side**, plus context %, model, and session cost.

**`bash` + `node` only** (Claude Code already ships Node) · **one file** · **no daemon** · **no network**.

```bash
curl -fsSL https://raw.githubusercontent.com/mangomandu/quotabar/main/install.sh | bash
```

<sub>Installs as a Claude Code statusline and also reads Codex's local session data, so both agents' limits live in one place. Open a new session to see it.</sub>

---

## ⚡ Lightweight & secure — measured, not claimed

A statusline runs on *every* render, so it has to be nearly free. quotabar was audited **three independent ways** — an adversarial review agent, **OpenAI Codex**, and [**Verdikt**](https://github.com/mangomandu/verdikt) (a holdout-based A/B referee) for the speed claim.

> **TL;DR** — on the common path (cache hit) a render is **~6 ms / ~3.4 MB with no Node spawned**, about **5× lighter than `ccusage`**. No daemon, timer, or socket. No exploit found in any of the three audits.

### Per render — one statusline update

| | quotabar — cache hit *(the common case)* | quotabar — cache miss | `ccusage statusline` |
|---|---|---|---|
| **time** | **~6 ms** | ~32 ms | ~32 ms |
| **peak memory** | **~3.4 MB** *(no Node spawned)* | ~45 MB | ~48 MB |
| **network** | **none** | none | none |
| **background process** | **none** | none | none |

- quotabar **caches its output per session** (default 2 s), so most renders skip Node entirely → **~6 ms, about 5× lighter than `ccusage`**, which pays full Node startup on every render.
- A cold render is a single short-lived `node` (~22 ms of which is Node's own startup) — on par with ccusage.
- **No daemon, no timer, no sockets.** It does literally nothing when you're idle — unlike always-on monitors (e.g. RunCat) that poll and animate continuously.

### Footprint vs other tools

This compares *cost*, not features — RunCat shows system CPU, not AI usage.

| | quotabar | `ccusage` statusline | RunCat |
|---|---|---|---|
| type | statusline — runs per render | statusline — runs per render | **persistent menu-bar app** |
| when you're idle | **nothing runs** | nothing runs | runs continuously (polls + animates) |
| per update | **~5 ms** *(cache hit)* · ~32 ms cold | ~32 ms | continuous low CPU |
| memory | transient, freed (3.4–45 MB) | transient, freed (~48 MB) | **resident the whole time** |
| network | none | none | none |
| background process | **none** | none | **always-on daemon** |

> **Verdikt verdict** — sealed holdout, paired trials, bootstrap CI:
> ```
> ┌─ claim: quotabar (cache hit) renders faster than ccusage
> │  on sealed holdout: 100%  (95% CI 100%–100%)
> │  deflated (1 try): 100%
> └─ verdict: PASS ✅
> ```
> Average over the trials: **quotabar 5.4 ms vs ccusage 29.6 ms.**

### Security — adversarial audit (and Codex), no exploit found

- **No command injection.** The config loader's `eval` only ever sees keys sanitized to `[A-Za-z0-9_]`; values are passed as a literal argument to `export`, never to `eval`. `$(...)`, backticks, `;cmd`, brace-breakouts — all inert.
- **No terminal-escape injection.** Every rendered string (model name, tags, Codex file paths, the `Cx idle` token, the `│` divider, debug output) goes through `clean()`, which strips all C0/C1 control bytes (`\x00–\x1f`, `\x7f–\x9f`). A crafted model name or Codex log **cannot smuggle ANSI/OSC sequences** (e.g. clipboard-stealing OSC 52) onto your terminal.
- **No path traversal.** The Codex walk uses `readdirSync(withFileTypes)` and skips symlinked dirs/files; cache filenames are sanitized from `session_id`; depth is capped.
- **Bounded.** Regexes are linear (no ReDoS); bar width clamps to 1–40; percent clamps to 0–100; the Codex tail read is capped at 4 MB regardless of file size.

---

## What it looks like

**Default** — Claude Code and Codex side by side, brand-colored (Claude orange / Codex blue), two rows. Bars stay neutral, go **yellow past 50%** and **red past 80%**; the `%` is always white:

![demo](./assets/demo.png)

**Wide terminal → one line** with a `│` divider (responsive, automatic):

![wide](./assets/wide.png)

**Codex idle past `CC_USAGE_STALE_MIN` min → its rows collapse** to a compact `Cx idle` tag after Claude Code:

![stale](./assets/stale.png)

---

## Why

`ccusage` and friends show the **dollar cost**. But on a flat-rate plan what bites you is the **limit %** and **when it resets** — and that data now arrives in the statusline's stdin. quotabar shows exactly that, and is the only one that folds in Codex too.

## Install

Needs `bash` and `node` (Claude Code already uses Node), on Linux, macOS, or WSL.

```bash
curl -fsSL https://raw.githubusercontent.com/mangomandu/quotabar/main/install.sh | bash
```

Drops `statusline.sh` into `~/.claude/hooks/`, adds a default `~/.claude/cc-usage.conf`, and wires up `statusLine` in `~/.claude/settings.json` (backing it up first). Open a new Claude Code session to see it.

<details>
<summary>Manual install</summary>

1. Copy `statusline.sh` to `~/.claude/hooks/statusline.sh` (`chmod +x`).
2. Copy `cc-usage.conf` to `~/.claude/cc-usage.conf`.
3. Add to `~/.claude/settings.json`:
   ```json
   "statusLine": { "type": "command", "command": "bash ~/.claude/hooks/statusline.sh", "padding": 0 }
   ```
</details>

**I only use Claude Code (no Codex).** Nothing to do — the Codex rows only render when Codex session data exists on your machine. Without it the default just shows the two brand-colored Claude Code rows (`5h`, `7d`).

---

## Customize

Edit **one file** — `~/.claude/cc-usage.conf` (no JSON). One `KEY=value` per line; `#` starts a comment. Save, then trigger any statusline refresh (type a message). Every key can also be an environment variable, which takes precedence.

#### What to show & layout — `CC_USAGE_SEGMENTS`

`,` puts items on the same line, `;` starts a new line. Items: `5h 7d` (Claude Code), `cx5h cx7d` (Codex), `ctx`, `model`, `cost`, `sep` (a `│` divider).

```
CC_USAGE_SEGMENTS=5h,7d;cx5h,cx7d    # default — Claude Code row + Codex row
CC_USAGE_SEGMENTS=5h,7d              # Claude Code only
```

**Responsive:** `CC_USAGE_SEGMENTS_WIDE` (default `5h,7d,sep,cx5h,cx7d`) kicks in when the terminal is at least `CC_USAGE_WIDE_AT` columns (shipped default 150; the one-line layout is ≈ 134 cols), else `CC_USAGE_SEGMENTS`. Width comes from the `COLUMNS` env Claude Code provides — no extra process.

#### Labels & colors

The head is `[provider tag] [window tag]`, and **every slot is replaceable** — any text or emoji, or empty to omit it:

```
CC_USAGE_TAG_CC=CC   CC_USAGE_TAG_CX=Cx                  # provider labels
CC_USAGE_TAG_5H=5h   CC_USAGE_TAG_7D=7d   CC_USAGE_TAG_CTX=ctx
# emoji instead:  TAG_CC=🟧  TAG_CX=🟦  TAG_5H=⏳  TAG_7D=📅
```

Color the **provider** tag — applies to text or a monochrome symbol like `✿ ⬢ ● ◆` (color emoji such as 🟧 ignore it):

```
CC_USAGE_TAGCOLOR_CC=claude   # built-in: claude orange #d77757
CC_USAGE_TAGCOLOR_CX=codex    # built-in: codex blue   #5769f7
```

The two brand defaults:

| tag | name | value | what it is |
|---|---|---|---|
| `CC` | `claude` | `#d77757` | Claude's terracotta orange |
| `Cx` | `codex`  | `#5769f7` | Codex blue — the blue Claude Code flashes while "compacting" |

Both were **eyedropped straight out of Claude Code / Codex screenshots** so the tags match the real UI. **Coral** and a couple of other screenshot-sampled shades were in the running before these won. Colors accept a built-in name, a 256-index, `#hex`, or `rgb(r,g,b)` — other built-ins: `coral` `orange` `purple` `violet` `blue` `pink` `teal` `lime` `red` `yellow` `green` `cyan` `magenta` `gray` `white`.

#### Everything else

| key | what it does |
|---|---|
| `CC_USAGE_RESET` | `relative` (`4h00m`) · `clock` (`→18:40`) · `both` |
| `CC_USAGE_BARS` | bar cells, 1–40 (default 10) |
| `CC_USAGE_WARN` / `CC_USAGE_CRIT` | yellow / red thresholds (default 50 / 80) |
| `CC_USAGE_THRESHOLD=off` | never color the bars |
| `CC_USAGE_STYLE=ascii` | render bars as `#-` · `NO_COLOR=1` disables color |
| `CC_USAGE_STALE_MIN` | collapse Codex to `Cx idle` after N idle minutes (default 30; `0` = always full) |
| `CC_USAGE_CODEX_DIR` | where to read Codex sessions (default `~/.codex/sessions`) |
| `CC_USAGE_CACHE_TTL` | reuse output for N seconds per session (default 2; `0` = always recompute) |

See [`cc-usage.conf`](./cc-usage.conf) for the annotated template.

---

## How it works

On each render Claude Code pipes a JSON blob to the command. quotabar reads `rate_limits` (`five_hour` / `seven_day`, with `used_percentage` + epoch `resets_at`), plus `context_window`, `cost`, `model`. For Codex it finds the newest `~/.codex/sessions/**/rollout-*.jsonl` by mtime and reads just the tail (growing 256 KB → 4 MB) to pull the last `rate_limits` event. It reads `COLUMNS` to pick the layout, then caches the result per `(session, layout)`. Everything happens in **one short-lived `node` process** (zero on a cache hit) — no `ls`/`grep`/`tail` subprocesses, no network.

## Notes & limitations

- **Codex freshness** — quotabar reads Codex's limits from Codex's own session log, so they're exactly as current as the last time Codex ran; it can't refresh them on its own. Once Codex has been idle past `CC_USAGE_STALE_MIN` minutes (default 30) the rows collapse to `Cx idle`, so you're not staring at frozen numbers. (Two open sessions can briefly disagree right as Codex crosses that threshold.)
- **Responsive lag** — the statusline re-runs when Claude Code re-renders (on activity), not on a bare terminal resize, so after resizing the layout switches on your next action. (Watching the terminal continuously would need a persistent daemon, which this deliberately avoids.)
- **Symbol tags** — if you put an emoji or symbol in a tag, some terminals force color-emoji presentation and ignore your `TAGCOLOR`. Use a plain dingbat (`✿ ⬢ ● ◆`) when you want your own color, or a color emoji (🟧 🟦) when you want a fixed-color glyph.

## Development

Run `bash test.sh` for the test suite (18 assertions; needs `bash` + `node`). For diagnostics, `CC_USAGE_DEBUG=1 … bash statusline.sh` (or `--debug`) prints the parsed data, resolved config, chosen Codex file + freshness, and any unknown `CC_USAGE_*` keys (typos) to stderr.

## License

MIT
