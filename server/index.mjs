import http from 'node:http';
import {createReadStream, statSync} from 'node:fs';
import {resolve,extname,sep} from 'node:path';
import {fileURLToPath} from 'node:url';
import {WebSocketServer} from 'ws';
import {initial,sanitize,step,finish} from './rules.mjs';
const root=resolve(fileURLToPath(new URL('../build/web/',import.meta.url)));
const mime={'.html':'text/html','.js':'text/javascript','.wasm':'application/wasm','.pck':'application/octet-stream','.png':'image/png','.svg':'image/svg+xml'};
const server=http.createServer((req,res)=>{
 if(req.url==='/health'){res.writeHead(200);res.end('ok');return;}
 let path;try{path=resolve(root,'.'+decodeURIComponent(new URL(req.url,'http://localhost').pathname));}catch{res.writeHead(400);res.end();return;}
 if(path===root)path=resolve(root,'index.html');
 if(!path.startsWith(root+sep)){res.writeHead(403);res.end();return;}
 try{if(!statSync(path).isFile())throw Error();res.writeHead(200,{'Content-Type':mime[extname(path)]||'application/octet-stream','Cache-Control':'no-cache'});createReadStream(path).pipe(res);}catch{res.writeHead(404);res.end('Build the Godot Web export first.');}
});
const wss=new WebSocketServer({server,path:'/ws',maxPayload:16384});
const rooms=new Map();
const send=(ws,data)=>{if(ws.readyState===1)ws.send(JSON.stringify(data));};
function broadcast(r,data){r.peers.forEach(ws=>send(ws,data));}
function schedule(r){
 const dt=60000/r.bpm,beats=r.groups.reduce((a,b)=>a+b,0),end=r.start+beats*dt;
 r.timer=setTimeout(()=>{
  if(r.peers.length!==2)return;
  const ps=r.plans.map((p,i)=>sanitize(p,beats,r.state.energy[i],r.state.cool[i]));
  const frames=[];let s=r.state;
  for(let b=0;b<beats;b++){const frame=step(s,ps.map(p=>p.plan[b]));frames.push(frame);s=frame.state;if(s.hp.some(h=>h<=0))break;}
  const final=finish(s,ps.map(p=>p.penalty));
  const actionStart=end+dt;
  const next=actionStart+(beats+1)*dt;
  broadcast(r,{type:'action',round:r.state.round,start:actionStart,frames,final,next});
  r.state=final;r.plans=[null,null];r.start=next;
  if(s.hp.every(h=>h>0))schedule(r);
 },Math.max(0,end+dt*.4-Date.now()));
}
wss.on('connection',ws=>{
 ws.alive=true;ws.on('pong',()=>ws.alive=true);
 ws.on('message',raw=>{
  let m;try{m=JSON.parse(raw);}catch{return ws.close(1007);}
  if(m.type==='ping'){send(ws,{type:'pong',echo:m.time,time:Date.now()});return;}
  if(m.type==='join'&&!ws.room){
   const code=String(m.room||'').toUpperCase();
   if(!/^[A-Z0-9-]{3,24}$/.test(code)){send(ws,{type:'error',message:'Room: 3–24 letters / numbers'});return;}
   let r=rooms.get(code);
   if(!r){
    const groups=Array.isArray(m.groups)?m.groups:[];
    if(!groups.length||!groups.every(x=>Number.isInteger(x)&&x>=1&&x<=32)||groups.reduce((a,b)=>a+b,0)>32||!Number.isFinite(m.bpm)||m.bpm<20||m.bpm>400||!Number.isInteger(m.n)||m.n<3||m.n>10){send(ws,{type:'error',message:'Invalid settings'});return;}
    r={peers:[],state:initial(m.n),bpm:m.bpm,groups,plans:[null,null]};rooms.set(code,r);
   }
   if(r.peers.length>=2){send(ws,{type:'error',message:'Room is full'});return;}
   ws.room=code;ws.player=r.peers.length;r.peers.push(ws);
   send(ws,{type:'joined',player:ws.player,room:code});
   if(r.peers.length===2){const dt=60000/r.bpm;r.ready=Date.now()+800;r.start=r.ready+4*dt;broadcast(r,{type:'start',state:r.state,bpm:r.bpm,groups:r.groups,ready:r.ready,start:r.start});schedule(r);}
  }
  if(m.type==='plan'&&ws.room){const r=rooms.get(ws.room);if(r&&m.round===r.state.round&&Date.now()>=r.start-100&&r.plans[ws.player]===null&&Array.isArray(m.plan))r.plans[ws.player]=m.plan;}
 });
 ws.on('close',()=>{const r=rooms.get(ws.room);if(!r)return;clearTimeout(r.timer);rooms.delete(ws.room);for(const peer of r.peers){peer.room=null;if(peer!==ws){send(peer,{type:'left'});peer.close(1000);}}});
 ws.on('error',()=>{});
});
const heartbeat=setInterval(()=>{for(const ws of wss.clients){if(!ws.alive){ws.terminate();continue;}ws.alive=false;ws.ping();}},15000);
server.on('close',()=>clearInterval(heartbeat));
server.listen(Number(process.env.PORT||8080),()=>console.log('PULSE / SLASH http://localhost:'+(process.env.PORT||8080)));
