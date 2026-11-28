import asyncio, json, subprocess, time, urllib.request
import websockets
CHROME='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'; PORT=9487; PROFILE='/tmp/ds-bksingle'
URL='file:///tmp/r4-final/dayspark-prototype.html'
subprocess.run(['rm','-rf',PROFILE])
p=subprocess.Popen([CHROME,'--headless=new','--disable-gpu',f'--remote-debugging-port={PORT}',f'--user-data-dir={PROFILE}','--window-size=1440,1000',URL],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
u=None
for _ in range(80):
  try:
    d=json.load(urllib.request.urlopen(f'http://127.0.0.1:{PORT}/json')); pp=[t for t in d if t.get('type')=='page']
    if pp: u=pp[0]['webSocketDebuggerUrl']; break
  except: pass
  time.sleep(.25)
async def m():
  async with websockets.connect(u,max_size=2**24) as ws:
    i=0; errs=[]
    async def s(mm,**pa):
      nonlocal i;i+=1;mi=i;await ws.send(json.dumps({'id':mi,'method':mm,'params':pa}))
      while True:
        x=json.loads(await ws.recv())
        if x.get('id')==mi:return x
        if x.get('method') in ('Runtime.exceptionThrown','Log.entryAdded'): errs.append(x)
    async def e(x):
      r=await s('Runtime.evaluate',expression=x,returnByValue=True);q=r.get('result',{})
      if 'exceptionDetails' in q: return {'ERR':q['exceptionDetails'].get('text')}
      return q.get('result',{}).get('value')
    await s('Runtime.enable'); await s('Log.enable'); await asyncio.sleep(1)
    print('seed raw',await e("JSON.stringify({hasPlans:Array.isArray(todoById('report').plans),raw:todoById('report').plan&&[todoById('report').plan.start,todoById('report').plan.end]})"))
    payload={'v':1,'todos':[{'id':'report','title':'提交周报给林总','cal':'work','due':'2026-11-20','dueTime':'18:00','plans':[{'id':'alloc-1','date':'2026-11-20','start':'09:00','end':'10:00','state':'active','occurrenceDate':None}]}],'events':[],'cal':{},'data':{},'state':{}}
    print('apply',await e(f"JSON.stringify(Proto.applyBackupMerge({json.dumps(payload,ensure_ascii=False)}))")); await asyncio.sleep(.3)
    print('after',await e("JSON.stringify({plans:DS3.allocations(todoById('report')).map(p=>[p.id,p.start,p.end,p.state]),plan:todoById('report').plan&&[todoById('report').plan.id,todoById('report').plan.start]})"))
    print('errs',[x.get('method') for x in errs])
  p.terminate()
asyncio.run(m())
