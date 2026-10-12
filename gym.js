// GYM. Supabase stores the log; this browser only displays it.
(function(){
'use strict';
const $=id=>document.getElementById(id);
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const MUSCLES=['Chest','Back','Shoulders','Arms','Legs','Glutes','Core','Full body','Cardio','Other'];
const COLORS=['#3987e5','#d95926','#199e70','#c98500','#d55181','#008300','#9085e9','#e66767'];
const PAGE=1000;
const isoDay=d=>{ const x=new Date(d); return new Date(x.getTime()-x.getTimezoneOffset()*60000).toISOString().slice(0,10); };
const today=()=>isoDay(new Date());
const parseDay=s=>{ const [y,m,d]=s.split('-').map(Number); return new Date(y,m-1,d); };
const addDays=(s,n)=>isoDay(new Date(parseDay(s).getTime()+n*86400000+3600000*6));
const shortDate=s=>parseDay(s).toLocaleDateString([], {month:'short',day:'numeric'});
const longDate=s=>parseDay(s).toLocaleDateString([], {weekday:'short',month:'short',day:'numeric',year:'numeric'});
const weekStart=s=>{ const d=parseDay(s); const dow=(d.getDay()+6)%7; return addDays(s,-dow); }; // Monday
const num=n=>{ const v=Number(n)||0; return Number.isInteger(v)?String(v):v.toFixed(1).replace(/\.0$/,''); };
const fmtW=(w,u)=>Number(w)===0?'bodyweight':`${num(w)} ${u}`;
// Epley: a weight for reps estimates a one-rep max. One rep is just the weight.
const e1rm=(w,r)=>r<=1?w:w*(1+r/30);
// Bodyweight sets have no load to estimate from, so their headline is reps.
const bestText=(set,unit)=>set.weight>0?fmtW(e1rm(set.weight,set.reps).toFixed(0),unit):`${set.reps} reps`;

let client=null,user=null,busy=false,authSub=null,connecting=null,storageCleanup=null;
let exercises=[],sets=[],range='90',picked='',loadId=0,colorOf=new Map();

function message(id,text,kind=''){ $(id).textContent=text; $(id).className='message'+(kind?' '+kind:''); }
$('ex-muscle').innerHTML=MUSCLES.map(m=>`<option>${esc(m)}</option>`).join('');

// ---- connection: the two public Supabase settings come from /api/config ----
function projectConfig(v){ const url=typeof v?.url==='string'?v.url.trim().replace(/\/$/,''):'', key=typeof v?.key==='string'?v.key.trim():''; if(!/^https:\/\/[a-z0-9-]+\.supabase\.co$/.test(url)||!/^sb_publishable_[A-Za-z0-9_-]+$/.test(key)) throw new Error('This page needs its Supabase connection set up in Vercel.'); return {url,key}; }
async function connect(){
  if(client)return client; if(connecting)return connecting;
  connecting=(async()=>{ let r; try{ r=await fetch('/api/config',{cache:'no-store'}); }catch{ throw new Error('Could not connect. Check your internet connection and try again.'); }
    if(!r.ok) throw new Error('This page needs its Supabase connection set up in Vercel.'); return makeClient(projectConfig(await r.json())); })();
  try{ return await connecting; } finally{ connecting=null; }
}
function makeClient(config){
  if(!window.supabase) throw new Error('The connection library could not load. Reload the page.');
  const storageKey='gym.auth.'+new URL(config.url).hostname, storage=window.localStorage;
  authSub?.unsubscribe(); client?.auth.stopAutoRefresh(); storageCleanup?.();
  client=supabase.createClient(config.url,config.key,{auth:{storage,storageKey,persistSession:true,autoRefreshToken:true,detectSessionInUrl:false}});
  const mine=client;
  authSub=client.auth.onAuthStateChange((_e,session)=>{ setTimeout(()=>{ if(client!==mine)return; setUser(session&&storage.getItem(storageKey)?session.user:null); },0); }).data.subscription;
  const changed=e=>{ if(client===mine&&e.storageArea===storage&&(e.key===storageKey||e.key===null)&&e.newValue===null)setUser(null); };
  window.addEventListener('storage',changed); storageCleanup=()=>window.removeEventListener('storage',changed);
  return client;
}
function setUser(next){
  if(next?.id===user?.id)return;
  user=next; loadId++;
  $('connect-open').hidden=!!user;
  for(const id of ['sign-out','log-open','log-open-2','ex-open','csv-log']) $(id).hidden=!user;
  $('log-fields').disabled=!user; $('ex-fields').disabled=!user;
  $('connection-status').textContent=user?'Connected':'Your record'; $('connection-status').classList.toggle('connected',!!user);
  if(!user){ exercises=[]; sets=[]; picked=''; render(); $('log-list').innerHTML='<p class="row-empty">Sign in to see your workouts.</p>'; $('ex-list').innerHTML='<p class="row-empty">Sign in to see your exercises.</p>'; $('log-dialog').close(); $('ex-dialog').close(); }
  else load();
  window.coachUser?.(user?.id);
}
$('connect-open').onclick=()=>{ $('connection-dialog').showModal(); $('email').focus(); };
$('connect-close').onclick=()=>{ if(!busy)$('connection-dialog').close(); };
$('connect-form').addEventListener('submit',async e=>{
  e.preventDefault(); if(busy)return; busy=true; $('connect-submit').disabled=true; message('connect-message','Signing in…');
  try{ const db=await connect(); const {data,error}=await db.auth.signInWithPassword({email:$('email').value.trim(),password:$('password').value}); if(error)throw error; $('password').value=''; setUser(data.user); $('connection-dialog').close(); message('connect-message',''); }
  catch(err){ message('connect-message',err.message||'Could not sign in.','error'); }
  finally{ busy=false; $('connect-submit').disabled=false; }
});
$('sign-out').onclick=async()=>{ if(!client||busy)return; busy=true; try{ const {error}=await client.auth.signOut({scope:'local'}); if(error)throw error; setUser(null); }catch(err){ message('history-message',err.message,'error'); } finally{ busy=false; } };

// ---- reading all of it, and never some of it ----
async function readAll(make){ const all=[]; let from=0; for(;;){ const {data,error,count}=await make().range(from,from+PAGE-1); if(error)throw error; all.push(...data); from+=data.length; if(from>=count||!data.length)return all; } }
async function load(){
  const id=++loadId; message('history-message','');
  try{
    const db=await connect();
    const [e,s]=await Promise.all([
      readAll(()=>db.from('exercises').select('*',{count:'exact'}).order('name')),
      readAll(()=>db.from('sets').select('*',{count:'exact'}).order('performed_on',{ascending:false}).order('exercise_id').order('set_no'))
    ]);
    if(id!==loadId)return;
    exercises=e.map(r=>({...r,increment:Number(r.increment)})); sets=s.map(r=>({...r,weight:Number(r.weight),reps:Number(r.reps)}));
    if(!exercises.some(x=>x.id===picked)) picked=lastTrainedExercise()||exercises.find(x=>!x.archived)?.id||'';
    render();
  }catch(err){ if(id!==loadId)return; const missing=/relation .* does not exist|schema cache/i.test(err.message||''); message('history-message',missing?'Run setup.sql in your Supabase SQL editor once, then reload.':(err.message||'Could not load your training.'),'error'); }
}
function lastTrainedExercise(){ return sets[0]?.exercise_id||''; }

// ---- derived ----
const exById=id=>exercises.find(x=>x.id===id);
function colorFor(name){ if(!colorOf.has(name)) colorOf.set(name,COLORS[colorOf.size%COLORS.length]); return colorOf.get(name); }
// A session: every set of one exercise on one day.
function sessions(exerciseId){
  const m=new Map();
  for(const s of sets) if(s.exercise_id===exerciseId){ if(!m.has(s.performed_on)) m.set(s.performed_on,[]); m.get(s.performed_on).push(s); }
  return [...m].map(([day,rows])=>{ rows.sort((a,b)=>a.set_no-b.set_no); const best=rows.reduce((a,b)=>e1rm(b.weight,b.reps)>e1rm(a.weight,a.reps)?b:a,rows[0]); return {day,rows,best,e1rm:e1rm(best.weight,best.reps),top:Math.max(...rows.map(r=>r.weight)),volume:rows.reduce((a,r)=>a+r.weight*r.reps,0),note:rows.find(r=>r.note)?.note||''}; }).sort((a,b)=>a.day<b.day?-1:1);
}
// Progressive overload: hit every target set for target reps at one weight → add the increment. Otherwise, same weight again.
function suggest(ex){
  const hist=sessions(ex.id); if(!hist.length) return {weight:null,why:'No sessions yet. Start light and hit the target.'};
  const last=hist.at(-1); const w=last.top; const atTop=last.rows.filter(r=>r.weight===w);
  const hit=atTop.length>=ex.target_sets && atTop.every(r=>r.reps>=ex.target_reps);
  if(hit) return {weight:w+ex.increment,why:`You hit ${ex.target_sets}×${ex.target_reps} at ${fmtW(w,ex.unit)} on ${shortDate(last.day)}. Add ${num(ex.increment)} ${ex.unit}.`};
  const done=atTop.map(r=>r.reps).join('/');
  return {weight:w,why:`Last time: ${done} reps at ${fmtW(w,ex.unit)}. Reach ${ex.target_sets}×${ex.target_reps} to move up.`};
}
function isPR(exerciseId,day,value){ for(const s of sets) if(s.exercise_id===exerciseId&&s.performed_on<day&&e1rm(s.weight,s.reps)>=value) return false; return true; }

function render(){
  const t=today(), ws=weekStart(t);
  const days=[...new Set(sets.map(s=>s.performed_on))].sort().reverse();
  const weekDays=days.filter(d=>d>=ws);
  const weekVol=sets.filter(s=>s.performed_on>=ws).reduce((a,s)=>a+s.weight*s.reps,0);
  let streak=0; { let w=ws; const weeks=new Set(days.map(weekStart)); if(!weeks.has(w)) w=addDays(w,-7); while(weeks.has(w)){ streak++; w=addDays(w,-7); } }
  const monthStart=t.slice(0,8)+'01';
  let prs=0; for(const ex of exercises) for(const se of sessions(ex.id)) if(se.day>=monthStart&&isPR(ex.id,se.day,se.e1rm)) prs++;
  $('week-count').textContent=sets.length?String(weekDays.length):'—';
  $('week-note').textContent=sets.length?`${days.length} workout${days.length===1?'':'s'} logged · week of ${shortDate(ws)}`:'Your first workout starts here.';
  $('side-week').textContent=sets.length?String(weekDays.length):'—'; $('side-total').textContent=sets.length?String(days.length):'—';
  $('tile-last').textContent=days[0]?shortDate(days[0]):'—'; $('tile-last-note').textContent=days[0]?[...new Set(sets.filter(s=>s.performed_on===days[0]).map(s=>exById(s.exercise_id)?.name).filter(Boolean))].slice(0,3).join(', '):'';
  $('tile-volume').textContent=sets.length?num(weekVol):'—'; $('tile-volume-note').textContent=sets.length?`weight × reps · ${exercises[0]?.unit||'lbs'}`:'weight × reps';
  $('tile-streak').textContent=sets.length?String(streak):'—';
  $('tile-prs').textContent=sets.length?String(prs):'—';
  renderPicker(); renderNext(); drawLine(); renderLog(); renderLibrary();
}
function renderPicker(){
  const live=exercises.filter(x=>!x.archived);
  $('exercise-pick').innerHTML=live.length?live.map(x=>`<option value="${x.id}"${x.id===picked?' selected':''}>${esc(x.name)}</option>`).join(''):'<option value="">Add an exercise first</option>';
  $('exercise-pick').disabled=!live.length;
}
function renderNext(){
  const ex=exById(picked); $('next').hidden=!ex; if(!ex)return;
  const s=suggest(ex); $('next-label').textContent=`Next session · ${ex.name}`;
  $('next-plan').textContent=s.weight===null?`${ex.target_sets} × ${ex.target_reps}`:`${ex.target_sets} × ${ex.target_reps} at ${fmtW(s.weight,ex.unit)}`;
  $('next-why').textContent=s.why;
}

// ---- line: estimated one-rep max per session ----
let linePts=[];
function drawLine(){
  const svg=$('line-plot'), ex=exById(picked);
  const all=ex?sessions(ex.id):[]; const from=range==='all'?'0000-00-00':addDays(today(),-(Number(range)-1));
  const hist=all.filter(s=>s.day>=from); const bodyweight=hist.length>0&&hist.every(h=>h.top===0); if(bodyweight) for(const h of hist) h.e1rm=h.best.reps;
  $('line-title').textContent=ex?`Progress · ${ex.name}`:'Progress';
  $('line-sub').textContent=ex?(bodyweight?`Best reps per session${hist.length?` · best ${Math.max(...hist.map(h=>h.e1rm))} reps`:''}`:`Estimated one-rep max per session · ${ex.unit}${hist.length?` · best ${fmtW(Math.max(...hist.map(h=>h.e1rm)).toFixed(0),ex.unit)}`:''}`):'Estimated one-rep max per session';
  const has=hist.length>0; $('line-empty').hidden=has; svg.hidden=!has; if(!has){ svg.innerHTML=''; return; }
  const W=700,H=260,L=56,R=16,T=16,B=34;
  const vals=hist.map(h=>h.e1rm); const lo=Math.min(...vals), hi=Math.max(...vals); const pad=(hi-lo)*0.25||Math.max(hi*0.1,5); const min=Math.max(0,lo-pad), max=hi+pad;
  const t0=parseDay(hist[0].day).getTime(), t1=parseDay(hist.at(-1).day).getTime(); const span=t1-t0||1;
  const x=d=>hist.length===1?L+(W-L-R)/2:L+(parseDay(d).getTime()-t0)/span*(W-L-R); const y=v=>T+(H-T-B)*(1-(v-min)/(max-min));
  linePts=hist.map(h=>({...h,px:x(h.day),py:y(h.e1rm),pr:isPR(ex.id,h.day,h.e1rm)}));
  const path=linePts.map((p,i)=>`${i?'L':'M'}${p.px.toFixed(1)} ${p.py.toFixed(1)}`).join('');
  const area=`${path}L${linePts.at(-1).px.toFixed(1)} ${H-B}L${linePts[0].px.toFixed(1)} ${H-B}Z`;
  const ticks=[0,.5,1].map(f=>{ const v=min+(max-min)*f; return `<line class="grid" x1="${L}" x2="${W-R}" y1="${y(v)}" y2="${y(v)}"/><text x="${L-8}" y="${y(v)+4}" text-anchor="end">${Math.round(v)}</text>`; }).join('');
  const step=Math.ceil(linePts.length/6); const xl=linePts.filter((_,i)=>i%step===0||i===linePts.length-1).map(p=>`<text x="${p.px}" y="${H-10}" text-anchor="middle">${esc(shortDate(p.day))}</text>`).join('');
  const dots=linePts.map(p=>`<circle cx="${p.px}" cy="${p.py}" r="${p.pr?4.5:3.5}" fill="${p.pr?'#ffd0d0':'#ff9b9b'}" stroke="#0d0909" stroke-width="2"/>`).join('');
  svg.innerHTML=`<defs><linearGradient id="wash" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ff9b9b" stop-opacity=".18"/><stop offset="1" stop-color="#ff9b9b" stop-opacity="0"/></linearGradient></defs>${ticks}<line class="axis" x1="${L}" x2="${W-R}" y1="${H-B}" y2="${H-B}"/><path d="${area}" fill="url(#wash)"/><path d="${path}" fill="none" stroke="#ff9b9b" stroke-width="2" stroke-linejoin="round"/>${dots}${xl}<g id="line-focus"></g><rect class="hit" x="${L}" y="0" width="${W-L-R}" height="${H}"/>`;
}
function lineHover(e){
  if(!linePts.length)return; const svg=$('line-plot'), r=svg.getBoundingClientRect(); const mx=(e.clientX-r.left)/r.width*700;
  let best=linePts[0]; for(const p of linePts) if(Math.abs(p.px-mx)<Math.abs(best.px-mx)) best=p;
  $('line-focus').innerHTML=`<line x1="${best.px}" x2="${best.px}" y1="16" y2="226" stroke="#ff9b9b" stroke-opacity=".3"/><circle cx="${best.px}" cy="${best.py}" r="5.5" fill="#ffd0d0" stroke="#0d0909" stroke-width="2"/>`;
  const ex=exById(picked), tip=$('line-tip'), card=$('line-card').getBoundingClientRect();
  tip.innerHTML=`${esc(longDate(best.day))}${best.pr?'<span class="pr">PR</span>':''}<strong>${best.best.weight>0?esc(fmtW(best.e1rm.toFixed(0),ex.unit))+' est. 1RM':best.best.reps+' reps'}</strong>${best.rows.map(s=>`${num(s.weight)}×${s.reps}`).join(' · ')}`;
  tip.classList.remove('hidden'); tip.style.left=(r.left-card.left+best.px/700*r.width)+'px'; tip.style.top=(r.top-card.top+best.py/260*r.height)+'px';
}
$('line-plot').addEventListener('pointermove',lineHover); tapToRead($('line-plot'),lineHover,()=>{ $('line-tip').classList.add('hidden'); const f=$('line-focus'); if(f)f.innerHTML=''; });

// ---- lists ----
function renderLog(){
  const days=[...new Set(sets.map(s=>s.performed_on))].sort().reverse();
  $('log-count').textContent=days.length?`${days.length} workout${days.length===1?'':'s'}`:'';
  if(!days.length){ $('log-list').innerHTML='<p class="row-empty">No workouts yet. Log your first one to start the graph.</p>'; return; }
  $('log-list').innerHTML=days.slice(0,30).map(day=>{
    const byEx=new Map(); for(const s of sets) if(s.performed_on===day){ if(!byEx.has(s.exercise_id)) byEx.set(s.exercise_id,[]); byEx.get(s.exercise_id).push(s); }
    const vol=[...byEx.values()].flat().reduce((a,s)=>a+s.weight*s.reps,0);
    return `<div class="day-group"><div class="day-head">${esc(longDate(day))}<span>${byEx.size} exercise${byEx.size===1?'':'s'} · ${num(vol)} volume</span></div><div class="rows">${[...byEx].map(([exId,rows])=>{ const ex=exById(exId); if(!ex)return ''; rows.sort((a,b)=>a.set_no-b.set_no); const best=rows.reduce((a,b)=>e1rm(b.weight,b.reps)>e1rm(a.weight,a.reps)?b:a,rows[0]); const pr=isPR(exId,day,e1rm(best.weight,best.reps));
      return `<div class="row"><span class="dot" style="background:${colorFor(ex.muscle)}"></span><div class="who"><b>${esc(ex.name)}${pr?'<span class="pr">PR</span>':''}</b><small class="sets-line">${rows.map(s=>`${num(s.weight)}×${s.reps}`).join('  ')}${rows.find(r=>r.note)?' · '+esc(rows.find(r=>r.note).note):''}</small></div><span class="amt">${esc(bestText(best,ex.unit))}</span><div class="ops"><button class="text-button" data-log-edit="${exId}|${day}" type="button">Edit</button><button class="text-button" data-log-del="${exId}|${day}" type="button">Delete</button></div></div>`; }).join('')}</div></div>`;
  }).join('')+(days.length>30?`<p class="row-empty">Showing the latest 30 of ${days.length} workouts.</p>`:'');
}
function renderLibrary(){
  $('ex-count').textContent=exercises.length?`${exercises.length} total`:'';
  if(!exercises.length){ $('ex-list').innerHTML='<p class="row-empty">No exercises yet. Create one with a target, like 3 sets of 8, and GYM will tell you when to add weight.</p>'; return; }
  $('ex-list').innerHTML=exercises.map(ex=>{ const hist=sessions(ex.id); const bestSet=hist.length?hist.reduce((a,h)=>h.e1rm>a.e1rm?h:a,hist[0]).best:null; const s=suggest(ex);
    return `<div class="row" style="${ex.archived?'opacity:.5':''}"><span class="dot" style="background:${colorFor(ex.muscle)}"></span><div class="who"><b>${esc(ex.name)}</b><small>${esc(ex.muscle)} · target ${ex.target_sets}×${ex.target_reps} · +${num(ex.increment)} ${esc(ex.unit)} · ${hist.length} session${hist.length===1?'':'s'}</small></div><span class="lib-stat">${hist.length?`best ${esc(bestText(bestSet,ex.unit))} · next ${esc(fmtW(s.weight,ex.unit))}`:'not started'}</span><div class="ops"><button class="text-button" data-ex-chart="${ex.id}" type="button">Chart</button><button class="text-button" data-ex-edit="${ex.id}" type="button">Edit</button><button class="text-button" data-ex-del="${ex.id}" type="button">Delete</button></div></div>`; }).join('');
}


// Charts answer a tap as well as a hover: a touch pins the tooltip until you tap elsewhere.
// Marks in the same group share one tooltip, so moving between them swaps it instead of hiding it.
let lastPinned=null,lastGroup='';
function tapToRead(el,show,hide,group=''){
  let pinned=false;
  el.addEventListener('pointerdown',e=>{ show(e); pinned=e.pointerType!=='mouse'; if(pinned){ lastPinned=el; lastGroup=group; } });
  el.addEventListener('pointerleave',()=>{ if(!pinned) hide(); });
  document.addEventListener('pointerdown',e=>{ if(pinned&&!el.contains(e.target)){ pinned=false; if(!(group&&lastGroup===group&&lastPinned!==el&&lastPinned?.contains(e.target))) hide(); } });
}

// Download, or on a phone share, a CSV of your own rows.
async function exportCsv(name,header,rows){
  const q=v=>{ const s=String(v??''); return /[",\n\r]/.test(s)?'"'+s.replace(/"/g,'""')+'"':s; };
  const csv=[header,...rows].map(r=>r.map(q).join(',')).join('\r\n');
  const blob=new Blob(['﻿'+csv],{type:'text/csv;charset=utf-8'});
  try{ const file=new File([blob],name,{type:'text/csv'}); if(navigator.canShare&&navigator.canShare({files:[file]})){ await navigator.share({files:[file],title:name}); return; } }catch(err){ if(err?.name==='AbortError') return; }
  const a=document.createElement('a'); a.href=URL.createObjectURL(blob); a.download=name; document.body.appendChild(a); a.click(); setTimeout(()=>{ URL.revokeObjectURL(a.href); a.remove(); },1000);
}
$('csv-log').onclick=()=>exportCsv('gym-sets.csv',['date','exercise','set','weight','reps','unit','note'],sets.slice().sort((a,b)=>a.performed_on<b.performed_on?1:a.performed_on>b.performed_on?-1:a.set_no-b.set_no).map(s=>{ const ex=exById(s.exercise_id); return [s.performed_on,ex?.name||'',s.set_no,s.weight,s.reps,ex?.unit||'',s.note]; }));
// ---- forms ----
function parseNum(s,label){ const v=Number(String(s).replace(',','.')); if(!Number.isFinite(v)||v<0) throw new Error(`Enter a ${label} like 135.`); return Math.round(v*100)/100; }
function setRow(i,w='',r=''){ return `<div class="set-row"><span>${i+1}</span><input type="text" inputmode="decimal" placeholder="weight" value="${esc(w)}" aria-label="Set ${i+1} weight"><input type="number" inputmode="numeric" min="0" max="1000" placeholder="reps" value="${esc(r)}" aria-label="Set ${i+1} reps"><button type="button" aria-label="Remove set ${i+1}">×</button></div>`; }
function renumber(){ $('sets-grid').querySelectorAll('.set-row').forEach((row,i)=>{ row.querySelector('span').textContent=i+1; }); }
function fillSets(rows){ $('sets-grid').innerHTML=rows.map((r,i)=>setRow(i,r.weight,r.reps)).join(''); }
$('add-set').onclick=()=>{ const rows=$('sets-grid').querySelectorAll('.set-row'); const last=rows[rows.length-1]; const w=last?last.querySelector('input').value:''; $('sets-grid').insertAdjacentHTML('beforeend',setRow(rows.length,w,'')); $('sets-grid').lastElementChild.querySelector('input[type=number]').focus(); };
$('sets-grid').addEventListener('click',e=>{ const b=e.target.closest('button'); if(!b)return; if($('sets-grid').children.length>1){ b.closest('.set-row').remove(); renumber(); } });
function openLog(prefill){
  if(!user){ $('connection-dialog').showModal(); return; }
  const live=exercises.filter(x=>!x.archived); if(!live.length){ openEx(); return; }
  $('log-exercise').innerHTML=live.map(x=>`<option value="${x.id}">${esc(x.name)} (${esc(x.unit)})</option>`).join('');
  $('log-edit-key').value=''; $('log-title').textContent='Log workout.'; $('log-note').value='';
  if(prefill?.edit){ const [exId,day]=prefill.edit.split('|'); const rows=sets.filter(s=>s.exercise_id===exId&&s.performed_on===day).sort((a,b)=>a.set_no-b.set_no); $('log-exercise').value=exId; $('log-date').value=day; $('log-note').value=rows.find(r=>r.note)?.note||''; fillSets(rows.map(r=>({weight:num(r.weight),reps:r.reps}))); $('log-edit-key').value=prefill.edit; $('log-title').textContent='Edit workout.'; }
  else { const ex=exById(prefill?.exercise||picked)||live[0]; $('log-exercise').value=ex.id; $('log-date').value=today(); const s=suggest(ex); fillSets(Array.from({length:ex.target_sets},()=>({weight:s.weight===null?'':num(s.weight),reps:''}))); }
  message('log-message',''); $('log-dialog').showModal(); $('sets-grid').querySelector('input[type=number]').focus();
}
$('log-exercise').onchange=()=>{ if($('log-edit-key').value)return; const ex=exById($('log-exercise').value); if(!ex)return; const s=suggest(ex); fillSets(Array.from({length:ex.target_sets},()=>({weight:s.weight===null?'':num(s.weight),reps:''}))); };
function openEx(row){
  if(!user){ $('connection-dialog').showModal(); return; }
  $('ex-id').value=row?.id||''; $('ex-title').textContent=row?'Edit exercise.':'New exercise.'; $('ex-name').value=row?.name||''; $('ex-muscle').value=row?.muscle||'Chest'; $('ex-unit').value=row?.unit||'lbs'; $('ex-sets').value=row?.target_sets??3; $('ex-reps').value=row?.target_reps??8; $('ex-inc').value=row?num(row.increment):'5';
  message('ex-message',''); $('ex-dialog').showModal(); $('ex-name').focus();
}
$('log-open').onclick=()=>openLog(); $('log-open-2').onclick=()=>openLog(); $('next-log').onclick=()=>openLog({exercise:picked}); $('ex-open').onclick=()=>openEx();
$('log-close').onclick=()=>{ if(!busy)$('log-dialog').close(); }; $('ex-close').onclick=()=>{ if(!busy)$('ex-dialog').close(); };
for(const id of ['log-dialog','ex-dialog','connection-dialog']) $(id).addEventListener('cancel',e=>{ if(busy)e.preventDefault(); });
$('log-form').addEventListener('submit',async e=>{
  e.preventDefault(); if(busy||!user)return; busy=true; $('log-save').disabled=true;
  try{
    const exId=$('log-exercise').value, day=$('log-date').value, note=$('log-note').value.trim(); if(!exId||!day) throw new Error('Pick an exercise and a date.');
    const rows=[...$('sets-grid').querySelectorAll('.set-row')].map((r,i)=>{ const [w,reps]=r.querySelectorAll('input'); if(w.value===''&&reps.value==='') return null; return {exercise_id:exId,performed_on:day,set_no:i+1,weight:parseNum(w.value||'0','weight'),reps:Math.max(0,Math.round(Number(reps.value))),note:i===0?note:''}; }).filter(Boolean);
    if(!rows.length) throw new Error('Enter at least one set.'); if(rows.some(r=>!Number.isFinite(r.reps))) throw new Error('Enter reps for every set.');
    const db=await connect(); const key=$('log-edit-key').value;
    if(key){ const [oldEx,oldDay]=key.split('|'); const {error}=await db.from('sets').delete().eq('exercise_id',oldEx).eq('performed_on',oldDay); if(error)throw error; }
    else { const {count,error}=await db.from('sets').select('id',{count:'exact',head:true}).eq('exercise_id',exId).eq('performed_on',day); if(error)throw error; if(count){ const {error:e2}=await db.from('sets').delete().eq('exercise_id',exId).eq('performed_on',day); if(e2)throw e2; } }
    const {error}=await db.from('sets').insert(rows); if(error)throw error;
    picked=exId; $('log-dialog').close(); await load();
  }catch(err){ message('log-message',err.message||'Could not save.','error'); }
  finally{ busy=false; $('log-save').disabled=false; }
});
$('ex-form').addEventListener('submit',async e=>{
  e.preventDefault(); if(busy||!user)return; busy=true; $('ex-save').disabled=true;
  try{ const row={name:$('ex-name').value.trim(),muscle:$('ex-muscle').value,unit:$('ex-unit').value,target_sets:Number($('ex-sets').value),target_reps:Number($('ex-reps').value),increment:parseNum($('ex-inc').value,'number')}; if(!row.name)throw new Error('Give it a name.');
    const db=await connect(); const id=$('ex-id').value; const q=id?db.from('exercises').update(row).eq('id',id):db.from('exercises').insert(row).select('id').single(); const {data,error}=await q; if(error)throw error;
    if(!id&&data?.id) picked=data.id; $('ex-dialog').close(); await load(); }
  catch(err){ message('ex-message',err.message||'Could not save.','error'); }
  finally{ busy=false; $('ex-save').disabled=false; }
});
document.addEventListener('click',async e=>{
  const b=e.target.closest('button[data-log-edit],button[data-log-del],button[data-ex-edit],button[data-ex-del],button[data-ex-chart]'); if(!b||busy)return;
  if(b.dataset.logEdit) return openLog({edit:b.dataset.logEdit});
  if(b.dataset.exEdit) return openEx(exById(b.dataset.exEdit));
  if(b.dataset.exChart){ picked=b.dataset.exChart; render(); $('gym').scrollIntoView({behavior:'smooth'}); return; }
  busy=true;
  try{ const db=await connect();
    if(b.dataset.logDel){ const [exId,day]=b.dataset.logDel.split('|'); if(!confirm('Delete this exercise from the workout?')) return; const {error}=await db.from('sets').delete().eq('exercise_id',exId).eq('performed_on',day); if(error)throw error; }
    else { const ex=exById(b.dataset.exDel); const n=sessions(ex.id).length; if(!confirm(n?`Delete ${ex.name} and its ${n} logged session${n===1?'':'s'}?`:`Delete ${ex.name}?`)) return; const {error}=await db.from('exercises').delete().eq('id',ex.id); if(error)throw error; }
    await load();
  }catch(err){ message('history-message',err.message||'Could not delete.','error'); } finally{ busy=false; }
});
$('exercise-pick').onchange=()=>{ picked=$('exercise-pick').value; render(); };
document.querySelectorAll('[data-range]').forEach(b=>b.onclick=()=>{ range=b.dataset.range; document.querySelectorAll('[data-range]').forEach(x=>x.setAttribute('aria-pressed',String(x===b))); render(); });


// What the coach reads: every exercise with its target, the last sessions of each, and how often you trained.
function coachSummary(){
  const t=today(); const L=[];
  const days=[...new Set(sets.map(s=>s.performed_on))].sort();
  const weeks=[]; for(let i=7;i>=0;i--){ const e=addDays(t,-i*7), s=addDays(e,-6); weeks.push(`${s}: ${days.filter(d=>d>=s&&d<=e).length}`); }
  L.push(`Workouts logged: ${days.length} total, ${days.filter(d=>d>=addDays(t,-29)).length} in the last 30 days. Last workout: ${days.at(-1)||'none'}.`);
  L.push('Workouts per week, oldest first: '+weeks.join('; ')+'.');
  for(const ex of exercises.filter(x=>!x.archived)){
    const hist=sessions(ex.id); const s=suggest(ex); const best=hist.length?hist.reduce((a,h)=>h.e1rm>a.e1rm?h:a,hist[0]):null;
    L.push(`\nExercise: ${ex.name} (${ex.muscle}). Target ${ex.target_sets}×${ex.target_reps}, +${num(ex.increment)} ${ex.unit} when hit. ${hist.length} sessions.${best?` Best estimated 1RM ${best.e1rm.toFixed(0)} ${ex.unit} on ${best.day}.`:''} Next suggested: ${s.weight===null?'start':fmtW(s.weight,ex.unit)}.`);
    for(const h of hist.slice(-6)) L.push(`  ${h.day}: ${h.rows.map(r=>`${num(r.weight)}×${r.reps}`).join(' ')} (est 1RM ${h.e1rm.toFixed(0)}, volume ${num(h.volume)})${h.note?' note: '+h.note:''}`);
  }
  return L.join('\n');
}
window.coach={app:'gym',userId:async()=>user?.id||null,session:async()=>{ try{ const db=await connect(); const {data:{session}}=await db.auth.getSession(); return session?.access_token||null; }catch{ return null; } },summary:coachSummary};
// Reconnect a saved session, if any.
render();
connect().catch(()=>{});
})();
