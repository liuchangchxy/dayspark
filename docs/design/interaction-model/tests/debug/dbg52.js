const path=require('path');
const {chromium}=require('playwright-core');
const CHROME='/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL='file://'+path.resolve(__dirname,'..','..','index.html');
(async()=>{
 const b=await chromium.launch({executablePath:CHROME});
 const p=await b.newPage({viewport:{width:1440,height:900}});
 p.on('pageerror',e=>console.log('PAGEERROR',e.message));
 await p.goto(URL); await p.waitForFunction(()=>window.__READY__===true);
 await p.evaluate(()=>window.App.go('todos'));
 await p.waitForTimeout(300);
 // call UI.menu directly
 await p.evaluate(()=>{ const btn=document.querySelector('[data-testid="todos-filter"]'); window.UI.menu(btn, [{icon:'eye', text:'X', action:()=>{}}]); });
 await p.waitForTimeout(200);
 console.log('direct menu:', await p.evaluate(()=>!!document.querySelector('.menu')));
 await p.evaluate(()=>{ const m=document.querySelector('.menu'); if(m) m.remove(); });
 // now click
 await p.click('[data-testid="todos-filter"]');
 console.log('immediately after click:', await p.evaluate(()=>!!document.querySelector('.menu')));
 await p.waitForTimeout(100);
 console.log('after 100ms:', await p.evaluate(()=>!!document.querySelector('.menu')));
 await b.close();
})();
