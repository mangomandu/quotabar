#!/usr/bin/env bash
# quotabar v1.2.2 — Claude Code statusline  (https://github.com/mangomandu/quotabar)
# Claude Code(공식 rate_limits) + Codex(세션 파일 rate_limits)의 5시간/주간 한도,
# 그리고 컨텍스트/모델/비용을 막대 바 + 색상으로 표시. 외부 의존성 없음(node 제외).
#
# 설정(환경변수, 모두 선택):
#   CC_USAGE_SEGMENTS  표시 항목/배치. 기본 "5h,7d".
#                      항목: 5h 7d ctx(분수) effort model cost  cx5h cx7d  (cx*=Codex)  sep(구분선│)
#                      "," = 같은 줄에 나란히,  ";" = 줄바꿈.
#                      예) "5h,7d;cx5h,cx7d" → CC 한 줄, Codex 한 줄 (총 2줄)
#   CC_USAGE_SEGMENTS_WIDE  터미널이 넓을 때(COLUMNS≥WIDE_AT) 대신 쓸 배치(반응형). 좁으면 SEGMENTS.
#   CC_USAGE_WIDE_AT        WIDE 전환 폭 기준(기본 120). COLUMNS는 Claude Code가 줌(추가비용 0).
#   CC_USAGE_RESET     리셋 표시: relative(기본,"4h00m") | clock("→18:40") | both
#   CC_USAGE_TAG_CC    "CC" 자리 라벨(기본 "CC"). 아무 글자/이모지로 교체 (예: 🟧)
#   CC_USAGE_TAG_CX    "Cx" 자리 라벨(기본 "Cx").                    (예: 🟦)
#   CC_USAGE_TAG_5H    "5h" 자리 라벨(기본 "5h").                    (예: ⏳)
#   CC_USAGE_TAG_7D    "7d" 자리 라벨(기본 "7d").                    (예: 📅)
#   CC_USAGE_TAG_CTX   "ctx" 자리 라벨(기본 "ctx").                  (예: 🧠)
#   CC_USAGE_TAGCOLOR_CC  CC 태그 색: 이름/256번호/#hex/rgb(). 글자·단색기호에 적용(컬러 이모지는 무시)
#   CC_USAGE_TAGCOLOR_CX  Cx 태그 색
#   CC_USAGE_STYLE     unicode(기본) | ascii   (막대를 #,- 로: 옛 터미널용)
#   CC_USAGE_BARS      막대 칸 수(기본 10)
#   CC_USAGE_WARN      노랑 임계 %(기본 50)
#   CC_USAGE_CRIT      빨강 임계 %(기본 80)
#   CC_USAGE_THRESHOLD 막대 경고색 on(기본)|off. 기본 무채색, warn%↑ 노랑·crit%↑ 빨강. %글씨는 항상 흰색
#   CC_USAGE_CODEX_DIR Codex 세션 루트(기본 ~/.codex/sessions)
#   CC_USAGE_CACHE_TTL 같은 세션 재렌더 캐시 TTL(초). 기본 2. 0=비활성(항상 즉시 계산)
#   CC_USAGE_STALE_MIN Codex가 이 분(min) 넘게 안 돌면 'Cx idle'로 접어 CC 뒤에 붙임. 기본 30. 0=끔
#   CC_USAGE_WATCH_SECS --watch 재렌더 간격(초). 기본 5. 1 미만/비숫자는 보정.
#   CC_USAGE_UPDATE    on 설정 시 기본 7일에 1회 백그라운드로 새 버전 확인 후 막대 끝에 '⬆ vX' 표시. 기본 off.
#                      렌더는 안 막음(detached). 수동 갱신은 'statusline.sh --update'(언제든, 네트워크 필요).
#   CC_USAGE_UPDATE_DAYS  위 확인 간격(일). 기본 7. 렌더 비용은 간격과 무관(파일 1회 읽기뿐).
#   CC_USAGE_DEBUG     설정 시(또는 첫 인자 --debug) 파싱·설정·codex 진단을 stderr로 출력
#   NO_COLOR           비어있지 않게 설정 시 색상 비활성(no-color.org 관례)
#
# 위 변수들은 설정 파일 ~/.claude/cc-usage.conf 에 "KEY=value" 한 줄씩 적어두면
# 자동으로 적용됩니다(JSON 편집 불필요). 환경변수가 있으면 환경변수가 우선.
# 파일 위치는 CC_USAGE_CONFIG 로 바꿀 수 있습니다.

VER="1.2.2"   # 헤더의 'quotabar vX.Y.Z'와 동일하게 유지 — 업데이트 비교/표시에 사용

# 버전 비교: $1 > $2 이면 0. 점 구분 숫자, fork·GNU(sort -V) 비의존(macOS/BSD 안전). 업데이트 알림 표시에만 씀.
_qb_gt() {
  local i n; local -a A B
  IFS=. read -ra A <<<"$1"; IFS=. read -ra B <<<"$2"
  n=${#A[@]}; [ "${#B[@]}" -gt "$n" ] && n=${#B[@]}
  for ((i=0; i<n; i++)); do
    local a=${A[i]:-0} b=${B[i]:-0}
    case "$a" in *[!0-9]*) a=0;; esac; case "$b" in *[!0-9]*) b=0;; esac
    [ "$((10#$a))" -gt "$((10#$b))" ] && return 0
    [ "$((10#$a))" -lt "$((10#$b))" ] && return 1
  done
  return 1
}

# --- 플래그 파싱(순서 무관): --update(즉시 동작) / --standalone(=--codex, 독립 모드) / --tmux / --watch / --debug ---
_standalone=0; _tmux=0; _watch=0; _do_update=0; _do_setup=0
for _a in "$@"; do case "$_a" in
  --update) _do_update=1;;
  --setup) _do_setup=1;;
  --standalone|--codex) _standalone=1;;
  --tmux) _tmux=1;;
  --watch) _watch=1; _standalone=1;;
  --debug) export CC_USAGE_DEBUG=1;;
esac; done

# 수동 업데이트: 최신 statusline.sh를 받아 자기 자신을 덮어씀(언제든, node 불필요)
if [ "$_do_update" = 1 ]; then
  _self="${BASH_SOURCE[0]:-$0}"; _tmp="$(mktemp 2>/dev/null)" || { echo "✗ mktemp failed"; exit 1; }
  if curl -fsSL "https://raw.githubusercontent.com/mangomandu/quotabar/main/statusline.sh" -o "$_tmp" 2>/dev/null && [ -s "$_tmp" ]; then
    chmod +x "$_tmp" 2>/dev/null
    if mv "$_tmp" "$_self" 2>/dev/null; then
      rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/quotabar/.update-available" 2>/dev/null
      echo "✓ quotabar updated → $_self"; exit 0
    fi
  fi
  rm -f "$_tmp" 2>/dev/null; echo "✗ quotabar update failed (network or permissions)"; exit 1
fi

# 셋업 도우미: 환경 감지 후 standalone/tmux 설정 안내. tmux 없는 Codex 사용자에겐 설치 권장.
# (일반 터미널에서 Codex 풀스크린 TUI 도중엔 바를 띄울 자리가 없으므로, 안내는 이 수동 명령/설치 시점에만 가능)
if [ "$_do_setup" = 1 ]; then
  _self="${BASH_SOURCE[0]:-$0}"   # 절대경로(복붙용 — tmux.conf는 다른 cwd에서 실행됨)
  _dir="$(cd "$(dirname "$_self")" 2>/dev/null && pwd)"; [ -n "$_dir" ] && _self="$_dir/$(basename "$_self")"
  printf '%s\n' "quotabar setup  (copy-paste; paths absolute)" "─────────────────────────────────────────"
  if command -v tmux >/dev/null 2>&1; then
    printf '%s\n' "tmux bar  → add to ~/.tmux.conf (append; won't clobber your existing bar):" \
      "  set -ga status-right \"  #($_self --standalone --tmux)\"" \
      "  set -g status-interval 5" \
      "  set -ga terminal-overrides ',*:RGB'"
  else
    printf '%s\n' "always-on bar → install tmux:  sudo apt install tmux   (mac: brew install tmux)" \
      "                then re-run: bash \"$_self\" --setup"
  fi
  printf '%s\n' "watch    → bash \"$_self\" --watch        (2nd pane · Ctrl-C)" \
    "one-shot → bash \"$_self\" --standalone" \
    "in Claude Code → register this script as your statusLine (install.sh does it)"
  exit 0
fi

if [ "$_watch" = 1 ]; then
  _self="${BASH_SOURCE[0]:-$0}"
  _dir="$(cd "$(dirname "$_self")" 2>/dev/null && pwd)"; [ -n "$_dir" ] && _self="$_dir/$(basename "$_self")"
  _secs="${CC_USAGE_WATCH_SECS:-5}"; case "$_secs" in ''|*[!0-9]*) _secs=5;; esac; [ "$_secs" -lt 1 ] 2>/dev/null && _secs=1
  trap 'printf "\n"; exit 0' INT
  _args=(--standalone)
  [ "$_tmux" = 1 ] && _args+=(--tmux)
  while :; do
    _line="$(bash "$_self" "${_args[@]}" </dev/null)"
    printf '\r\033[K%s' "$_line"
    sleep "$_secs" || break
  done
  exit 0
fi

command -v node >/dev/null 2>&1 || { printf '⏳ cc-usage: node not found'; exit 0; }

# (--debug 는 위 플래그 루프에서 처리됨; CC_USAGE_DEBUG=1 로도 가능)

# 설정 파일 로드: "KEY=value" 줄만 인식, 주석(#)/빈 줄 무시, 환경변수가 우선
conf="${CC_USAGE_CONFIG:-$HOME/.claude/cc-usage.conf}"
if [ -f "$conf" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in *=*) ;; *) continue;; esac          # '='가 있는 줄만
    key=${line%%=*}; val=${line#*=}
    key="${key#"${key%%[![:space:]]*}"}"; key="${key%"${key##*[![:space:]]}"}"  # 키 양끝 공백 제거
    case "$key" in *[!A-Za-z0-9_]*|'') continue;; esac   # 키는 영숫자/밑줄만(eval 주입 방지)
    case "$key" in CC_USAGE_*|NO_COLOR) ;; *) continue;; esac  # 인식하는 키만
    val="${val#"${val%%[![:space:]]*}"}"               # 값 좌측 공백 제거
    val="${val%%" #"*}"                                # 인라인 주석( #...) 제거
    val="${val%"${val##*[![:space:]]}"}"               # 값 우측 공백 제거
    val="${val#\"}"; val="${val%\"}"; val="${val#\'}"; val="${val%\'}"  # 양끝 따옴표 제거
    eval "[ -z \"\${$key+x}\" ]" && export "$key=$val"  # 미설정 시에만(=env 우선); key는 검증됨
  done < "$conf"
fi

# --- 캐시(#1): 같은 세션의 잦은 재렌더 시 node 미기동. TTL 내 + conf 미변경이면 캐시 사용 ---
# 독립 모드(CC 밖): CC가 stdin으로 JSON을 안 줌 → stdin 읽기 생략(안 그러면 cat이 EOF 기다리며 멈춤 = 프롬프트 먹통).
# Codex 위주 세그먼트로 고정(반응형 WIDE 미적용 → CC 세그먼트 재유입/블랭크 가드 회피), node에 모드 전달.
[ "$_tmux" = 1 ] && export CC_USAGE_TMUX=1   # --tmux: 출력 포맷(입력 모드와 무관 — standalone이든 CC stdin이든 tmux 마크업)
if [ "$_standalone" = 1 ]; then
  IN=""
  export CC_USAGE_STANDALONE=1
  export CC_USAGE_SEGMENTS="${CC_USAGE_SEGMENTS_STANDALONE:-5h,7d,sep,cx5h,cx7d}"   # 대칭: CC(스냅샷)+Codex(파일) 한 줄, 빈 쪽은 구분선 정리됨
else
  IN=$(cat)                                                  # stdin(JSON) 캡처
fi
ttl="${CC_USAGE_CACHE_TTL:-2}"; case "$ttl" in *[!0-9]*) ttl=0;; esac
sid=default
case "$IN" in *'"session_id":"'*) sid="${IN#*\"session_id\":\"}"; sid="${sid%%\"*}";; esac
case "$sid" in *[!A-Za-z0-9._-]*|'') sid=default;; esac     # 안전한 파일명만
# 반응형: 터미널이 넓으면(COLUMNS≥WIDE_AT) WIDE 레이아웃 사용. COLUMNS는 Claude Code가 줌(공짜). 독립 모드는 미적용.
cols="${COLUMNS:-0}"; case "$cols" in ''|*[!0-9]*) cols=0;; esac
wat="${CC_USAGE_WIDE_AT:-120}"; case "$wat" in ''|*[!0-9]*) wat=120;; esac
lw=n
if [ "$_standalone" != 1 ] && [ -n "${CC_USAGE_SEGMENTS_WIDE:-}" ] && [ "$cols" -ge "$wat" ]; then export CC_USAGE_SEGMENTS="$CC_USAGE_SEGMENTS_WIDE"; lw=w; fi
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/quotabar"
_ckey="$sid-$lw"
[ "$_standalone" = 1 ] && _ckey="standalone-$lw"   # 독립 모드: 세션ID 없음 → 고정 네임스페이스
[ "$_tmux" = 1 ] && _ckey="$_ckey-tmux"            # tmux 마크업 출력은 raw와 별도 캐시(충돌 방지)
cache="$cache_dir/$_ckey"   # 폭(레이아웃)별 + 모드별 캐시

# --- 업데이트 알림(opt-in: CC_USAGE_UPDATE=on). 기본 7일에 1회만 백그라운드로 버전 확인 — 렌더는 안 막음(detached).
#     간격은 CC_USAGE_UPDATE_DAYS로 조정. 기본(off)일 땐 문자열 비교 1번이 전부.
#     on이어도 핫패스는 EPOCHSECONDS(빌트인)+파일 1회 읽기, fork 0 — 간격이 길든 짧든 렌더 비용은 동일.
upd_hint=""; _uon=0
# 명시적 truthy 값일 때만 켬 — false/0/no/off/오타는 네트워크 안 건드림(Codex 리뷰 P2). case라 fork 0 + bash3 안전.
case "${CC_USAGE_UPDATE:-}" in on|On|ON|1|true|True|TRUE|yes|Yes|YES) _uon=1;; esac
[ "$_standalone" = 1 ] && _uon=0   # 독립 모드: 업데이트 알림 끔(CC 전용 기능 + idle 시 upd_hint가 남아 안 사라지는 것 방지)
if [ "$_uon" = 1 ]; then
  _unow="${EPOCHSECONDS:-0}"; [ "$_unow" = 0 ] && _unow=$(date +%s 2>/dev/null || echo 0)
  _ud="${CC_USAGE_UPDATE_DAYS:-7}"; case "$_ud" in ''|*[!0-9]*) _ud=7;; esac; [ "$_ud" -lt 1 ] 2>/dev/null && _ud=7
  _uint=$(( _ud * 86400 ))                       # 확인 간격(초). 기본 7일
  _uf="$cache_dir/.update-check"; _ul=0
  # read는 개행 없이 EOF면 값은 넣고도 exit 1을 냄 → '|| _ul=0' 쓰면 방금 읽은 값을 도로 0으로 만들어
  # throttle이 매번 발동(백그라운드 fork)함. _ul은 이미 0으로 초기화돼 있으니 read 실패는 무시하고, 값 검증은 아래 case로.
  [ -f "$_uf" ] && IFS= read -r _ul < "$_uf" 2>/dev/null
  case "$_ul" in ''|*[!0-9]*) _ul=0;; esac
  # 스탬프 기록에 성공했을 때만 백그라운드 확인을 띄움 — 기록 실패(읽기전용 캐시 등)면 throttle을 못 박으니
  # 아예 확인을 건너뛴다. 그래야 매 렌더 재발동(네트워크 fork 반복)을 막음. (Codex 리뷰 P2)
  # printf의 '2>/dev/null'을 '>'보다 먼저 둠: 리다이렉션은 좌→우 처리라, 이 순서여야 파일 열기 실패
  # (읽기전용 캐시 등)의 bash 에러가 stderr로 안 샌다. 실패 시 종료코드는 비0 → &&로 백그라운드도 안 뜸. (Codex P3)
  if [ "$(( _unow - _ul ))" -gt "$_uint" ] && mkdir -p "$cache_dir" 2>/dev/null && printf '%s\n' "$_unow" 2>/dev/null > "$_uf"; then
    ( _l=$(curl -fsSL --max-time 5 "https://raw.githubusercontent.com/mangomandu/quotabar/main/statusline.sh" 2>/dev/null \
            | sed -n 's/^# quotabar v\([0-9.]*\).*/\1/p' | head -1)
      if [ -n "$_l" ] && [ "$_l" != "$VER" ]; then printf '%s\n' "$_l" > "$cache_dir/.update-available" 2>/dev/null
      else rm -f "$cache_dir/.update-available" 2>/dev/null; fi
    ) </dev/null >/dev/null 2>&1 &
  fi
  # 캐시된 가용 버전이 현재 VER '보다 최신'일 때만 표시(_qb_gt). 같거나 빈 값이면 낡은 플래그 제거 —
  # 안 그러면 설치 경로로 이미 갱신된 자기 버전을, 또는 더 옛 캐시값을 'update 있음'으로 잘못 표시함. (Codex 리뷰 P2)
  if [ -f "$cache_dir/.update-available" ]; then
    _uv=""; IFS= read -r _uv < "$cache_dir/.update-available" 2>/dev/null
    if [ -z "$_uv" ] || [ "$_uv" = "$VER" ]; then
      rm -f "$cache_dir/.update-available" 2>/dev/null
    elif _qb_gt "$_uv" "$VER"; then
      upd_hint="  ⬆ v$_uv"        # _uv > VER (최신)일 때만 표시 — 다운그레이드 프롬프트 방지
    fi
  fi
fi

if [ "$ttl" -gt 0 ] && [ -z "$CC_USAGE_DEBUG" ] && [ -f "$cache.o" ] && [ -f "$cache.t" ] && [ ! "$conf" -nt "$cache.t" ]; then
  IFS= read -r _ts < "$cache.t" 2>/dev/null || _ts=0
  case "$_ts" in ''|*[!0-9]*) _ts=0;; esac
  _now=$(date +%s 2>/dev/null || echo 0)
  if [ "$(( _now - _ts ))" -ge 0 ] && [ "$(( _now - _ts ))" -lt "$ttl" ]; then
    cat "$cache.o"; printf '%s' "$upd_hint"; exit 0
  fi
fi

out=$(printf '%s' "$IN" | node -e '
const fs=require("fs");
let d={};try{d=JSON.parse(fs.readFileSync(0,"utf8"))}catch(e){}
const rl=d.rate_limits||{};
const clean=s=>String(s==null?"":s).replace(/[\x00-\x1f\x7f-\x9f]/g,"");  // 터미널 제어문자(ESC 등) 제거 = 인젝션 방지

const env=process.env;
const standalone=!!env.CC_USAGE_STANDALONE, tmux=!!env.CC_USAGE_TMUX;
// tmux 상태바는 raw ANSI(SGR)를 색칠 안 함 → 자체 마크업 #[fg=...] 로 변환하고 리터럴 #는 ## 로 이스케이프.
const _h2=n=>{n=Number(n)||0;n=n<0?0:n>255?255:n;const s=n.toString(16);return s.length<2?"0"+s:s;};
const dimC=env.CC_USAGE_TMUX_DIM||"colour244";   // tmux 흐림(빈막대·리셋·구분선) 색. conf로 조절. 기본 colour244
const _sgrToTmux=codes=>{const parts=codes.split(";");let out="";
  for(let k=0;k<parts.length;k++){const c=parts[k];
    if(c===""||c==="0")out+="#[default]";
    else if(c==="1")out+="#[bold]";
    else if(c==="2")out+=(dimC==="dim"?"#[dim]":"#[fg="+dimC+"]");           // dim → CC_USAGE_TMUX_DIM: "dim"=진짜 흐림속성(CC와 동일) / 색이름·#hex=그 색. 기본 colour244
    else if(c==="38"&&parts[k+1]==="2"){out+="#[fg=#"+_h2(parts[k+2])+_h2(parts[k+3])+_h2(parts[k+4])+"]";k+=4;}  // truecolor(#[fg=#rrggbb] 표시엔 tmux RGB 필요)
    else if(c==="38"&&parts[k+1]==="5"){out+="#[fg=colour"+parts[k+2]+"]";k+=2;}                                  // 256색
    else if(c==="32")out+="#[fg=green]";else if(c==="33")out+="#[fg=yellow]";else if(c==="31")out+="#[fg=red]";}
  return out;};
const toTmux=s=>{let r="",i=0;
  while(i<s.length){
    if(s[i]==="\x1b"&&s[i+1]==="["){const j=s.indexOf("m",i);if(j>=0){r+=_sgrToTmux(s.slice(i+2,j));i=j+1;continue;}}
    r+=(s[i]==="#")?"##":s[i];i++;}
  return r;};
const cfg={
  rows:(env.CC_USAGE_SEGMENTS||"5h,7d").split(";")
        .map(r=>r.split(",").map(s=>s.trim()).filter(Boolean)).filter(r=>r.length),
  reset:env.CC_USAGE_RESET||"relative",
  ascii:(env.CC_USAGE_STYLE||"unicode")==="ascii",
  width:Math.max(1,Math.min(40,parseInt(env.CC_USAGE_BARS||"10",10)||10)),  // 1~40 칸으로 제한
  warn:parseInt(env.CC_USAGE_WARN||"50",10),
  crit:parseInt(env.CC_USAGE_CRIT||"80",10),
  color:!env.NO_COLOR,
};
// B: tmux 중복 제거(opt-in CC_USAGE_TMUX_DEDUP). CC statusline이 tmux 안에서 돌면($TMUX 있음) 쿼터 세그먼트 제거
// — tmux 바가 쿼터를 보여주니 중복 방지. 일반 터미널($TMUX 없음)에선 그대로 full 표시. 스냅샷 기록엔 영향 없음.
if(!standalone && /^(on|1|true|yes)$/i.test(env.CC_USAGE_TMUX_DEDUP||"") && env.TMUX){
  cfg.rows=cfg.rows.map(r=>r.filter(s=>s!=="5h"&&s!=="7d"&&s!=="cx5h"&&s!=="cx7d")).filter(r=>r.length);
}

// Codex: cx 세그먼트가 있을 때만, 모든 rollout 중 mtime 최신 파일에서 마지막 rate_limits 추출.
// 파일 끝에서 점점 키워가며(256KB→최대 4MB) 읽어 큰 세션도 안 놓침. 서브셸 없이 node로.
let cx={},cxTs=0,codexFile=null;
if(cfg.rows.some(r=>r.includes("cx5h")||r.includes("cx7d"))){
  try{
    const root=env.CC_USAGE_CODEX_DIR||require("os").homedir()+"/.codex/sessions";
    const cand=[];  // 모든 rollout 후보 {p,m}; mtime 최신순으로 정렬해 가장 최근 rate_limits를 찾음
    const walk=(dir,depth)=>{
      let ents;try{ents=fs.readdirSync(dir,{withFileTypes:true})}catch(e){return}
      for(const e of ents){const p=dir+"/"+e.name;
        if(depth<3){if(e.isDirectory())walk(p,depth+1)}
        else if(e.isFile()&&e.name.startsWith("rollout-")&&e.name.endsWith(".jsonl")){
          let m;try{m=fs.statSync(p).mtimeMs}catch(_){continue}
          cand.push({p:p,m:m})}}
    };
    walk(root,0);
    cand.sort((a,b)=>b.m-a.m);
    // 파일 끝에서 점점 키워가며(256KB→최대 4MB) 마지막 rate_limits 추출. 서브셸 없이 node로.
    const tryRead=p=>{
      let lcx={},lts=0;
      const fd=fs.openSync(p,"r"),sz=fs.fstatSync(fd).size;
      for(let chunk=262144;;chunk*=4){
        const n=Math.min(sz,chunk);
        const b=Buffer.alloc(n);fs.readSync(fd,b,0,n,sz-n);
        const arr=b.toString("utf8").split("\n");
        const start=(n<sz)?1:0;   // 전체를 안 읽었으면 잘린 첫 줄은 버림(부분기록 라인도 자연히 건너뜀)
        for(let i=arr.length-1;i>=start;i--){
          if(arr[i].includes("\"rate_limits\"")){
            try{const pj=JSON.parse(arr[i]);if(pj.payload&&pj.payload.rate_limits){lcx=pj.payload.rate_limits;lts=Date.parse(pj.timestamp)||0}}catch(_){}
            if(Object.keys(lcx).length)break;
          }
        }
        if(Object.keys(lcx).length||n>=sz||chunk>=4194304)break;
      }
      fs.closeSync(fd);
      return {cx:lcx,ts:lts};
    };
    // 최신 파일에 rate_limits가 없을 수 있어(부분기록·다른 세션) 최신 몇 개를 차례로 시도(상한 8).
    for(let k=0;k<cand.length&&k<8;k++){
      const rr=tryRead(cand[k].p);
      if(Object.keys(rr.cx).length){cx=rr.cx;cxTs=rr.ts;codexFile=cand[k].p;break;}
    }
  }catch(e){}
}
const cxNorm=o=>o?{used_percentage:o.used_percent,resets_at:o.resets_at}:null;
// 라벨 태그: 공급자(cc/cx) + 윈도우(5h/7d) + ctx. 기본은 글자, 무엇이든(이모지 포함) 교체 가능.
const tag={
  cc:  clean(env.CC_USAGE_TAG_CC  ?? "CC"),
  cx:  clean(env.CC_USAGE_TAG_CX  ?? "Cx"),
  "5h":clean(env.CC_USAGE_TAG_5H  ?? "5h"),
  "7d":clean(env.CC_USAGE_TAG_7D  ?? "7d"),
  ctx: clean(env.CC_USAGE_TAG_CTX ?? "ctx"),
};

const C=cfg.color?{R:"\x1b[0m",DIM:"\x1b[2m",B:"\x1b[1m",g:"\x1b[32m",y:"\x1b[33m",r:"\x1b[31m"}
                 :{R:"",DIM:"",B:"",g:"",y:"",r:""};
const thresh=!/^(off|0|false|no)$/i.test(env.CC_USAGE_THRESHOLD||"on"); // 막대 경고색 on|off
const DEEP={warn:"\x1b[38;2;198;156;43m",crit:"\x1b[38;2;188;58;52m"};  // 막대 채움색: 쨍한 ANSI 대신 진한 골드/레드(truecolor)
const col=p=>(thresh&&cfg.color)?(p>=cfg.crit?DEEP.crit:p>=cfg.warn?DEEP.warn:""):"";  // warn%↑ 진골드, crit%↑ 진레드
const G=cfg.ascii?{fill:"#",empty:"-"}:{fill:"▰",empty:"▱"};
// 색 보간 → ANSI truecolor escape (effort max 그라데이션용)
const lerpC=(c1,c2,t)=>"\x1b[38;2;"+Math.round(c1[0]+(c2[0]-c1[0])*t)+";"+Math.round(c1[1]+(c2[1]-c1[1])*t)+";"+Math.round(c1[2]+(c2[2]-c1[2])*t)+"m";
// 태그 색(공급자 라벨용): 색 이름 또는 256색 번호 → ANSI. 컬러 이모지(🟧)엔 영향 없음, 단색 기호(✿ ⬢)에 색.
const NAMED={black:0,red:196,green:46,yellow:226,blue:39,magenta:201,cyan:51,white:255,
  orange:208,purple:135,violet:99,pink:213,gray:244,grey:244,teal:44,lime:118,coral:209,
  claude:"#da7756",codex:"#5769f7"};   // claude=Anthropic 테라코타(공식 브랜드색), codex=Claude Code compacting 블루(Codex 공식색 없음)
const tcol=spec=>{
  if(!cfg.color||!spec)return"";
  let s=String(spec).trim().toLowerCase();
  if(NAMED[s]!=null)s=String(NAMED[s]);    // 이름 → 정의값(hex 또는 번호)으로 치환 후 재해석
  let m;
  if(m=s.match(/^#?([0-9a-f]{6})$/))return `\x1b[38;2;${parseInt(m[1].slice(0,2),16)};${parseInt(m[1].slice(2,4),16)};${parseInt(m[1].slice(4,6),16)}m`; // #hex → truecolor
  if(m=s.match(/^rgb\((\d+),(\d+),(\d+)\)$/))return `\x1b[38;2;${m[1]};${m[2]};${m[3]}m`;     // rgb(r,g,b) → truecolor
  if(/^\d+$/.test(s))return `\x1b[38;5;${s}m`;                                                // 256색 번호
  return "";
};
const provColor={cc:tcol(env.CC_USAGE_TAGCOLOR_CC),cx:tcol(env.CC_USAGE_TAGCOLOR_CX)};

const bar=p=>{
  const f=Math.max(0,Math.min(cfg.width,Math.round(p/100*cfg.width)));
  return col(p)+G.fill.repeat(f)+C.R+C.DIM+G.empty.repeat(cfg.width-f)+C.R;
};
const ms=o=>{let t=Number(o.resets_at);if(isNaN(t))return null;return t<1e12?t*1000:t;};
const relStr=o=>{ // 남은 시간
  const t=ms(o);if(t==null)return"";
  let s=Math.max(0,Math.floor((t-Date.now())/1000));
  const dd=Math.floor(s/86400),h=Math.floor(s%86400/3600),m=Math.floor(s%3600/60);
  return dd>0?`${dd}d${h}h`:`${h}h${String(m).padStart(2,"0")}m`;
};
const clockStr=o=>{ // 초기화 시각
  const t=ms(o);if(t==null)return"";
  const dt=new Date(t),now=new Date();
  const hh=String(dt.getHours()).padStart(2,"0"),mm=String(dt.getMinutes()).padStart(2,"0");
  const same=dt.toDateString()===now.toDateString();
  return same?`${hh}:${mm}`:`${dt.getMonth()+1}/${dt.getDate()} ${hh}:${mm}`;
};
const resetStr=o=>{
  if(!o||o.resets_at==null)return"";
  const rel=relStr(o),clk=clockStr(o);
  if(cfg.reset==="clock")return clk?`→${clk}`:"";
  if(cfg.reset==="both")return rel?`${rel}${clk?` (→${clk})`:""}`:(clk?`→${clk}`:"");
  return rel;
};

const staleMin=parseFloat(env.CC_USAGE_STALE_MIN||"30");  // 분(min); 소수 OK(0.5=30초, 디버깅용). 0=끔
const codexStale=cxTs>0&&staleMin>0&&Date.now()-cxTs>staleMin*60000;
// 대칭 스냅샷: CC는 자기 한도를 디스크에 안 남김(stdin으로만 줌) → CC 모드에서 quotabar가 대신 파일에 저장하고,
// standalone(tmux/프롬프트)에선 그 파일을 읽어 CC도 표시(Codex가 파일로 읽히는 것과 대칭). staleMin 넘으면 무시.
const cacheDir=(env.XDG_CACHE_HOME||(require("os").homedir()+"/.cache"))+"/quotabar";
const ccSnap=cacheDir+"/cc-limits.json";
let ccSnapAge=-1;
if(!standalone){
  if(rl.five_hour||rl.seven_day){
    try{fs.mkdirSync(cacheDir,{recursive:true});fs.writeFileSync(ccSnap,JSON.stringify({five_hour:rl.five_hour,seven_day:rl.seven_day,ts:Date.now()}));}catch(e){}
  }
}else{
  try{const sn=JSON.parse(fs.readFileSync(ccSnap,"utf8"));
    if(sn&&sn.ts){ccSnapAge=Math.floor((Date.now()-sn.ts)/60000);
      if(staleMin<=0||Date.now()-sn.ts<=staleMin*60000){
        if(sn.five_hour)rl.five_hour=sn.five_hour;
        if(sn.seven_day)rl.seven_day=sn.seven_day;
      }
    }
  }catch(e){}
}
// prov=공급자 태그키(cc/cx), win=윈도우 태그키(5h/7d), tagKey=단일 태그(ctx 등)
// 토큰 수 사람친화 표기: 396176→"396k", 1000000→"1M", 1500000→"1.5M"
const hum=n=>{n=Number(n);if(!Number.isFinite(n))return null;
  if(n>=1e6){const m=n/1e6;return (Number.isInteger(m)?m:m.toFixed(1))+"M";}
  if(n>=1e3)return Math.round(n/1e3)+"k";
  return String(Math.round(n));};
// 정적 보라 그라데이션: 글자마다 색 보간(애니메이션 아님, 비용 0). 컬러 꺼지면 평문.
const grad=(str,c1,c2)=>{
  if(!cfg.color)return str;
  const n=Math.max(1,str.length-1);let out="";
  for(let i=0;i<str.length;i++)out+=lerpC(c1,c2,i/n)+str[i];
  return out+C.R;};
// 한 줄(wide) 레이아웃이면 간격 좁히고 % 패딩 생략; 여러 줄이면 현재 간격 + % 열 정렬 유지
const oneLine=cfg.rows.length===1;
const SP=oneLine?" ":"  ";   // 세그먼트 내부 간격(머리말·바·리셋 주변)
const JN=oneLine?"  ":"   "; // 세그먼트 사이 간격(구분선 포함)
const SEG={
  "5h":   {prov:"cc", win:"5h", type:"limit", get:()=>rl.five_hour},
  "7d":   {prov:"cc", win:"7d", type:"limit", get:()=>rl.seven_day},
  "cx5h": {prov:"cx", win:"5h", type:"limit", get:()=>cxNorm(cx.primary)},
  "cx7d": {prov:"cx", win:"7d", type:"limit", get:()=>cxNorm(cx.secondary)},
  "ctx":  {tagKey:"ctx", type:"ctxfrac", get:()=>d.context_window},
  "model":{type:"text", get:()=>clean(d.model&&d.model.display_name)||null},
  "cost": {type:"text", get:()=>{const c=Number(d.cost&&d.cost.total_cost_usd);return Number.isFinite(c)?"$"+c.toFixed(2):null;}},
  "effort":{type:"effort", get:()=>clean(d.effort&&d.effort.level)||null},
};
// 머리말 = 공급자태그 + 윈도우태그 (예: 기본 "CC 5h", 커스텀 "🟧 ⏳"). ctx는 단일 태그. model/cost는 없음.
const head=(s,showProv)=>{
  if(s.prov){
    const pt=showProv?tag[s.prov]:"";         // 같은 줄에서 공급자 반복 시 태그 생략
    const wt=tag[s.win],pc=provColor[s.prov];
    const provPart=pt?(pc?pc+pt+C.R:pt):"";   // 공급자 태그에 지정색(있으면)
    return [provPart,wt].filter(Boolean).join(" ");
  }
  if(s.tagKey)return tag[s.tagKey]||"";
  return "";
};
let cxIdleShown=false;   // Codex 스테일 시 Cx idle 토큰은 (여러 cx 세그 중) 첫 자리에만 인플레이스로 1회
const render=(key,showProv)=>{
  if(key==="sep"||key==="|")return C.DIM+"│"+C.R;   // 구분선(예: 같은 줄에서 CC│Cx)
  const s=SEG[key];if(!s)return null;
  if(s.prov==="cx"&&codexStale){   // Codex 스테일 → 막대 대신 Cx idle 을 그 자리에(첫 cx만), 나머지 cx는 숨김
    if(standalone)return null;     // 독립 모드: Cx idle 안 띄우고 그냥 사라짐(빈 출력 → 캐시 안 됨 → 재개 시 즉시 복귀)
    if(cxIdleShown)return null;
    cxIdleShown=true;
    const cxt=tag.cx||"Cx";
    return (provColor.cx?provColor.cx+cxt+C.R:C.DIM+cxt+C.R)+C.DIM+" idle"+C.R;
  }
  const o=s.get();
  const h=head(s,showProv);
  if(s.type==="text"){if(!o)return null;return (h?h+" ":"")+C.DIM+o+C.R;}
  if(s.type==="ctxfrac"){   // 컨텍스트를 분수로: 396k/1M (막대·% 없음). 토큰 필드 없으면 %로 폴백
    if(!o)return null;
    const tok=Number(o.total_input_tokens), size=Number(o.context_window_size);
    // 사용량 0이면(세션 처음, 아직 안 채워짐) 숨김 — 스푸리어스 "0/1M" 방지(첫 사용 후 표시)
    if(Number.isFinite(tok)&&tok>0&&Number.isFinite(size)&&size>0)
      return (h?h+" ":"")+C.DIM+hum(tok)+"/"+hum(size)+C.R;
    const p=Number(o.used_percentage);
    return (Number.isFinite(p)&&p>0)?(h?h+" ":"")+C.DIM+Math.round(p)+"%"+C.R:null;
  }
  if(s.type==="effort"){    // "<level> effort". max면 max 단어만 보라 그라데이션, 나머지·effort는 흐리게
    if(!o)return null;
    if(o==="max")return (h?h+" ":"")+grad("max",[203,166,247],[124,58,237])+C.DIM+" effort"+C.R;
    return (h?h+" ":"")+C.DIM+o+" effort"+C.R;
  }
  if(!o)return null;
  const raw=Number(o.used_percentage);
  if(!Number.isFinite(raw))return null;   // 숫자 아니면 NaN% 대신 항목 숨김
  const p=Math.max(0,Math.min(100,Math.round(raw)));   // 0~100 클램프
  let out=(h?h+SP:"")+bar(p)+SP+C.B+(oneLine?String(p):String(p).padStart(3))+"%"+C.R;   // 막대=사용률색 / %글씨=항상 흰색(bold)
  if(s.type==="limit"){
    const t=ms(o), expired=t!=null&&Date.now()>=t;   // 윈도우가 이미 리셋됨 → 카운트다운 무의미
    if(!expired){const rs=resetStr(o);if(rs)out+=SP+C.DIM+"· "+rs+C.R;}
  }
  return out;
};

let lines=cfg.rows.map(row=>{
  const seen=new Set(); const parts=[];
  for(const key of row){
    const isSep=(key==="sep"||key==="|");
    const s=SEG[key], prov=s&&s.prov;
    const r=render(key, !prov||!seen.has(prov));  // 공급자 첫 등장에만 태그 표시
    if(r==null)continue;
    if(prov)seen.add(prov);
    parts.push({sep:isSep,t:r});
  }
  // 구분선 정리: 맨 앞/뒤 sep와 연속 sep 제거(빈 cx 등으로 이중 구분선·끝 구분선 생기는 것 방지)
  const out=[];
  for(const p of parts){ if(p.sep&&(out.length===0||out[out.length-1].sep))continue; out.push(p); }
  while(out.length&&out[out.length-1].sep)out.pop();
  return out.map(p=>p.t).join(JN);
}).filter(Boolean);
// CC 한도가 설정됐는데 rate_limits가 없으면(세션 처음 로딩 전, 또는 오래 유휴로 식음) → statusline 통째로 비움.
// 모델·effort 등 부분만 외롭게 띄우지 않음(빈 출력은 v1.0.2에 따라 캐시 안 함 → 첫 활동 시 즉시 복구).
if(!standalone && cfg.rows.some(r=>r.includes("5h")||r.includes("7d")) && !rl.five_hour && !rl.seven_day){
  lines=[];
}

// #4 진단: CC_USAGE_DEBUG(또는 --debug) 시 파싱·설정·codex 상태를 stderr로 덤프
if(env.CC_USAGE_DEBUG){
  const KNOWN=["SEGMENTS","SEGMENTS_WIDE","SEGMENTS_STANDALONE","WIDE_AT","RESET","STYLE","BARS","WARN","CRIT","THRESHOLD","CODEX_DIR","CACHE_TTL","STALE_MIN","WATCH_SECS","UPDATE","UPDATE_DAYS","TAG_CC","TAG_CX","TAG_5H","TAG_7D","TAG_CTX","TAGCOLOR_CC","TAGCOLOR_CX","CONFIG","DEBUG","CODEX_LINE","STANDALONE","TMUX","TMUX_DEDUP","TMUX_DIM"].map(k=>"CC_USAGE_"+k);
  const unknown=Object.keys(env).filter(k=>k.indexOf("CC_USAGE_")===0&&KNOWN.indexOf(k)<0);
  const pc=o=>o&&o.used_percentage!=null?o.used_percentage+"%":"-";
  const px=o=>o&&o.used_percent!=null?o.used_percent+"%":"-";
  const E=process.stderr;
  E.write("[quotabar debug]\n");
  E.write("  rate_limits: "+(d.rate_limits?"five_hour="+pc(rl.five_hour)+" seven_day="+pc(rl.seven_day):"MISSING from stdin")+"\n");
  E.write("  ctx="+pc(d.context_window)+" cost="+(d.cost&&d.cost.total_cost_usd!=null?"$"+d.cost.total_cost_usd:"-")+" model="+(clean(d.model&&d.model.display_name)||"-")+"\n");
  E.write("  config: segments="+JSON.stringify(cfg.rows)+" reset="+cfg.reset+" style="+(cfg.ascii?"ascii":"unicode")+" bars="+cfg.width+" warn="+cfg.warn+" crit="+cfg.crit+" color="+(cfg.color?"on":"off")+"\n");
  E.write("  tags: cc="+tag.cc+" cx="+tag.cx+" 5h="+tag["5h"]+" 7d="+tag["7d"]+" ctx="+tag.ctx+"\n");
  E.write("  codex: file="+(clean(codexFile)||"(none)")+" staleMin="+staleMin+" stale="+codexStale+" ageMin="+(cxTs?Math.floor((Date.now()-cxTs)/60000):"-")+" primary="+px(cx.primary)+" secondary="+px(cx.secondary)+"\n");
  E.write("  mode: standalone="+standalone+" tmux="+tmux+(standalone?" ccSnapAgeMin="+(ccSnapAge<0?"(none)":ccSnapAge):"")+(standalone&&!lines.length?"  (empty: no fresh CC/Codex data — disappears by design)":"")+"\n");
  if(unknown.length)E.write("  WARNING unknown CC_USAGE_* keys (typo?): "+unknown.map(clean).join(", ")+"\n");
}
let outStr=lines.join("\n");
if(tmux)outStr=toTmux(outStr);   // tmux 상태바용 #[...] 마크업으로 변환(--tmux)
process.stdout.write(outStr);
')
printf '%s' "$out$upd_hint"   # upd_hint: CC_USAGE_UPDATE=on이고 새 버전 감지됐을 때만, 아니면 빈 문자열
# 캐시 갱신(실패해도 무시). 빈 출력은 캐시 안 함: 첫 세션(rate_limits 도착 전)의
# 빈 결과가 TTL 동안 물려 정상화를 지연시키는 걸 막음 → 첫 메시지 직후 즉시 바 표시.
if [ "$ttl" -gt 0 ] && [ -n "$out" ]; then
  mkdir -p "$cache_dir" 2>/dev/null && { printf '%s' "$out" > "$cache.o" && date +%s > "$cache.t"; } 2>/dev/null
fi
