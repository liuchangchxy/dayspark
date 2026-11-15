const {chromium}=require('playwright-core');
const path=require('path');
const CHROME='/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL='file:///Users/chang/Desktop/Code/dayspark-g0/docs/design/interaction-model/index.html';
(async()=>{
 const b=await chromium.launch({executablePath:CHROME,headless:true});
 const ctx=await b.newContext({viewport:{width:390,height:844},hasTouch:true,isMobile:true});
 const p=await ctx.newPage();
 p.on('pageerror',e=>console.log('PAGEERR',e.message));
 await p.goto(URL); await p.waitForFunction(()=>window.__READY__);
 await p.evaluate(()=>window.App.go('todos')); await p.waitForTimeout(400);
 const tile=p.locator('[data-testid="todo-tile"]',{hasText:'买牛奶和咖啡豆'}).first();
 const bb=await tile.boundingBox(); console.log('bb',bb);
 await p.evaluate(()=>{
   window.__ev=[];
   const r=document.querySelector('[data-testid="todo-list"]');
   ['pointerdown','pointermove','pointerup','pointercancel','touchstart','touchmove','touchend'].forEach(n=>
     r.addEventListener(n,(e)=>{window.__ev.push(n+' x='+Math.round(e.clientX||0)+' pt='+(e.pointerType||''))},{capture:true}));
 });
 const cdp=await ctx.newCDPSession(p); const cx=bb.x+bb.width/2, cy=bb.y+bb.height/2;
 await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x:cx,y:cy,id:1}]});
 for(let i=1;i<=10;i++){await cdp.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{x:cx-i*12,y:cy,id:1}]});}
 await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
 await p.waitForTimeout(700);
 console.log('events',await p.evaluate(()=>window.__ev.slice(0,30)));
 console.log('state',await p.evaluate(()=>({route:window.Store.state.route,toast:document.querySelector('.toast')&&document.querySelector('.toast').textContent,deleted:window.Store.state.todos.find(t=>t.summary==='买牛奶和咖啡豆').deletedAt})));
 await p.screenshot({path:'/tmp/review2-g0/X-swipe-debug.png'});
 await b.close();
})().catch(e=>{console.log('ERR',e.message);process.exit(1)});
