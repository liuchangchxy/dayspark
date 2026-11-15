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
 console.log('has filter btn', await p.evaluate(()=>!!document.querySelector('[data-testid="todos-filter"]')));
 await p.click('[data-testid="todos-filter"]');
 await p.waitForTimeout(250);
 console.log('menu', await p.evaluate(()=>{const m=document.querySelector('.menu');return m?m.outerHTML.slice(0,400):null;}));
 await b.close();
})();
