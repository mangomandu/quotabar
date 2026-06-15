# quotabar

*[English](./README.md) · [한국어](./README.ko.md)*

[Claude Code](https://claude.com/claude-code) 상태줄(statusline)에 AI 코딩 **사용 한도** — 정액제에서 진짜 신경 쓰이는 5시간/주간 한도 —를 색 막대로 보여주는 작은 도구입니다. **[Claude Code](https://claude.com/claude-code)와 [Codex](https://github.com/openai/codex)를 한 줄에 나란히** 추적하고, 컨텍스트 %·모델·세션 비용도 함께 표시합니다.

![quotabar statusline](./screenshot.svg)

> Claude Code의 statusline으로 설치되며(호스트), 추가로 Codex의 로컬 세션 데이터를 읽어 두 에이전트의 한도를 한 곳에 모아 보여줍니다.

`bash` + `node`(Claude Code가 이미 쓰는) 외엔 의존성 없음. 파일 하나, 렌더당 짧게 도는 `node` 프로세스 하나.

막대는 50% 넘으면 **노랑**, 80% 넘으면 **빨강**으로 바뀝니다.

## 왜?

`ccusage` 같은 도구는 **달러 비용**을 보여줍니다. 그런데 정액제에서 실제로 발목 잡는 건 **한도 %**와 **언제 리셋되는지**예요 — 이 데이터가 이제 statusline의 stdin으로 들어옵니다. quotabar는 바로 그걸 보여주고, **Codex까지 한데 묶는 유일한** 도구입니다.

## 요구사항

- `bash`, `node` (Claude Code가 이미 Node를 사용)
- Linux · macOS · WSL에서 동작

## 설치

```bash
curl -fsSL https://raw.githubusercontent.com/mangomandu/quotabar/main/install.sh | bash
```

`~/.claude/hooks/`에 `statusline.sh`를 넣고, 기본 `~/.claude/cc-usage.conf`를 추가하고, `~/.claude/settings.json`에 `statusLine`을 연결합니다(기존 설정은 먼저 백업). 새 Claude Code 세션을 열면 보입니다.

<details>
<summary>수동 설치</summary>

1. `statusline.sh`를 `~/.claude/hooks/statusline.sh`로 복사(`chmod +x`).
2. `cc-usage.conf`를 `~/.claude/cc-usage.conf`로 복사.
3. `~/.claude/settings.json`에 추가:
   ```json
   "statusLine": { "type": "command", "command": "bash ~/.claude/hooks/statusline.sh", "padding": 0 }
   ```
</details>

## Claude Code만 쓰는 경우 (Codex 없음)

할 게 없습니다 — 그게 기본값이에요. Claude Code 두 줄(`5h`, `7d`)만 뜨고, Codex 행은 기기에 Codex 세션 데이터가 있을 때만 나타납니다. 명시하고 싶으면 설정에 이 줄을 두세요:

```
CC_USAGE_SEGMENTS=5h,7d
```

## 커스터마이즈

**파일 하나**만 고치면 됩니다 — `~/.claude/cc-usage.conf` (JSON 편집 불필요). 한 줄에 `KEY=값`, `#`는 주석. 저장 후 아무 메시지나 보내면(statusline 갱신) 적용됩니다. 모든 키는 환경변수로도 줄 수 있고, 환경변수가 우선합니다.

**무엇을 / 몇 줄로 — `CC_USAGE_SEGMENTS`**
`,`=같은 줄, `;`=줄바꿈. 항목: `5h 7d`(Claude Code), `cx5h cx7d`(Codex), `ctx`, `model`, `cost`.
```
CC_USAGE_SEGMENTS=5h,7d              # 기본: Claude Code 한 줄
CC_USAGE_SEGMENTS=5h,7d;cx5h,cx7d    # Claude Code 줄 + Codex 줄
CC_USAGE_SEGMENTS=5h,7d;cx5h,cx7d;ctx,cost
```

**라벨 — 자유 슬롯 4개**
머리말 = `[공급자 태그] [윈도우 태그]`. 기본은 글자, 아무 글자/이모지로 교체.
```
CC_USAGE_TAG_CC=✿        # "CC" 자리   (기본: CC)
CC_USAGE_TAG_CX=❖        # "Cx" 자리   (기본: Cx)
CC_USAGE_TAG_5H=⏳        # "5h" 자리   (기본: 5h)
CC_USAGE_TAG_7D=📅        # "7d" 자리   (기본: 7d)
CC_USAGE_TAGCOLOR_CC=orange   # 단색 기호(✿ ❖ ● ◆ …)에 색; 이름 또는 256색 번호
CC_USAGE_TAGCOLOR_CX=purple   # (🟧 같은 컬러 이모지는 자체 색이라 무시됨)
```

**리셋 표시 — `CC_USAGE_RESET`**: `relative`(`4h00m`) · `clock`(`→18:40`) · `both`

**모양**: `CC_USAGE_BARS`(칸 수) · `CC_USAGE_WARN`/`CC_USAGE_CRIT`(% 임계) · `CC_USAGE_STYLE=ascii`(막대를 `#-`로) · `NO_COLOR=1`

주석 달린 템플릿은 [`cc-usage.conf`](./cc-usage.conf) 참고.

## 작동 방식

렌더할 때마다 Claude Code가 statusline 명령에 JSON을 파이프로 넘깁니다. 이 스크립트는 `rate_limits`(`five_hour`/`seven_day`, `used_percentage` + epoch `resets_at`)와 `context_window`·`cost`·`model`을 읽습니다. Codex는 `~/.codex/sessions/**/rollout-*.jsonl` 중 최신 파일을 찾아 **끝부분만** 읽어 마지막 `rate_limits` 이벤트(`primary`=5시간, `secondary`=주간)를 가져옵니다.

모든 처리가 **짧게 도는 `node` 프로세스 하나** 안에서 일어납니다 — `ls`/`grep`/`tail` 같은 서브프로세스 없음, Codex는 `cx*` 세그먼트가 켜졌을 때만 읽음. 렌더당 오버헤드는 ~20ms(거의 전부 Node 기동), 게다가 Claude Code가 활동 시에만 다시 실행하므로 사실상 공짜입니다.

## 참고 / 한계

- **Codex 신선도**: Codex 값은 Codex가 마지막으로 실행된 시점 기준입니다(그때 데이터를 기록하니까). 리셋까지 남은 시간은 항상 정확하고, %만 마지막으로 알려진 값입니다.
- **터미널 글리프**: 일부 터미널은 ☁ 같은 기호를 컬러 이모지로 강제 렌더해 색을 무시합니다. 색을 확실히 입히려면 단색 딩뱃(`✿ ❖ ● ◆`)을 쓰거나, 컬러 이모지 사각형(🟧 🟪)을 쓰세요.
- **갱신 주기**: Claude Code는 활동 시 statusline을 다시 실행(쓰로틀 적용)하므로, %는 실시간에 가깝게 따라가지만 째깍거리는 실시간 카운터는 아닙니다.

## 라이선스

MIT
