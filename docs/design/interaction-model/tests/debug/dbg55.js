const path=require('path');
const {chromium}=require('playwright-core');
const CHROME='/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL='file://'+path.resolve(__dirname,'..','..','index.html');
(async()=>{
 const b=await chromium.launch({executablePath:CHROME});
 const p=await b.newPage({viewport:{width:1440,height:900}});
 p.on('pageerror',e=>console.log('PAGEERROR',e.message));
 await p.addInitScript(()=>{
   const orig = Date.prototype.getTime;
 });
 await p.goto(URL);
 await p.waitForFunction(()=>window.__READY__===true);
 console.log(await p.evaluate(()=>{
   const e=window.Store.state.events.find(x=>x.summary==='国庆假期');
   const d=e.startDt;
   return { ctor:d.constructor.name, keys:Object.keys(d), str:String(d), isDate: d instanceof Date,
     getTime: typeof d.getTime };
 }));
 await b.close();
})();
