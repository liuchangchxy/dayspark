import asyncio, json, subprocess, time, urllib.request, glob, os, sys
import websockets
CHROME='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'; PORT=9471; PROFILE='/tmp/ds-bkround'
URL=__import__('pathlib').Path(__file__).resolve().parents[2].as_uri() + '/dayspark-prototype.html'; DL='/tmp/r4-evidence/downloads'
subprocess.run(['rm','-rf',PROFILE]); subprocess.run(['rm','-rf',DL]); os.makedirs(DL,exist_ok=True)
p=subprocess.Popen([CHROME,'--headless=new','--disable-gpu',f'--remote-debugging-port={PORT}',f'--user-data-dir={PROFILE}','--window-size=1440,1000',URL],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
wsurl=None
for _ in range(80):
    try:
        d=json.load(urllib.request.urlopen(f'http://127.0.0.1:{PORT}/json')); pg=[t for t in d if t.get('type')=='page']
        if pg: wsurl=pg[0]['webSocketDebuggerUrl']; break
    except Exception: pass
    time.sleep(.25)
async def main():
  async with websockets.connect(wsurl,max_size=2**24) as ws:
    i=0; errs=[]
    async def send(m,**pa):
      nonlocal i; i+=1; mid=i
      await ws.send(json.dumps({'id':mid,'method':m,'params':pa}))
      while True:
        x=json.loads(await ws.recv())
        if x.get('id')==mid: return x
        if x.get('method') in ('Runtime.exceptionThrown','Log.entryAdded'): errs.append(x)
    async def ev(x):
      r=await send('Runtime.evaluate',expression=x,returnByValue=True); res=r.get('result',{})
      if 'exceptionDetails' in res: return {'ERR':res['exceptionDetails'].get('text'),'d':res.get('result',{}).get('description')}
      return res.get('result',{}).get('value')
    async def wait_ready():
      for _ in range(80):
        v=await ev("!!window.state && document.readyState==='complete'")
        if v is True: return True
        await asyncio.sleep(.1)
      return False
    await send('Runtime.enable'); await send('Log.enable'); await send('DOM.enable'); await send('Page.enable')
    await send('Browser.setDownloadBehavior',behavior='allow',downloadPath=DL,eventsEnabled=True)
    await wait_ready(); await asyncio.sleep(.5)
    # Seed the real app state through the same runtime objects the UI uses.
    seed=await ev("""(()=>{
      const r=todoById('report');
      DS3.addAllocation(r,{date:'2026-11-20',start:'09:00',end:'10:00'});
      r.reminders=['30 分钟前'];
      r.tags=['备份验证'];
      const rec=todoById('recurring');
      DS3.addAllocation(rec,{date:'2026-11-26',start:'09:00',end:'10:00',occurrenceDate:'2026-11-27'});
      state.doneInstances=['recurring@2026-11-06'];
      state.skipped=['weekly@2026-11-13'];
      state.deletedTodos=['gone'];
      addLocalTodo({title:'备份里的本地待办',cal:'personal',priority:0});
      if(!Proto.data.tags.some(t=>t.name==='备份验证')) Proto.data.tags.push({name:'备份验证',color:'#123456'});
      return JSON.stringify({plans:r.plans.length,local:state.localTodos.length,seq:state.planSeq});
    })()""")
    print('seed',seed)
    print('backup screen',await ev("Proto.goSection('backup'); 'ok'")); await asyncio.sleep(.5)
    print('click export',await ev("(()=>{const e=document.querySelector('[data-proto-action=backup-export],[data-action=backup-export]'); if(!e)return 'MISSING'; e.click(); return 'ok'})()"))
    path=None
    for _ in range(60):
      fs=glob.glob(DL+'/*')
      if fs: path=fs[0]; break
      await asyncio.sleep(.2)
    print('file',path)
    payload=json.load(open(path)) if path else {}
    print('backup keys',list(payload.keys()),'ai',payload.get('data',{}).get('ai'))
    print('backup state keys',list(payload.get('state',{}).keys()))
    # reset: clear site data and reload (same as a new install)
    print('reset',await ev("localStorage.clear(); 'ok'")); await send('Page.reload'); await asyncio.sleep(1.5); await wait_ready(); await asyncio.sleep(.5)
    print('reset screen',await ev("JSON.stringify({screen:state.screen,todos:TODOS.length,report:!!todoById('report'),local:state.localTodos.length})"))
    print('after reset',await ev("JSON.stringify({alloc:DS3.allocations(todoById('report')).length,local:state.localTodos.length,done:state.doneInstances||[]})"))
    # real import: click the file action, then give the hidden input the exported file
    print('merge screen',await ev("Proto.goSection('backup'); 'ok'")); await asyncio.sleep(.4)
    print('click merge',await ev("(()=>{const e=document.querySelector('[data-proto-action=backup-merge],[data-action=backup-merge]'); if(!e)return 'MISSING'; e.click(); return 'ok'})()")); await asyncio.sleep(.3)
    doc=await send('DOM.getDocument',depth=-1,pierce=True); root=doc['result']['root']['nodeId']
    q=await send('DOM.querySelector',nodeId=root,selector='#proto-backup-file')
    nid=q['result']['nodeId']; print('node',nid)
    if nid:
      r=await send('DOM.setFileInputFiles',files=[path],nodeId=nid)
      print('setFile',r.get('error') or 'ok')
    await asyncio.sleep(1.2)
    # R6 added a real impact preview before writing; the confirm is part of the
    # flow now, so a merge that never clicked it would prove nothing.
    print('merge confirm',await ev("(()=>{const s=[...document.querySelectorAll('.proto-modal-scrim')].pop(); if(!s)return 'no modal'; const b=[...s.querySelectorAll('.proto-modal-foot button')].find(x=>x.textContent.trim()==='合并'); if(!b)return 'no 合并'; b.click(); return 'ok'})()"))
    await asyncio.sleep(1.0)
    print('after merge screen',await ev("JSON.stringify({screen:state.screen,variant:state.variant})"))
    print('after merge report',await ev("JSON.stringify(todoById('report')?{alloc:DS3.allocations(todoById('report')).map(p=>[p.start,p.end]),rem:todoById('report').reminders,tags:todoById('report').tags}:null)"))
    print('after merge recurring',await ev("JSON.stringify(todoById('recurring')?DS3.allocations(todoById('recurring')).map(p=>[p.date,p.occurrenceDate]):null)"))
    print('after merge state',await ev("JSON.stringify({done:state.doneInstances,skip:state.skipped,del:state.deletedTodos,local:state.localTodos.map(t=>t.id),seq:state.planSeq,tag:Proto.data.tags.some(t=>t.name==='备份验证')})"))
    print('secret leaks',await ev("JSON.stringify({snap:JSON.stringify(Proto.snapshot()).includes('sk-leak'),local:(localStorage.getItem('dayspark.prototype.v1')||'').includes('sk-leak')})"))
    # persisted after refresh
    print('reload',await send('Page.reload') and 'ok'); await asyncio.sleep(1.5); await wait_ready(); await asyncio.sleep(.5)
    print('persisted',await ev("JSON.stringify({alloc:DS3.allocations(todoById('report')).length,rem:todoById('report').reminders,done:state.doneInstances,local:state.localTodos.length,seq:state.planSeq})"))
    print('errs', [e.get('method') for e in errs])
  p.terminate()
asyncio.run(main())
