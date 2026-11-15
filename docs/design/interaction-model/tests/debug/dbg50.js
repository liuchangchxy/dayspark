const path=require('path');
const {chromium}=require('playwright-core');
const CHROME='/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL='file://'+path.resolve('/Users/chang/Desktop/Code/dayspark-g0/docs/design/interaction-model','index.html');
(async()=>{
 const b=await chromium.launch({executablePath:CHROME});
 const p=await b.newPage({viewport:{width:1440,height:900}});
 p.on('pageerror',e=>console.log('PAGEERROR',e.message));
 await p.goto(URL); await p.waitForFunction(()=>window.__READY__===true);
 console.log(await p.evaluate(()=>{
   const S=window.Store;
   const pending=S.pendingTodos();
   const planned=S.plannedTodoIds();
   return {
     pending: pending.length,
     planned: planned.size,
     unplanned: S.inboxTodos().length,
     noDue: pending.filter(t=>!t.dueDate).length,
     withAlloc: pending.filter(t=>S.allocationsForTodo(t.id).some(a=>S.isAllocationLive(a))).length,
     sample: pending.map(t=>({s:t.summary, due:!!t.dueDate, alloc:S.allocationsForTodo(t.id).some(a=>S.isAllocationLive(a))})),
   };
 }));
 await p.evaluate(()=>window.App.go('todos'));
 await p.waitForTimeout(300);
 console.log('dated', await p.evaluate(()=>window.Store.todosForDay(new Date()).dated.length),
   'overdue', await p.evaluate(()=>window.Store.todosForDay(new Date()).overdue.length),
   'tiles', await p.$$eval('.todo-list [data-testid="todo-tile"]', n=>n.length));
 await b.close();
})();
