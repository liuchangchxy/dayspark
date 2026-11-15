const path=require('path');
const {chromium}=require('playwright-core');
const CHROME='/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL='file://'+path.resolve(__dirname,'..','..','index.html');
(async()=>{
 const b=await chromium.launch({executablePath:CHROME});
 const p=await b.newPage({viewport:{width:1440,height:900}});
 p.on('pageerror',e=>console.log('PAGEERROR',e.message));
 await p.goto(URL); await p.waitForFunction(()=>window.__READY__===true);
 await p.evaluate(()=>window.App.go('action'));
 await p.waitForTimeout(250);
 await p.evaluate(()=>document.querySelector('[data-testid="action-create"]').click());
 await p.waitForTimeout(250);
 await p.evaluate(()=>document.querySelector('[data-testid="create-todo"]').click());
 await p.waitForTimeout(350);
 await p.fill('[data-testid="composer-title"]','今天页高亮');
 await p.evaluate(()=>document.querySelector('[data-testid="composer-save"]').click());
 await p.waitForTimeout(400);
 console.log(await p.evaluate(()=>({
   route: window.Store.state.route.name,
   hl: window.Store.state.highlight,
   hlNodes: Array.from(document.querySelectorAll('.hl')).map(n=>n.dataset.testid+':'+n.dataset.id),
   actionTodos: Array.from(document.querySelectorAll('[data-testid="action-todo"]')).map(n=>n.dataset.id+':'+n.textContent.slice(0,20)),
   titles: Array.from(document.querySelectorAll('.row-title')).map(n=>n.textContent.slice(0,20)),
 })));
 await b.close();
})();
