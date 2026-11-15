const L=require('./r2-lib');
(async()=>{const b=await L.launch();const p=await L.newPage(b,L.DESKTOP);
await L.go(p,'todos'); await L.clickText(p,'.chip-btn','全部');
await p.locator('[data-testid="todo-tile"]',{hasText:'准备季度评审'}).first().click(); await L.settle(p,300);
const pid=(await L.state(p)).route.params.id;
const subs=await p.evaluate(id=>window.Store.subtasksOf(id).map(s=>({id:s.id,summary:s.summary,cal:s.calendarId})),pid);
console.log('pid',pid,'subs',subs);
await L.clickText(p,'.detail-actions button','移到回收站'); await L.settle(p,200);
await L.clickText(p,'.modal button','移到回收站'); await L.settle(p,400);
await L.go(p,'trash'); await L.settle(p,300);
// purge parent only
const row=p.locator('[data-testid="trash-row"]',{hasText:'准备季度评审'}).first();
console.log('trash rows',await p.locator('[data-testid="trash-row"]').count());
await row.locator('[data-testid="trash-purge"]').click(); await L.settle(p,250);
const modals=await L.texts(p,'.modal button'); console.log('purge modal buttons',modals);
await p.locator('.modal .btn.danger').click(); await L.settle(p,400);
let st=await L.state(p);
console.log('after parent purge subs:',st.todos.filter(t=>subs.some(s=>s.id===t.id)));
// restore a child
const child=p.locator('[data-testid="trash-row"]',{hasText:'收集各组数据'}).first();
console.log('child row exists',await child.count());
if(await child.count()){await child.locator('[data-testid="trash-restore"]').click(); await L.settle(p,400);}
st=await L.state(p);
const c=st.todos.find(t=>t.id===subs[0].id);
console.log('child after restore:',c);
// where does it appear?
await L.go(p,'todos'); await L.clickText(p,'.chip-btn','全部'); await L.settle(p,300);
console.log('all list has child?',/收集各组数据/.test(await L.text(p,'[data-testid="todo-list"]')));
await L.go(p,'search'); await p.fill('input','收集各组数据').catch(()=>{}); await L.settle(p,400);
console.log('search text',await L.text(p,'#view'));
await L.go(p,'detail',{type:'todo',id:subs[0].id}); await L.settle(p,350);
console.log('child detail text',(await L.text(p,'#view')).slice(0,220));
console.log('errors',p.__errors);
await L.shot(p,'X-orphan-subtask');
await b.close();})().catch(e=>{console.log('ERR',e.message);process.exit(1)});
