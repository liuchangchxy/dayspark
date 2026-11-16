const path=require('path');const {chromium}=require('playwright-core');
const CHROME='/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
(async()=>{
 const b=await chromium.launch({executablePath:CHROME});
 const p=await b.newPage({viewport:{width:1440,height:900}});
 p.on('pageerror',e=>console.log('PAGEERROR',e.message));
 await p.goto('file://'+path.resolve(__dirname,'..','..','index.html'));
 await p.waitForFunction(()=>window.__READY__===true);
 await p.evaluate(()=>window.App.go('todos'));
 await p.waitForTimeout(250);
 await p.evaluate(()=>document.querySelector('[data-testid="todo-tile"] .todo-row').click());
 await p.waitForTimeout(250);
 console.log('pane open:', await p.evaluate(()=>!!document.querySelector('[data-testid="detail-pane-body"]')));
 await p.evaluate(()=>document.querySelector('[data-testid="pane-close"]').click());
 await p.waitForTimeout(250);
 console.log('after close btn:', await p.evaluate(()=>({pane:!!document.querySelector('[data-testid="detail-pane-body"]'), rows:document.querySelectorAll('[data-testid="todo-tile"]').length})));
 await p.evaluate(()=>document.querySelector('[data-testid="todo-tile"] .todo-row').click());
 await p.waitForTimeout(200);
 await p.keyboard.press('Escape');
 await p.waitForTimeout(250);
 console.log('after Esc:', await p.evaluate(()=>({pane:!!document.querySelector('[data-testid="detail-pane-body"]'), route:window.Store.state.route.name, tab:window.Store.state.tab})));
 // mobile check
 await p.setViewportSize({width:390,height:844});
 await p.waitForTimeout(300);
 console.log('mobile bash:', await p.evaluate(()=>({
   bottomBtns: Array.from(document.querySelectorAll('#bottomnav button')).map(b=>b.dataset.testid),
 })));
 await b.close();
})();
