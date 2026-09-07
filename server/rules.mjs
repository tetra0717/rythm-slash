export const initial = n => ({n,pos:[[0,n-1],[n-1,0]],hp:[3,3],energy:[3,3],cool:[0,0],items:[],round:0});
const eq=(a,b)=>a[0]===b[0]&&a[1]===b[1];
export const cells=(p,d,c)=>{
 const f=[p[0]+d[0],p[1]+d[1]], far=[p[0]+2*d[0],p[1]+2*d[1]], s=[-d[1],d[0]];
 if(c===0)return [f]; if(c===1)return [f,far];
 if(c===2)return [f,[p[0]+s[0],p[1]+s[1]],[p[0]-s[0],p[1]-s[1]]];
 return [f,far,[f[0]+s[0],f[1]+s[1]],[f[0]-s[0],f[1]-s[1]]];
};
export function sanitize(plan,beats,energy,cool){
 const out=Array.from({length:beats},()=>({k:'wait'})); let charge=0,guard=false,penalty=0;
 for(let b=0;b<beats;b++){
  const a=plan?.[b]; if(!a||typeof a!=='object'){charge=0;guard=false;continue;}
  const dir=Array.isArray(a.d)&&a.d.length===2&&a.d.every(Number.isInteger)&&Math.abs(a.d[0])+Math.abs(a.d[1])===1;
  if(a.k==='guard'&&cool===0&&!penalty){out[b]={k:'guard'};guard=true;charge=0;if(a.release===1||a.release===3){penalty=a.release;guard=false;}continue;}
  if(guard){penalty=a.bad?3:1;guard=false;}
  if(a.k==='charge'&&dir){out[b]={k:'charge',d:a.d};charge=Math.min(3,charge+1);continue;}
  if(a.k==='attack'&&dir){const c=Number.isInteger(a.c)?a.c:0;if(c>=0&&c<=3&&c<=charge&&c<=energy){out[b]={k:'attack',d:a.d,c};energy-=c;}}
  if(a.k==='move'&&dir)out[b]={k:'move',d:a.d};
  charge=0;
 }
 if(guard)penalty=1;
 return {plan:out,penalty};
}
export function step(state,actions){
 const s=structuredClone(state), targets=structuredClone(s.pos), hits=[false,false],zones=[[],[]];
 actions.forEach((a,i)=>{if(a.k==='move'){const p=[s.pos[i][0]+a.d[0],s.pos[i][1]+a.d[1]];if(p.every(v=>v>=0&&v<s.n))targets[i]=p;}});
 if(eq(targets[0],targets[1])||(eq(targets[0],s.pos[1])&&eq(targets[1],s.pos[0]))){}else s.pos=targets;
 actions.forEach((a,i)=>{if(a.k==='attack'&&a.c<=s.energy[i]){s.energy[i]-=a.c;zones[i]=cells(s.pos[i],a.d,a.c);hits[1-i]=zones[i].some(p=>eq(p,s.pos[1-i]))&&actions[1-i].k!=='guard';}});
 for(let i=0;i<2;i++){if(hits[i])s.hp[i]--;const at=s.items.findIndex(p=>eq(p,s.pos[i]));if(at>=0){s.items.splice(at,1);s.energy[i]=Math.min(3,s.energy[i]+1);}}
 return {state:s,hits,zones,actions};
}
export function finish(state,penalties,random=Math.random){
 const s=structuredClone(state);s.cool=s.cool.map((c,i)=>Math.max(c-1,penalties[i]));s.round++;
 if(random()<.3){let best=Infinity,candidates=[];for(let x=0;x<s.n;x++)for(let y=0;y<s.n;y++){
 const p=[x,y];if([...s.pos,...s.items].some(q=>eq(p,q)))continue;
 const delta=Math.abs(Math.abs(x-s.pos[0][0])+Math.abs(y-s.pos[0][1])-Math.abs(x-s.pos[1][0])-Math.abs(y-s.pos[1][1]));
 if(delta<best){best=delta;candidates=[];}if(delta===best)candidates.push(p);
 }if(candidates.length)s.items=[candidates[Math.floor(random()*candidates.length)]];}
 return s;
}
