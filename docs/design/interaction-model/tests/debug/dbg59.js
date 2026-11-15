const path=require('path');
const {chromium}=require('playwright-core');
const CHROME='/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL='file://'+path.resolve(__dirname,'..','..','index.html');
(async()=>{
 const b=await chromium.launch({executablePath:CHROME});
 const p=await b.newPage({viewport:{width:1440,height:900}});
 await p.goto(URL); await p.waitForFunction(()=>window.__READY__===true);
 await p.evaluate(()=>window.App.go('todos'));
 await p.waitForTimeout(200);
 for (const off of [-400, -60, 40, 400]) {
   await p.evaluate((o)=>window.__todoHelpers.setView({kind:'day', day: window.U.addDays(window.U.startOfDay(window.U.now()), o)}), off);
   await p.waitForTimeout(180);
   console.log(off, await p.evaluate(()=>({empty:document.querySelectorAll('.empty').length, rows:document.querySelectorAll('[data-testid="todo-tile"]').length})));
 }
 await b.close();
})();
