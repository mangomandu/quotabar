#!/usr/bin/env bash
# quotabar v1.2.5 — Claude Code statusline  (https://github.com/mangomandu/quotabar)
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
#   CC_USAGE_UPDATE    on 설정 시 기본 7일에 1회 백그라운드로 새 버전 확인 후 막대 끝에 '⬆ vX' 표시. 기본 off.
#                      렌더는 안 막음(detached). 수동 갱신은 'statusline.sh --update'(언제든, 네트워크 필요).
#   CC_USAGE_UPDATE_DAYS  위 확인 간격(일). 기본 7. 렌더 비용은 간격과 무관(파일 1회 읽기뿐).
#   CC_USAGE_DEBUG     설정 시(또는 첫 인자 --debug) 파싱·설정·codex 진단을 stderr로 출력
#   NO_COLOR           비어있지 않게 설정 시 색상 비활성(no-color.org 관례)
#
# 위 변수들은 설정 파일 ~/.claude/cc-usage.conf 에 "KEY=value" 한 줄씩 적어두면
# 자동으로 적용됩니다(JSON 편집 불필요). 환경변수가 있으면 환경변수가 우선.
# 파일 위치는 CC_USAGE_CONFIG 로 바꿀 수 있습니다.

VER="1.2.5"   # 헤더의 'quotabar vX.Y.Z'와 동일하게 유지 — 업데이트 비교/표시에 사용

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

# 현재 epoch초 → $_NOW. EPOCHSECONDS는 bash5+에서만 동적 빌트인 — 옛 bash(3.2)에선 동명 환경변수가
# 고정값으로 새어들 수 있어 TTL/throttle가 얼어붙음(Codex 리뷰 P2). 그래서 bash5+에서만 신뢰하고
# 아니면 date로 폴백. bash5 경로는 변수 직접 읽기라 fork 0(핫패스 절약 유지).
if [ "${BASH_VERSINFO:-0}" -ge 5 ] 2>/dev/null; then _qb_now(){ _NOW=$EPOCHSECONDS; }
else _qb_now(){ _NOW=$(date +%s 2>/dev/null||echo 0); }; fi

# 수동 업데이트: 최신 statusline.sh를 받아 자기 자신을 덮어씀(언제든, node 불필요)
if [ "${1:-}" = "--update" ]; then
  _self="${BASH_SOURCE[0]:-$0}"; _tmp="$(mktemp 2>/dev/null)" || { echo "✗ mktemp failed"; exit 1; }
  if curl -fsSL "https://raw.githubusercontent.com/mangomandu/quotabar/main/statusline.sh" -o "$_tmp" 2>/dev/null && [ -s "$_tmp" ] && grep -q '^# quotabar v' "$_tmp" 2>/dev/null && bash -n "$_tmp" 2>/dev/null; then
    # quotabar 헤더 + bash 문법검사(bash -n)를 통과할 때만 덮어씀 — 404 HTML이나 중간에 끊긴(truncated)
    # 다운로드는 node -e '…' 문자열이 안 닫혀 'bash -n'에서 잡힘 → 자기 자신을 깨먹지 않음 (Codex 리뷰 P1)
    chmod +x "$_tmp" 2>/dev/null
    if mv "$_tmp" "$_self" 2>/dev/null; then
      rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/quotabar/.update-available" 2>/dev/null
      echo "✓ quotabar updated → $_self"; exit 0
    fi
  fi
  rm -f "$_tmp" 2>/dev/null; echo "✗ quotabar update failed (network or permissions)"; exit 1
fi

command -v node >/dev/null 2>&1 || { printf '⏳ cc-usage: node not found'; exit 0; }

[ "$1" = "--debug" ] && export CC_USAGE_DEBUG=1   # 진단 출력(stderr). CC_USAGE_DEBUG=1 로도 가능

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
IN=$(</dev/stdin)                                          # stdin(JSON) 캡처 — cat fork 없이 빌트인으로 읽음(핫패스 절약)
ttl="${CC_USAGE_CACHE_TTL:-2}"; case "$ttl" in *[!0-9]*) ttl=0;; esac
sid=default
case "$IN" in *'"session_id":"'*) sid="${IN#*\"session_id\":\"}"; sid="${sid%%\"*}";; esac
case "$sid" in *[!A-Za-z0-9._-]*|'') sid=default;; esac     # 안전한 파일명만
# 반응형: 터미널이 넓으면(COLUMNS≥WIDE_AT) WIDE 레이아웃 사용. COLUMNS는 Claude Code가 줌(공짜).
cols="${COLUMNS:-0}"; case "$cols" in ''|*[!0-9]*) cols=0;; esac
wat="${CC_USAGE_WIDE_AT:-120}"; case "$wat" in ''|*[!0-9]*) wat=120;; esac
lw=n
if [ -n "${CC_USAGE_SEGMENTS_WIDE:-}" ] && [ "$cols" -ge "$wat" ]; then export CC_USAGE_SEGMENTS="$CC_USAGE_SEGMENTS_WIDE"; lw=w; fi
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/quotabar"; cache="$cache_dir/$sid-$lw"   # 폭(레이아웃)별 캐시

# --- 업데이트 알림(opt-in: CC_USAGE_UPDATE=on). 기본 7일에 1회만 백그라운드로 버전 확인 — 렌더는 안 막음(detached).
#     간격은 CC_USAGE_UPDATE_DAYS로 조정. 기본(off)일 땐 문자열 비교 1번이 전부.
#     on이어도 핫패스는 EPOCHSECONDS(빌트인)+파일 1회 읽기, fork 0 — 간격이 길든 짧든 렌더 비용은 동일.
upd_hint=""; _uon=0
# 명시적 truthy 값일 때만 켬 — false/0/no/off/오타는 네트워크 안 건드림(Codex 리뷰 P2). case라 fork 0 + bash3 안전.
case "${CC_USAGE_UPDATE:-}" in on|On|ON|1|true|True|TRUE|yes|Yes|YES) _uon=1;; esac
if [ "$_uon" = 1 ]; then
  _qb_now; _unow=$_NOW
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
  _qb_now; _now=$_NOW   # bash5+면 fork 0, 아니면 date 폴백(_qb_now 정의 참조)
  if [ "$(( _now - _ts ))" -ge 0 ] && [ "$(( _now - _ts ))" -lt "$ttl" ]; then
    printf '%s%s' "$(<"$cache.o")" "$upd_hint"; exit 0   # cat fork 없이 캐시 출력(핫패스). 캐시는 trailing 개행 없이 기록됨
  fi
fi

out=$(printf '%s' "$IN" | node -e '
const fs=require("fs");
let d={};try{d=JSON.parse(fs.readFileSync(0,"utf8"))}catch(e){}
const rl=d.rate_limits||{};
const clean=s=>String(s==null?"":s).replace(/[\x00-\x1f\x7f-\x9f]/g,"");  // 터미널 제어문자(ESC 등) 제거 = 인젝션 방지

const env=process.env;
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

// Codex: cx 세그먼트가 있을 때만. rollout 파일들을 mtime 최신순으로 정렬해, rate_limits를 가진
// 파일을 만날 때까지 새 것부터 시도(상한 8개). 갓 시작한 새 세션(rollout은 생겼지만 아직 rate_limits를
// 안 쓴 상태)이 직전 세션의 유효한 한도를 가리는 것을 방지(Codex 리뷰 P2). 각 파일은 끝에서 점점
// 키워가며(256KB→최대 4MB) 읽어 큰 세션도 안 놓침. 흔한 경우(최신 파일에 데이터 있음)는 1개만 읽음.
let cx={},cxTs=0,codexFile=null,codexTried=0;
if(cfg.rows.some(r=>r.includes("cx5h")||r.includes("cx7d"))){
  try{
    const root=env.CC_USAGE_CODEX_DIR||require("os").homedir()+"/.codex/sessions";
    const cand=[];   // [mtimeMs, path] 전부 수집(stat만 — 기존과 동일 비용) 후 최신순 정렬
    const walk=(dir,depth)=>{
      let ents;try{ents=fs.readdirSync(dir,{withFileTypes:true})}catch(e){return}
      for(const e of ents){const p=dir+"/"+e.name;
        if(depth<3){if(e.isDirectory())walk(p,depth+1)}
        else if(e.isFile()&&e.name.startsWith("rollout-")&&e.name.endsWith(".jsonl")){
          let m;try{m=fs.statSync(p).mtimeMs}catch(_){continue}
          cand.push([m,p]);}}
    };
    walk(root,0);
    cand.sort((a,b)=>b[0]-a[0]);              // mtime 내림차순(최신 먼저)
    if(cand.length)codexFile=cand[0][1];      // 진단/경고 표시용: 가장 최신 파일
    const readLimits=file=>{                  // 한 파일 tail에서 마지막 rate_limits → {r,ts} (없으면 r={})
      let r={},ts=0;
      const fd=fs.openSync(file,"r"),sz=fs.fstatSync(fd).size;
      for(let chunk=262144;;chunk*=4){
        const n=Math.min(sz,chunk);
        const b=Buffer.alloc(n);fs.readSync(fd,b,0,n,sz-n);
        const arr=b.toString("utf8").split("\n");
        const start=(n<sz)?1:0;   // 전체를 안 읽었으면 잘린 첫 줄은 버림
        for(let i=arr.length-1;i>=start;i--){
          if(arr[i].includes("\"rate_limits\"")){
            try{const pj=JSON.parse(arr[i]);if(pj.payload&&pj.payload.rate_limits){r=pj.payload.rate_limits;ts=Date.parse(pj.timestamp)||0}}catch(_){}
            if(Object.keys(r).length)break;
          }
        }
        if(Object.keys(r).length||n>=sz||chunk>=4194304)break;
      }
      fs.closeSync(fd);
      return {r,ts};
    };
    for(let i=0;i<cand.length&&i<8;i++){      // 최신순으로 최대 8개까지: 첫 성공에서 멈춤
      codexTried++;
      let got;try{got=readLimits(cand[i][1])}catch(_){continue}
      if(Object.keys(got.r).length){cx=got.r;cxTs=got.ts;codexFile=cand[i][1];break;}
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

const staleMin=parseInt(env.CC_USAGE_STALE_MIN||"30",10);  // Codex가 이 분(min) 넘게 안 돌면 idle 로 접음
const codexStale=cxTs>0&&staleMin>0&&Date.now()-cxTs>staleMin*60000;
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
let cxNaShown=false;     // Codex가 rate_limits 이벤트는 쓰지만 primary/secondary가 null이면 Cx n/a를 1회 표시
const render=(key,showProv)=>{
  if(key==="sep"||key==="|")return C.DIM+"│"+C.R;   // 구분선(예: 같은 줄에서 CC│Cx)
  const s=SEG[key];if(!s)return null;
  if(s.prov==="cx"&&codexStale){   // Codex 스테일 → 막대 대신 Cx idle 을 그 자리에(첫 cx만), 나머지 cx는 숨김
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
  if(!o){
    if(s.prov==="cx"&&cxTs>0&&!cxNaShown){
      cxNaShown=true;
      const cxt=tag.cx||"Cx";
      return (provColor.cx?provColor.cx+cxt+C.R:C.DIM+cxt+C.R)+C.DIM+" n/a"+C.R;
    }
    return null;
  }
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
if(cfg.rows.some(r=>r.includes("5h")||r.includes("7d")) && !rl.five_hour && !rl.seven_day){
  lines=[];
}

// #4 진단: CC_USAGE_DEBUG(또는 --debug) 시 파싱·설정·codex 상태를 stderr로 덤프
if(env.CC_USAGE_DEBUG){
  const KNOWN=["SEGMENTS","SEGMENTS_WIDE","WIDE_AT","RESET","STYLE","BARS","WARN","CRIT","THRESHOLD","CODEX_DIR","CACHE_TTL","STALE_MIN","UPDATE","UPDATE_DAYS","TAG_CC","TAG_CX","TAG_5H","TAG_7D","TAG_CTX","TAGCOLOR_CC","TAGCOLOR_CX","CONFIG","DEBUG","CODEX_LINE"].map(k=>"CC_USAGE_"+k);
  const unknown=Object.keys(env).filter(k=>k.indexOf("CC_USAGE_")===0&&KNOWN.indexOf(k)<0);
  const pc=o=>o&&o.used_percentage!=null?o.used_percentage+"%":"-";
  const px=o=>o&&o.used_percent!=null?o.used_percent+"%":"-";
  const E=process.stderr;
  E.write("[quotabar debug]\n");
  E.write("  rate_limits: "+(d.rate_limits?"five_hour="+pc(rl.five_hour)+" seven_day="+pc(rl.seven_day):"MISSING from stdin")+"\n");
  E.write("  ctx="+pc(d.context_window)+" cost="+(d.cost&&d.cost.total_cost_usd!=null?"$"+d.cost.total_cost_usd:"-")+" model="+(clean(d.model&&d.model.display_name)||"-")+"\n");
  E.write("  config: segments="+JSON.stringify(cfg.rows)+" reset="+cfg.reset+" style="+(cfg.ascii?"ascii":"unicode")+" bars="+cfg.width+" warn="+cfg.warn+" crit="+cfg.crit+" color="+(cfg.color?"on":"off")+"\n");
  E.write("  tags: cc="+tag.cc+" cx="+tag.cx+" 5h="+tag["5h"]+" 7d="+tag["7d"]+" ctx="+tag.ctx+"\n");
  E.write("  codex: file="+(clean(codexFile)||"(none)")+" tried="+codexTried+" staleMin="+staleMin+" stale="+codexStale+" ageMin="+(cxTs?Math.floor((Date.now()-cxTs)/60000):"-")+" primary="+px(cx.primary)+" secondary="+px(cx.secondary)+"\n");
  // rollout 파일이 있고 최신순 N개를 다 봤는데도 rate_limits가 안 나오면 = 포맷 변경 신호일 수 있음 → 조용한 빈 바 대신 경고
  if(codexFile&&!Object.keys(cx).length)E.write("  WARNING Codex rollout(s) found but no rate_limits parsed in newest "+codexTried+" (format change?): "+clean(codexFile)+"\n");
  if(unknown.length)E.write("  WARNING unknown CC_USAGE_* keys (typo?): "+unknown.map(clean).join(", ")+"\n");
}
process.stdout.write(lines.join("\n"));
')
printf '%s' "$out$upd_hint"   # upd_hint: CC_USAGE_UPDATE=on이고 새 버전 감지됐을 때만, 아니면 빈 문자열
# 캐시 갱신(실패해도 무시). 빈 출력은 캐시 안 함: 첫 세션(rate_limits 도착 전)의
# 빈 결과가 TTL 동안 물려 정상화를 지연시키는 걸 막음 → 첫 메시지 직후 즉시 바 표시.
if [ "$ttl" -gt 0 ] && [ -n "$out" ]; then
  _qb_now; _wts=$_NOW
  mkdir -p "$cache_dir" 2>/dev/null && { printf '%s' "$out" > "$cache.o" && printf '%s\n' "$_wts" > "$cache.t"; } 2>/dev/null
fi
exit 0   # 캐시 쓰기 실패(읽기전용 캐시 등)가 스크립트 종료코드를 비0으로 만들지 않게 — 출력은 이미 위에서 냄 (Codex 리뷰 P2)
