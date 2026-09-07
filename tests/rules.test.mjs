import test from 'node:test';
import assert from 'node:assert/strict';
import {initial,cells,step,finish,sanitize} from '../server/rules.mjs';
const wait={k:'wait'},attack=(d,c=0)=>({k:'attack',d,c});
test('charge shapes rotate in all four directions',()=>{
 for(const d of [[0,-1],[0,1],[1,0],[-1,0]]){
  assert.deepEqual([0,1,2,3].map(c=>cells([4,4],d,c).length),[1,2,3,4]);
  assert.equal(new Set(cells([4,4],d,3).map(String)).size,4);
 }
 assert.deepEqual(cells([2,2],[0,-1],2),[[2,1],[3,2],[1,2]]);
 assert.deepEqual(cells([2,2],[0,-1],3),[[2,1],[2,0],[3,1],[1,1]]);
});
test('simultaneous damage, guard, and move before attack',()=>{
 const s=initial(5);s.pos=[[1,1],[2,1]];
 assert.deepEqual(step(s,[attack([1,0]),attack([-1,0])]).state.hp,[2,2]);
 assert.deepEqual(step(s,[attack([1,0]),{k:'guard'}]).state.hp,[3,3]);
 assert.deepEqual(step(s,[attack([1,0]),{k:'move',d:[0,1]}]).state.hp,[3,3]);
 s.energy[0]=0;assert.deepEqual(step(s,[attack([1,0],1),wait]).state.hp,[3,3]);
});
test('blocked collision and swap; legal following movement',()=>{
 const s=initial(5);s.pos=[[1,1],[2,1]];
 assert.deepEqual(step(s,[{k:'move',d:[1,0]},wait]).state.pos,s.pos);
 assert.deepEqual(step(s,[{k:'move',d:[1,0]},{k:'move',d:[-1,0]}]).state.pos,s.pos);
 assert.deepEqual(step(s,[{k:'move',d:[1,0]},{k:'move',d:[1,0]}]).state.pos,[[2,1],[3,1]]);
});
test('charge validates time slots, meter length and energy budget',()=>{
 const c={k:'charge',d:[0,-1]};
 assert.equal(sanitize([c,c,c,attack([0,-1],3)],4,3,0).plan[3].c,3);
 assert.equal(sanitize([c,c,attack([0,-1],3)],3,3,0).plan[2].k,'wait');
 assert.equal(sanitize([attack([0,-1],3)],4,3,0).plan[0].k,'wait');
 assert.equal(sanitize([c,attack([0,-1],1),c,attack([0,-1],1)],4,1,0).plan[3].k,'wait');
 for(const n of [1,3,5,7,32])assert.equal(sanitize([],n,3,0).plan.length,n);
});
test('guard releases have exact cooldowns; unavailable guards cannot execute',()=>{
 assert.equal(sanitize([{k:'guard',release:3},wait],2,3,0).penalty,3);
 assert.equal(sanitize([{k:'guard'},wait],2,3,0).penalty,1);
 assert.equal(sanitize([{k:'guard'}],1,3,1).plan[0].k,'wait');
 let s=finish(initial(5),[3,1],()=>1);assert.deepEqual(s.cool,[3,1]);
 for(const expected of [[2,0],[1,0],[0,0]]){s=finish(s,[0,0],()=>1);assert.deepEqual(s.cool,expected);}
});
test('items appear only below 30%, as equidistant as possible, restore one',()=>{
 const s=initial(5);assert.equal(finish(s,[0,0],()=>.3).items.length,0);
 const f=finish(s,[0,0],()=>0);assert.equal(f.items.length,1);
 const p=f.items[0];const dist=q=>Math.abs(p[0]-q[0])+Math.abs(p[1]-q[1]);assert.equal(dist(s.pos[0]),dist(s.pos[1]));
 s.items=[[0,4]];s.energy[0]=1;assert.equal(step(s,[wait,wait]).state.energy[0],2);
});
test('new item replaces the existing item, failed spawn keeps it',()=>{
 let s=initial(5);s.items=[[2,2]];
 assert.deepEqual(finish(s,[0,0],()=>.5).items,[[2,2]]);
 for(let i=0;i<100;i++){
  const old=s.items[0];s=finish(s,[0,0],()=>0);
  assert.equal(s.items.length,1);assert.notDeepEqual(s.items[0],old);
 }
});
