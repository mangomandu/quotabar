#!/usr/bin/env bash
# cc-usage-statusline — Claude Code statusline
# Claude Code(공식 rate_limits) + Codex(세션 파일 rate_limits)의 5시간/주간 한도,
# 그리고 컨텍스트/모델/비용을 막대 바 + 색상으로 표시. 외부 의존성 없음(node 제외).
#
# 설정(환경변수, 모두 선택):
#   CC_USAGE_SEGMENTS  표시 항목/배치. 기본 "5h,7d".
#                      항목: 5h 7d ctx model cost  cx5h cx7d  (cx*=Codex)
#                      "," = 같은 줄에 나란히,  ";" = 줄바꿈.
#                      예) "5h,7d;cx5h,cx7d" → CC 한 줄, Codex 한 줄 (총 2줄)
#   CC_USAGE_RESET     리셋 표시: relative(기본,"4h00m") | clock("→18:40") | both
#   CC_USAGE_TAG_CC    "CC" 자리 라벨(기본 "CC"). 아무 글자/이모지로 교체 (예: 🟧)
#   CC_USAGE_TAG_CX    "Cx" 자리 라벨(기본 "Cx").                    (예: 🟦)
#   CC_USAGE_TAG_5H    "5h" 자리 라벨(기본 "5h").                    (예: ⏳)
#   CC_USAGE_TAG_7D    "7d" 자리 라벨(기본 "7d").                    (예: 📅)
#   CC_USAGE_TAG_CTX   "ctx" 자리 라벨(기본 "ctx").                  (예: 🧠)
#   CC_USAGE_TAGCOLOR_CC  CC 태그 색: 이름(orange,purple,red…) 또는 256색번호. 단색기호(✿☁)에만 효과
#   CC_USAGE_TAGCOLOR_CX  Cx 태그 색
#   CC_USAGE_STYLE     unicode(기본) | ascii   (막대를 #,- 로: 옛 터미널용)
#   CC_USAGE_BARS      막대 칸 수(기본 10)
#   CC_USAGE_WARN      노랑 임계 %(기본 50)
#   CC_USAGE_CRIT      빨강 임계 %(기본 80)
#   CC_USAGE_CODEX_DIR Codex 세션 루트(기본 ~/.codex/sessions)
#   NO_COLOR           비어있지 않게 설정 시 색상 비활성(no-color.org 관례)
#
# 위 변수들은 설정 파일 ~/.claude/cc-usage.conf 에 "KEY=value" 한 줄씩 적어두면
# 자동으로 적용됩니다(JSON 편집 불필요). 환경변수가 있으면 환경변수가 우선.
# 파일 위치는 CC_USAGE_CONFIG 로 바꿀 수 있습니다.

command -v node >/dev/null 2>&1 || { printf '⏳ cc-usage: node not found'; exit 0; }

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

node -e '
const fs=require("fs");
let d={};try{d=JSON.parse(fs.readFileSync(0,"utf8"))}catch(e){}
const rl=d.rate_limits||{};

const env=process.env;
const cfg={
  rows:(env.CC_USAGE_SEGMENTS||"5h,7d").split(";")
        .map(r=>r.split(",").map(s=>s.trim()).filter(Boolean)).filter(r=>r.length),
  reset:env.CC_USAGE_RESET||"relative",
  ascii:(env.CC_USAGE_STYLE||"unicode")==="ascii",
  width:Math.max(1,parseInt(env.CC_USAGE_BARS||"10",10)||10),
  warn:parseInt(env.CC_USAGE_WARN||"50",10),
  crit:parseInt(env.CC_USAGE_CRIT||"80",10),
  color:!env.NO_COLOR,
};

// Codex: cx 세그먼트가 있을 때만 최신 세션 파일 끝부분(≤256KB)에서 마지막 rate_limits 추출.
// 서브셸(ls/tail/grep) 없이 node 안에서 처리 → 가벼움. primary=5h, secondary=weekly.
let cx={};
if(cfg.rows.some(r=>r.includes("cx5h")||r.includes("cx7d"))){
  try{
    const root=env.CC_USAGE_CODEX_DIR||require("os").homedir()+"/.codex/sessions";
    let newest=null,nm=-1;
    const walk=(dir,depth)=>{
      let ents;try{ents=fs.readdirSync(dir,{withFileTypes:true})}catch(e){return}
      for(const e of ents){const p=dir+"/"+e.name;
        if(depth<3){if(e.isDirectory())walk(p,depth+1)}
        else if(e.isFile()&&e.name.startsWith("rollout-")&&e.name.endsWith(".jsonl")){
          let m;try{m=fs.statSync(p).mtimeMs}catch(_){continue}
          if(m>nm){nm=m;newest=p}}}
    };
    walk(root,0);
    if(newest){
      const fd=fs.openSync(newest,"r"),sz=fs.fstatSync(fd).size,n=Math.min(sz,262144);
      const b=Buffer.alloc(n);fs.readSync(fd,b,0,n,sz-n);fs.closeSync(fd);
      const arr=b.toString("utf8").split("\n");
      for(let i=arr.length-1;i>=0;i--){
        if(arr[i].includes("\"rate_limits\"")){
          try{cx=JSON.parse(arr[i]).payload.rate_limits||{}}catch(_){}
          if(Object.keys(cx).length)break;
        }
      }
    }
  }catch(e){}
}
const cxNorm=o=>o?{used_percentage:o.used_percent,resets_at:o.resets_at}:null;
// 라벨 태그: 공급자(cc/cx) + 윈도우(5h/7d) + ctx. 기본은 글자, 무엇이든(이모지 포함) 교체 가능.
const tag={
  cc:  env.CC_USAGE_TAG_CC  ?? "CC",
  cx:  env.CC_USAGE_TAG_CX  ?? "Cx",
  "5h":env.CC_USAGE_TAG_5H  ?? "5h",
  "7d":env.CC_USAGE_TAG_7D  ?? "7d",
  ctx: env.CC_USAGE_TAG_CTX ?? "ctx",
};

const C=cfg.color?{R:"\x1b[0m",DIM:"\x1b[2m",B:"\x1b[1m",g:"\x1b[32m",y:"\x1b[33m",r:"\x1b[31m"}
                 :{R:"",DIM:"",B:"",g:"",y:"",r:""};
const col=p=>p>=cfg.crit?C.r:p>=cfg.warn?C.y:C.g;
const G=cfg.ascii?{fill:"#",empty:"-"}:{fill:"▰",empty:"▱"};
// 태그 색(공급자 라벨용): 색 이름 또는 256색 번호 → ANSI. 컬러 이모지(🟧)엔 영향 없음, 단색 기호(✿☁)에 색.
const NAMED={black:0,red:196,green:46,yellow:226,blue:39,magenta:201,cyan:51,white:255,
  orange:208,purple:135,violet:99,pink:213,gray:244,grey:244,teal:44,lime:118};
const tcol=spec=>{
  if(!cfg.color||!spec)return"";
  const n=/^\d+$/.test(spec)?parseInt(spec,10):NAMED[String(spec).toLowerCase()];
  return (n==null||isNaN(n))?"":`\x1b[38;5;${n}m`;
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

// prov=공급자 태그키(cc/cx), win=윈도우 태그키(5h/7d), tagKey=단일 태그(ctx 등)
const SEG={
  "5h":   {prov:"cc", win:"5h", type:"limit", get:()=>rl.five_hour},
  "7d":   {prov:"cc", win:"7d", type:"limit", get:()=>rl.seven_day},
  "cx5h": {prov:"cx", win:"5h", type:"limit", get:()=>cxNorm(cx.primary)},
  "cx7d": {prov:"cx", win:"7d", type:"limit", get:()=>cxNorm(cx.secondary)},
  "ctx":  {tagKey:"ctx", type:"pct",  get:()=>d.context_window},
  "model":{type:"text", get:()=>d.model&&d.model.display_name},
  "cost": {type:"text", get:()=>{const c=Number(d.cost&&d.cost.total_cost_usd);return Number.isFinite(c)?"$"+c.toFixed(2):null;}},
};
// 머리말 = 공급자태그 + 윈도우태그 (예: 기본 "CC 5h", 커스텀 "🟧 ⏳"). ctx는 단일 태그. model/cost는 없음.
const head=s=>{
  if(s.prov){
    const pt=tag[s.prov],wt=tag[s.win],pc=provColor[s.prov];
    const provPart=pt?(pc?pc+pt+C.R:pt):"";   // 공급자 태그에 지정색 입힘(있으면)
    return [provPart,wt].filter(Boolean).join(" ");
  }
  if(s.tagKey)return tag[s.tagKey]||"";
  return "";
};
const render=key=>{
  const s=SEG[key];if(!s)return null;
  const o=s.get();
  const h=head(s);
  if(s.type==="text"){if(!o)return null;return (h?h+" ":"")+C.DIM+o+C.R;}
  if(!o)return null;
  const raw=Number(o.used_percentage);
  if(!Number.isFinite(raw))return null;   // 숫자 아니면 NaN% 대신 항목 숨김
  const p=Math.round(raw);
  let out=(h?h+"  ":"")+bar(p)+"  "+col(p)+C.B+String(p).padStart(3)+"%"+C.R;
  if(s.type==="limit"){const rs=resetStr(o);if(rs)out+="  "+C.DIM+"· "+rs+C.R;}
  return out;
};

const lines=cfg.rows
  .map(row=>row.map(render).filter(Boolean).join("   "))
  .filter(Boolean);
process.stdout.write(lines.join("\n"));
'
