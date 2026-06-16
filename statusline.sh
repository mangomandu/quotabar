#!/usr/bin/env bash
# quotabar v1.0.0 — Claude Code statusline  (https://github.com/mangomandu/quotabar)
# Claude Code(공식 rate_limits) + Codex(세션 파일 rate_limits)의 5시간/주간 한도,
# 그리고 컨텍스트/모델/비용을 막대 바 + 색상으로 표시. 외부 의존성 없음(node 제외).
#
# 설정(환경변수, 모두 선택):
#   CC_USAGE_SEGMENTS  표시 항목/배치. 기본 "5h,7d".
#                      항목: 5h 7d ctx model cost  cx5h cx7d  (cx*=Codex)  sep(구분선│)
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
#   CC_USAGE_DEBUG     설정 시(또는 첫 인자 --debug) 파싱·설정·codex 진단을 stderr로 출력
#   NO_COLOR           비어있지 않게 설정 시 색상 비활성(no-color.org 관례)
#
# 위 변수들은 설정 파일 ~/.claude/cc-usage.conf 에 "KEY=value" 한 줄씩 적어두면
# 자동으로 적용됩니다(JSON 편집 불필요). 환경변수가 있으면 환경변수가 우선.
# 파일 위치는 CC_USAGE_CONFIG 로 바꿀 수 있습니다.

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
IN=$(cat)                                                  # stdin(JSON) 캡처
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
if [ "$ttl" -gt 0 ] && [ -z "$CC_USAGE_DEBUG" ] && [ -f "$cache.o" ] && [ -f "$cache.t" ] && [ ! "$conf" -nt "$cache.t" ]; then
  IFS= read -r _ts < "$cache.t" 2>/dev/null || _ts=0
  case "$_ts" in ''|*[!0-9]*) _ts=0;; esac
  _now=$(date +%s 2>/dev/null || echo 0)
  if [ "$(( _now - _ts ))" -ge 0 ] && [ "$(( _now - _ts ))" -lt "$ttl" ]; then
    cat "$cache.o"; exit 0
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

// Codex: cx 세그먼트가 있을 때만, 모든 rollout 중 mtime 최신 파일에서 마지막 rate_limits 추출.
// 파일 끝에서 점점 키워가며(256KB→최대 4MB) 읽어 큰 세션도 안 놓침. 서브셸 없이 node로.
let cx={},cxTs=0,codexFile=null;
if(cfg.rows.some(r=>r.includes("cx5h")||r.includes("cx7d"))){
  try{
    const root=env.CC_USAGE_CODEX_DIR||require("os").homedir()+"/.codex/sessions";
    let nm=-1;  // 전 파일 mtime 최신 선택(가장 정확). 캐시가 호출 빈도를 낮춰줌.
    const walk=(dir,depth)=>{
      let ents;try{ents=fs.readdirSync(dir,{withFileTypes:true})}catch(e){return}
      for(const e of ents){const p=dir+"/"+e.name;
        if(depth<3){if(e.isDirectory())walk(p,depth+1)}
        else if(e.isFile()&&e.name.startsWith("rollout-")&&e.name.endsWith(".jsonl")){
          let m;try{m=fs.statSync(p).mtimeMs}catch(_){continue}
          if(m>nm){nm=m;codexFile=p}}}
    };
    walk(root,0);
    if(codexFile){
      const fd=fs.openSync(codexFile,"r"),sz=fs.fstatSync(fd).size;
      for(let chunk=262144;;chunk*=4){
        const n=Math.min(sz,chunk);
        const b=Buffer.alloc(n);fs.readSync(fd,b,0,n,sz-n);
        const arr=b.toString("utf8").split("\n");
        const start=(n<sz)?1:0;   // 전체를 안 읽었으면 잘린 첫 줄은 버림
        for(let i=arr.length-1;i>=start;i--){
          if(arr[i].includes("\"rate_limits\"")){
            try{const pj=JSON.parse(arr[i]);if(pj.payload&&pj.payload.rate_limits){cx=pj.payload.rate_limits;cxTs=Date.parse(pj.timestamp)||0}}catch(_){}
            if(Object.keys(cx).length)break;
          }
        }
        if(Object.keys(cx).length||n>=sz||chunk>=4194304)break;
      }
      fs.closeSync(fd);
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
const col=p=>thresh?(p>=cfg.crit?C.r:p>=cfg.warn?C.y:""):"";           // 기본 무채색, warn%↑ 노랑, crit%↑ 빨강만
const G=cfg.ascii?{fill:"#",empty:"-"}:{fill:"▰",empty:"▱"};
// 태그 색(공급자 라벨용): 색 이름 또는 256색 번호 → ANSI. 컬러 이모지(🟧)엔 영향 없음, 단색 기호(✿ ⬢)에 색.
const NAMED={black:0,red:196,green:46,yellow:226,blue:39,magenta:201,cyan:51,white:255,
  orange:208,purple:135,violet:99,pink:213,gray:244,grey:244,teal:44,lime:118,coral:209,
  claude:"#d77757",codex:"#5769f7"};   // claude=Claude 오렌지, codex=Codex 블루(밝은 쪽, 다크 가독성)
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
const SEG={
  "5h":   {prov:"cc", win:"5h", type:"limit", get:()=>rl.five_hour},
  "7d":   {prov:"cc", win:"7d", type:"limit", get:()=>rl.seven_day},
  "cx5h": {prov:"cx", win:"5h", type:"limit", get:()=>cxNorm(cx.primary)},
  "cx7d": {prov:"cx", win:"7d", type:"limit", get:()=>cxNorm(cx.secondary)},
  "ctx":  {tagKey:"ctx", type:"pct",  get:()=>d.context_window},
  "model":{type:"text", get:()=>clean(d.model&&d.model.display_name)||null},
  "cost": {type:"text", get:()=>{const c=Number(d.cost&&d.cost.total_cost_usd);return Number.isFinite(c)?"$"+c.toFixed(2):null;}},
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
const render=(key,showProv)=>{
  if(key==="sep"||key==="|")return C.DIM+"│"+C.R;   // 구분선(예: 같은 줄에서 CC│Cx)
  const s=SEG[key];if(!s)return null;
  if(s.prov==="cx"&&codexStale)return null;   // Codex 스테일 → 개별 막대 대신 collapse 토큰(아래)
  const o=s.get();
  const h=head(s,showProv);
  if(s.type==="text"){if(!o)return null;return (h?h+" ":"")+C.DIM+o+C.R;}
  if(!o)return null;
  const raw=Number(o.used_percentage);
  if(!Number.isFinite(raw))return null;   // 숫자 아니면 NaN% 대신 항목 숨김
  const p=Math.max(0,Math.min(100,Math.round(raw)));   // 0~100 클램프
  let out=(h?h+"  ":"")+bar(p)+"  "+C.B+String(p).padStart(3)+"%"+C.R;   // 막대=사용률색 / %글씨=항상 흰색(bold)
  if(s.type==="limit"){
    const t=ms(o), expired=t!=null&&Date.now()>=t;   // 윈도우가 이미 리셋됨 → 카운트다운 무의미
    if(!expired){const rs=resetStr(o);if(rs)out+="  "+C.DIM+"· "+rs+C.R;}
  }
  return out;
};

let lines=cfg.rows.map(row=>{
  const seen=new Set(), parts=[];
  for(const key of row){
    const s=SEG[key], prov=s&&s.prov;
    const r=render(key, !prov||!seen.has(prov));  // 공급자 첫 등장에만 태그 표시
    if(r==null)continue;
    if(prov)seen.add(prov);
    parts.push(r);
  }
  return parts.join("   ");
}).filter(Boolean);
// Codex 스테일 → Cx idle 한 토막으로 접어 CC(첫 줄) 뒤에 이어붙임
if(codexStale&&cfg.rows.some(r=>r.includes("cx5h")||r.includes("cx7d"))){
  const cxt=tag.cx||"Cx";
  const tok=(provColor.cx?provColor.cx+cxt+C.R:C.DIM+cxt+C.R)+C.DIM+" idle"+C.R;  // 공급자색 유지 + idle은 흐리게
  if(lines.length)lines[0]+="   "+tok; else lines=[tok];
}

// #4 진단: CC_USAGE_DEBUG(또는 --debug) 시 파싱·설정·codex 상태를 stderr로 덤프
if(env.CC_USAGE_DEBUG){
  const KNOWN=["SEGMENTS","SEGMENTS_WIDE","WIDE_AT","RESET","STYLE","BARS","WARN","CRIT","THRESHOLD","CODEX_DIR","CACHE_TTL","STALE_MIN","TAG_CC","TAG_CX","TAG_5H","TAG_7D","TAG_CTX","TAGCOLOR_CC","TAGCOLOR_CX","CONFIG","DEBUG","CODEX_LINE"].map(k=>"CC_USAGE_"+k);
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
  if(unknown.length)E.write("  WARNING unknown CC_USAGE_* keys (typo?): "+unknown.map(clean).join(", ")+"\n");
}
process.stdout.write(lines.join("\n"));
')
printf '%s' "$out"
# 캐시 갱신(실패해도 무시)
if [ "$ttl" -gt 0 ]; then
  mkdir -p "$cache_dir" 2>/dev/null && { printf '%s' "$out" > "$cache.o" && date +%s > "$cache.t"; } 2>/dev/null
fi
