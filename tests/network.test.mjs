import test from 'node:test';
import assert from 'node:assert/strict';
import {WebSocket} from '../server/node_modules/ws/wrapper.mjs';
const connect=()=>new Promise((resolve,reject)=>{const ws=new WebSocket('ws://localhost:8080/ws');ws.messages=[];ws.on('message',d=>ws.messages.push(JSON.parse(d)));ws.on('open',()=>resolve(ws));ws.on('error',reject);});
const until=async(ws,type)=>{const end=Date.now()+8000;while(Date.now()<end){const m=ws.messages.find(m=>m.type===type);if(m)return m;await new Promise(r=>setTimeout(r,20));}throw Error('Timed out: '+type);};
test('two real sockets: shared clock, hidden plans, authoritative frames, variable meter, disconnect',async()=>{
 const a=await connect(),b=await connect(),c=await connect();
 try{
  const room='TEST-'+Date.now();const settings={type:'join',room,n:5,bpm:400,groups:[3,2]};
  a.send(JSON.stringify(settings));await until(a,'joined');b.send(JSON.stringify({...settings,groups:[4]}));
  const sa=await until(a,'start'),sb=await until(b,'start');assert.equal(sa.start,sb.start);assert.deepEqual(sb.groups,[3,2]);
  assert.equal(sa.ready,sb.ready);assert.equal(sa.start-sa.ready,600,'four synchronized Ready/Go beats');
  c.send(JSON.stringify(settings));assert.equal((await until(c,'error')).message,'Room is full');
  a.send(JSON.stringify({type:'ping',time:42}));assert.equal((await until(a,'pong')).echo,42);
  await new Promise(r=>setTimeout(r,Math.max(0,sa.start-Date.now()+10)));
  a.send(JSON.stringify({type:'plan',round:0,plan:[{k:'move',d:[1,0]}]}));
  await new Promise(r=>setTimeout(r,80));assert.equal(b.messages.filter(m=>m.type==='action').length,0);
  await new Promise(r=>setTimeout(r,Math.max(0,sa.start+760-Date.now())));
  b.send(JSON.stringify({type:'plan',round:0,plan:[{k:'move',d:[-1,0]}]}));
  const ra=await until(a,'action'),rb=await until(b,'action');assert.deepEqual(ra,rb);assert.equal(ra.frames.length,5);
  assert.deepEqual(ra.frames[0].state.pos,[[1,4],[3,0]]);assert.equal(ra.next-ra.start,900,'five action beats plus one return beat');
  assert.equal(ra.start-sa.start,900,'five planning beats plus one transition beat');
  a.close();await until(b,'left');
 }finally{a.close();b.close();c.close();}
});
