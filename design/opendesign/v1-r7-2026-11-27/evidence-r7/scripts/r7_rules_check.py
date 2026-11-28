from pathlib import Path
import asyncio, json, subprocess, time, urllib.request, websockets
CHROME='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'; PORT=9775
HERE=Path(__file__).resolve().parents[2]
URL=(HERE/'dayspark-prototype.html').as_uri()
subprocess.run(['rm','-rf',f'/tmp/prof-{PORT}'])
p=subprocess.Popen([CHROME,'--headless=new','--disable-gpu',f'--remote-debugging-port={PORT}',f'--user-data-dir=/tmp/prof-{PORT}','--window-size=1440,1000',URL],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
u=None
for _ in range(120):
    try:
        d=json.load(urllib.request.urlopen(f'http://127.0.0.1:{PORT}/json')); pp=[t for t in d if t.get('type')=='page']
        if pp: u=pp[0]['webSocketDebuggerUrl']; break
    except Exception: pass
    time.sleep(.25)
async def main():
  async with websockets.connect(u, max_size=2**27) as ws:
    i=0; errs=[]
    async def call(m,params=None):
      nonlocal i; i+=1; mid=i
      await ws.send(json.dumps({'id':mid,'method':m,'params':params or {}}))
      while True:
        x=json.loads(await ws.recv())
        if x.get('method')=='Runtime.exceptionThrown': errs.append(((x['params']['exceptionDetails'].get('exception') or {}).get('description') or '')[:160])
        if x.get('id')==mid: return x
    async def ev(e):
      r=await call('Runtime.evaluate',{'expression':e,'returnByValue':True}); qq=r.get('result',{})
      if qq.get('exceptionDetails'): return 'ERR '+((qq['exceptionDetails'].get('exception') or {}).get('description') or '')[:160]
      return qq.get('result',{}).get('value')
    async def key(k,code,vk):
      await call('Input.dispatchKeyEvent',{'type':'keyDown','key':k,'code':code,'windowsVirtualKeyCode':vk,'nativeVirtualKeyCode':vk})
      await call('Input.dispatchKeyEvent',{'type':'keyUp','key':k,'code':code,'windowsVirtualKeyCode':vk,'nativeVirtualKeyCode':vk})
    await call('Runtime.enable'); await call('Page.enable'); await asyncio.sleep(1.8)
    checks=[]
    def rec(name, ok, detail=''): checks.append((name,bool(ok),detail)); print(('PASS ' if ok else 'FAIL ')+name+' => '+str(detail))

    # 1 create entry: one grammar on today / todo / calendar
    await ev("state.screen='today';state.variant='normal';render();Proto.enhance();'ok'"); await asyncio.sleep(.5)
    rec('today has exactly one 新建 entry', await ev("[...document.querySelectorAll('[data-proto-action=\"new-pick\"]')].filter(b=>b.offsetParent!==null).length")==1,
        await ev("[...document.querySelectorAll('[data-proto-action=\"new-pick\"]')].filter(b=>b.offsetParent!==null).map(b=>b.className)"))
    await ev("state.screen='cal-week';render();Proto.enhance();'ok'"); await asyncio.sleep(.5)
    rec('calendar has 新建日程 + 安排待办', await ev("!!document.querySelector('[data-proto-action=\"cal-new-proto\"]') && !!document.querySelector('[data-proto-action=\"cal-schedule-todo\"]')"))
    await ev("state.screen='todo-all';render();Proto.enhance();'ok'"); await asyncio.sleep(.5)
    rec('todo defaults to 全部 scope', await ev("state.screen==='todo-all' && document.querySelector('.mode-switch .is-on').textContent.trim()==='全部'"))

    # 2 date nav: step / today / arbitrary / focus preserved across view switch
    await ev("state.screen='todo-date';state.selectedDate='2026-11-20';render();Proto.enhance();'ok'"); await asyncio.sleep(.5)
    await ev("document.querySelector('.ds-step[data-step=\"1\"]').click();'ok'"); await asyncio.sleep(.4)
    rec('date next day', await ev("state.selectedDate")=='2026-11-21', await ev("state.selectedDate"))
    await ev("document.querySelector('.ds-month').click();'ok'"); await asyncio.sleep(.4)
    rec('date jump opens a picker', await ev("!!document.querySelector('.popover')"))
    await key('Escape','Escape',27); await asyncio.sleep(.4)
    await key('Escape','Escape',27); await asyncio.sleep(.4)
    await ev("state.screen='cal-day';state.variant='normal';state.selectedDate='2026-11-21';render();Proto.enhance();'ok'"); await asyncio.sleep(.5)
    rec('calendar keeps the same date focus', await ev("state.selectedDate")=='2026-11-21', await ev("state.selectedDate"))
    await ev("(function(){var b=[...document.querySelectorAll('.ph-right .tool')].find(x=>x.textContent.trim()==='今天');b.click();})()"); await asyncio.sleep(.4)
    rec('回到今天 resets the date', await ev("state.selectedDate")=='2026-11-20', await ev("state.selectedDate"))

    # 3 direct editing of frequent fields
    await ev("state.screen='todo-all';state.selectedDate='2026-11-20';state.variant='normal';state.drawer=null;state.drawerEdit=false;render();Proto.enhance();'ok'")
    await asyncio.sleep(.5)
    print('PRE', await ev("JSON.stringify({screen:state.screen,variant:state.variant,drawer:state.drawer,edit:state.drawerEdit,modals:document.querySelectorAll('.proto-modal-scrim').length,enh:(Proto.lastEnhancerError||'').slice(0,100)})"))
    await ev("document.querySelector('.product [data-action=open-todo]').click();'ok'")
    await asyncio.sleep(.8)
    print('POST', await ev("JSON.stringify({drawer:state.drawer&&state.drawer.id,edit:state.drawerEdit,acts:[...document.querySelectorAll('.drawer .field-row')].map(r=>r.dataset.protoAction),masked:getComputedStyle(document.querySelector('.drawer .field-row')).cursor,enh:(Proto.lastEnhancerError||'').slice(0,140)})"))
    await ev("Proto.enhance();'again'"); await asyncio.sleep(.4)
    print('REENHANCE', await ev("JSON.stringify({acts:[...document.querySelectorAll('.drawer .field-row')].map(r=>r.dataset.protoAction)})"))
    ident=await ev("state.drawer.id")
    rec('read-only detail has direct field rows', await ev("document.querySelectorAll('.drawer .field-row[data-proto-action]').length")>=5, await ev("[...document.querySelectorAll('.drawer .field-row')].map(r=>r.querySelector('.f-label').textContent+'|'+r.dataset.protoAction)"))
    b0=await ev("(todoById(state.drawer.id)||{}).priority")
    await ev("(function(){var r=[...document.querySelectorAll('.drawer .field-row')].find(x=>x.querySelector('.f-label').textContent==='优先级');r.click();})()"); await asyncio.sleep(.5)
    await ev("(function(){var b=[...document.querySelectorAll('[data-pri]')].find(x=>x.textContent.startsWith('低'));b.click();})()"); await asyncio.sleep(.5)
    rec('priority writes on the real row', await ev("(todoById(state.drawer.id)||{}).priority")==9, f"{b0}->"+str(await ev("(todoById(state.drawer.id)||{}).priority")))
    await ev("(function(){var r=[...document.querySelectorAll('.drawer .field-row')].find(x=>x.querySelector('.f-label').textContent==='日历');r.click();})()"); await asyncio.sleep(.5)
    rec('calendar picker opens', await ev("(document.querySelector('.proto-modal-head')||{}).textContent")=='日历')
    await ev("(function(){var b=[...document.querySelectorAll('.proto-modal-scrim [data-cal]')].find(x=>x.dataset.cal==='home');b.click();})()"); await asyncio.sleep(.5)
    rec('calendar writes', await ev("(todoById(state.drawer.id)||{}).cal")=='home', await ev("(todoById(state.drawer.id)||{}).cal"))
    await ev("(function(){var r=[...document.querySelectorAll('.drawer .field-row')].find(x=>x.querySelector('.f-label').textContent==='计划执行');r.click();})()"); await asyncio.sleep(.6)
    rec('plan row opens the one plan picker', await ev("state.screen")=='plan-picker', await ev("state.screen"))
    await key('Escape','Escape',27); await asyncio.sleep(.5)
    screen_now = await ev("state.screen"); drawer_now = await ev("state.drawer&&state.drawer.id")
    rec('plan exit returns to the drawer', screen_now=='todo-all' and drawer_now==ident, str(screen_now)+'/'+str(drawer_now))
    rec('no clickable-looking dead control in detail', await ev("[...document.querySelectorAll('.drawer button')].filter(b=>b.dataset.action==='noop'&&!b.dataset.protoAction).length")==0, await ev("[...document.querySelectorAll('.drawer button')].filter(b=>b.dataset.action==='noop'&&!b.dataset.protoAction).map(b=>b.textContent.trim())"))

    # 4 exit layering
    await key('Escape','Escape',27); await asyncio.sleep(.5)
    rec('Escape closes one layer (drawer)', await ev("state.drawer")==None, await ev("JSON.stringify({drawer:state.drawer,modal:!!document.querySelector('.proto-modal-scrim')})"))
    await ev("state.screen='todo-all';render();Proto.enhance();document.querySelector('.product [data-action=open-todo]').click();'ok'"); await asyncio.sleep(.6)
    await ev("(function(){var s=document.querySelector('.drawer .d-act.primary');s.click();})()"); await asyncio.sleep(.6)
    rec('edit mode opens the editor', await ev("state.drawerEdit")==True, await ev("state.drawerEdit"))

    # 5 saving semantics: simple field instant, complex confirmed by the editor save
    await ev("(function(){var r=[...document.querySelectorAll('.drawer .filter-chip-row .f-chip')].find(x=>x.textContent.trim()==='高');if(r)r.click();})()"); await asyncio.sleep(.5)
    rec('priority in editor stays a draft', await ev("!((todoById(state.drawer.id)||{}).priority===1)"), await ev("JSON.stringify({live:(todoById(state.drawer.id)||{}).priority,draft:state.draft&&state.draft.priority})"))

    # 6 hide completed is a real preference and survives reload
    await ev("Proto.save();'ok'"); await asyncio.sleep(.5)
    await ev("Proto.setHideCompleted(true);'ok'"); await asyncio.sleep(.4)
    await call('Page.navigate',{'url':URL}); await asyncio.sleep(1.8)
    rec('hide-completed persists after reload', await ev("Proto.data.prefs.hideCompleted")==True, await ev("JSON.stringify({pref:Proto.data.prefs.hideCompleted})"))
    await ev("state.screen='todo-all';render();Proto.enhance();'ok'"); await asyncio.sleep(.5)
    rec('completed section hidden', await ev("[...document.querySelectorAll('.completed-group')].filter(e=>e.style.display!=='none').length")==0)
    await ev("Proto.setHideCompleted(false);'ok'"); await asyncio.sleep(.3)

    # 7 calendar marks: term, holiday, makeup day
    await ev("state.screen='cal-month';state.selectedDate='2026-11-20';render();Proto.enhance();'ok'"); await asyncio.sleep(.6)
    rec('term marks on the month', await ev("document.querySelectorAll('.mcell .r7-term').length")>=2, await ev("[...document.querySelectorAll('.mcell .r7-term')].map(x=>x.textContent)"))
    await ev("state.screen='cal-month';state.selectedDate='2026-10-01';render();Proto.enhance();'ok'"); await asyncio.sleep(.6)
    rec('holiday 休 mark', await ev("document.querySelectorAll('.r7-hol.is-rest').length")>=1, await ev("[...document.querySelectorAll('.r7-hol')].map(x=>x.textContent)"))
    await ev("state.screen='cal-month';state.selectedDate='2026-09-20';render();Proto.enhance();'ok'"); await asyncio.sleep(.6)
    rec('makeup workday 班 mark', await ev("document.querySelectorAll('.r7-hol.is-work').length")>=1, await ev("[...document.querySelectorAll('.r7-hol')].map(x=>x.textContent)"))

    # 8 snooze writes the reminder, not the due
    await ev("state.screen='settings-notify';state.variant='normal';render();Proto.enhance();'ok'"); await asyncio.sleep(.5)
    await ev("(function(){document.querySelector('[data-proto-action=\"notify-demo-open\"]').click();})()"); await asyncio.sleep(.6)
    d0=await ev("JSON.stringify({remind:(todoById('report')||{}).remind,due:(todoById('report')||{}).due,dueTime:(todoById('report')||{}).dueTime})")
    await ev("document.querySelector('[data-proto-action=\"notify-snooze\"]').click();'ok'"); await asyncio.sleep(.6)
    d1=await ev("JSON.stringify({remind:(todoById('report')||{}).remind,due:(todoById('report')||{}).due,dueTime:(todoById('report')||{}).dueTime,snoozed:(todoById('report')||{}).snoozedRemind})")
    # Flutter snoozes from the clock (now + 1 hour), not from the due time, and
    # leaves the due date/time and the reminder label alone.
    rec('snooze re-arms from now + 1h and keeps the due', d0==d1.split(',"snoozed"')[0]+'}' and '"due":"2026-11-20"' in d1 and '"dueTime":"18:00"' in d1 and '16:00' in d1, d0+' -> '+d1)

    # 9 settings overview has no duplicate section links
    await ev("state.screen='settings-home';render();Proto.enhance();'ok'"); await asyncio.sleep(.6)
    rec('settings overview stats', await ev("document.querySelectorAll('.set-stat').length")==4)
    rec('settings overview has no duplicated nav links', await ev("[...document.querySelectorAll('.set-content .set-row')].filter(r=>['账号与同步','数据与备份','外观与日历'].includes(r.querySelector('.set-label').textContent.trim())).length")==0, await ev("[...document.querySelectorAll('.set-content .set-row .set-label')].map(x=>x.textContent.trim())"))

    # 10 recheck the R6 baselines that must not regress
    await ev("state.screen='todo-all';state.variant='normal';state.selectedDate='2026-11-20';state.drawer=null;render();Proto.enhance();'ok'"); await asyncio.sleep(.5)
    rec('todo list still renders groups', await ev("document.querySelectorAll('.todo-page .group-head').length")>=3)
    await ev("state.screen='cal-week';render();Proto.enhance();'ok'"); await asyncio.sleep(.5)
    rec('week still has 7 day columns', await ev("document.querySelectorAll('.day-col').length")==7)
    rec('sticky weekday header present', await ev("getComputedStyle(document.querySelector('.week-head')).position")=='sticky')
    print('TOTAL', sum(1 for _,ok,_ in checks if ok), '/', len(checks))
    print('ERRORS', errs[:3] if errs else 'none')
  p.terminate()
asyncio.run(main())
