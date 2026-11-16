const path=require('path');const {chromium}=require('playwright-core');
const CHROME='/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
(async()=>{
 const b=await chromium.launch({executablePath:CHROME});
 const p=await b.newPage({viewport:{width:1440,height:900}});
 p.on('pageerror',e=>console.log('PAGEERROR',e.message));
 p.on('console',m=>{if(m.type()==='error')console.log('CONSOLE',m.text());});
 await p.goto('file://'+path.resolve(__dirname,'..','..','index.html'));
 await p.waitForFunction(()=>window.__READY__===true);
 await p.evaluate(()=>window.App.go('todos'));
 await p.waitForTimeout(300);
 console.log('split?',await p.evaluate(()=>({
   md: !!document.querySelector('[data-testid="todos-masterdetail"]'),
   pane: !!document.querySelector('[data-testid="detail-pane"]'),
   rows: document.querySelectorAll('[data-testid="todo-tile"]').length,
 })));
 // click first row
 await p.evaluate(()=>{const r=document.querySelector('[data-testid="todo-tile"] .todo-row'); if(r) r.click();});
 await p.waitForTimeout(300);
 console.log('after click',await p.evaluate(()=>({
   md: !!document.querySelector('[data-testid="todos-masterdetail"]'),
   paneBody: !!document.querySelector('[data-testid="detail-pane-body"]'),
   rows: document.querySelectorAll('[data-testid="todo-tile"]').length,
   selected: document.querySelectorAll('.md-selected').length,
   route: window.Store.state.route.name,
 })));
 await b.close();
})();
