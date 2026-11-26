import asyncio, json, subprocess, time, urllib.request
import websockets
CHROME='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'; PORT=9409; PROFILE='/tmp/ds-mergeprobe'
URL='file:///tmp/r4-final/dayspark-prototype.html'
subprocess.run(['rm','-rf',PROFILE])
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
    i=0; evs=[]
    async def send(m,**pa):
      nonlocal i; i+=1; mid=i
      await ws.send(json.dumps({'id':mid,'method':m,'params':pa}))
      while True:
        x=json.loads(await ws.recv())
        if x.get('id')==mid: return x
        evs.append(x)
    async def ev(x):
      r=await send('Runtime.evaluate',expression=x,returnByValue=True); res=r.get('result',{})
      if 'exceptionDetails' in res: return {'ERR':res['exceptionDetails'].get('text'),'d':res.get('result',{}).get('description')}
      return res.get('result',{}).get('value')
    await send('Runtime.enable'); await asyncio.sleep(1)
    payload={
      'v':1,'todos':[{'id':'backup-t','title':'备份待办','cal':'work','plans':[{'id':'alloc-7','date':'2026-11-20','start':'10:00','end':'11:00','state':'active','occurrenceDate':None}]}],
      'events':[{'id':'backup-e','title':'备份日程','cal':'work','date':'2026-11-20','start':'12:00','end':'13:00'}],
      'cal':{},'data':{'tags':[{'name':'备份标签','color':'#123456'}],'ai':{'base':'https://x','model':'m','key':'sk-leak','secret':'sk-leak'}},
      'state':{'doneInstances':['recurring@2026-11-06'],'skipped':['weekly@2026-11-13'],'localTodos':[{'id':'local-9','title':'本地备份','cal':'personal','priority':0,'status':'open'}],'planSeq':7,'done':['plant'],'deletedTodos':['gone'],'hiddenCals':['life']}
    }
    js=json.dumps(payload,ensure_ascii=False)
    print('apply',await ev(f"JSON.stringify(Proto.applyBackupMerge({js}))"))
    print('data',await ev("JSON.stringify({doneInstances:state.doneInstances,skipped:state.skipped,local:state.localTodos.map(t=>t.id),seq:state.planSeq,done:state.done?Array.from(state.done):[],del:state.deletedTodos,hid:state.hiddenCals,todo:todoById('backup-t')&&todoById('backup-t').plans,ev:!!EVENTS.find(e=>e.id==='backup-e'),tag:Proto.data.tags.some(t=>t.name==='备份标签'),ai:Proto.data.ai})"))
    print('snapstr',await ev("JSON.stringify(Proto.snapshot()).includes('sk-leak')"))
    print('persist',await ev("Proto.persistNow()"), 'local',await ev("localStorage.getItem('dayspark.prototype.v1').includes('sk-leak')"))
    print('errs',json.dumps([e.get('method') for e in evs if e.get('method') in ('Runtime.exceptionThrown','Log.entryAdded')]))
  p.terminate()
asyncio.run(main())
