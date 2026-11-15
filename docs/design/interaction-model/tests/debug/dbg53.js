const path=require('path');
const {chromium}=require('playwright-core');
const CHROME='/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL='file://'+path.resolve(__dirname,'..','..','index.html');
(async()=>{
 const b=await chromium.launch({executablePath:CHROME});
 const p=await b.newPage({viewport:{width:1440,height:900}});
 p.on('pageerror',e=>console.log('PAGEERROR',e.message));
 p.on('console',m=>console.log('CONSOLE',m.text()));
 await p.goto(URL); await p.waitForFunction(()=>window.__READY__===true);
 await p.evaluate(()=>window.App.go('todos'));
 await p.waitForTimeout(300);
 console.log('count', await p.evaluate(()=>document.querySelectorAll('[data-testid="todos-filter"]').length));
 await p.evaluate(()=>{
   const btns=[...document.querySelectorAll('[data-testid="todos-filter"]')];
   btns.forEach((b,i)=>console.log('btn',i,'visible',!!b.offsetParent,'rect',JSON.stringify(b.getBoundingClientRect())));
   const orig=window.UI.menu;
   window.UI.menu=function(...a){ console.log('UI.menu called'); const r=orig.apply(this,a); console.log('menu node?', !!document.querySelector('.menu')); return r; };
   const oc=window.UI.closeMenu;
   window.UI.closeMenu=function(...a){ console.log('UI.closeMenu called', new Error().stack.split('\n')[2]); return oc.apply(this,a); };
 });
 await p.click('[data-testid="todos-filter"]');
 await p.waitForTimeout(200);
 await b.close();
})();
