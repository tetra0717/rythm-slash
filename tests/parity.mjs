// Generate deterministic fixtures shared with the GDScript rules test.
import {writeFileSync} from 'node:fs';
import {initial,step,cells} from '../server/rules.mjs';
let seed=12345;const random=()=>((seed=(Math.imul(seed,1664525)+1013904223)>>>0)/4294967296);
const cases=[];
for(let n=3;n<=10;n++)for(let j=0;j<40;j++){
 const s=initial(n);s.pos=[[Math.floor(random()*n),Math.floor(random()*n)],[Math.floor(random()*n),Math.floor(random()*n)]];
 if(String(s.pos[0])===String(s.pos[1]))continue;
 s.energy=[Math.floor(random()*4),Math.floor(random()*4)];
 const actions=[0,1].map(()=>{const k=['wait','move','attack','guard'][Math.floor(random()*4)];const d=[[1,0],[-1,0],[0,1],[0,-1]][Math.floor(random()*4)];return {k,d,c:Math.floor(random()*4)};});
 cases.push({s,actions,expected:step(s,actions)});
}
writeFileSync(new URL('./parity.json',import.meta.url),JSON.stringify(cases));
console.log('Generated '+cases.length+' rule parity fixtures.');
