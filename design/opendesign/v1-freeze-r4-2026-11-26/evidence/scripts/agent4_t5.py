import sys, json, time
sys.path.insert(0, '/tmp')
from agent4_cdp import *
p = new_page('http://127.0.0.1:8765/index.html')
c = CDP(p['webSocketDebuggerUrl']); open_app(c)
c.ev("localStorage.clear()"); reload(c); time.sleep(0.5)

def go_ai():
    c.ev("location.hash='#/ai'")
    c.wait("state.screen==='ai-chat'",5); time.sleep(0.5)

def send(text):
    c.ev("document.querySelector('#ai-input').value=%s" % json.dumps(text))
    c.ev("document.querySelector('#ai-input').dispatchEvent(new Event('input',{bubbles:true}))")
    c.wait("!!document.querySelector('.ai-send, .cap-send')",5)
    c.ev("(document.querySelector('[data-proto-action=\"ai-send-proto\"]')||document.querySelector('.ai-send')).click()")
    time.sleep(1.1)

def click_last_plan_chip():
    return c.ev("""(function(){
      const bubbles=[...document.querySelectorAll('.ai-msg')].filter(b=>/AI 助手/.test((b.querySelector('.ai-msg-head')||{}).textContent||''));
      const b=bubbles[bubbles.length-1]; if(!b) return 'no bubble';
      const chip=[...b.querySelectorAll('.ai-chip')].find(c=>/安排时间/.test(c.textContent));
      if(!chip) return 'no chip: '+b.textContent;
      chip.click(); return 'clicked';
    })()""")

go_ai()
send('安排一下整理周会纪要并群发')
print('chip', click_last_plan_chip())
c.wait("!!document.querySelector('.proto-modal-scrim')",5)
time.sleep(0.3)
# A repeating target must surface the occurrence picker, not inherit a date.
occ_modal = c.ev("""(function(){
  const s=[...document.querySelectorAll('.proto-modal-scrim')].find(x=>x.querySelector('[data-occ]'));
  if(!s) return {found:false, modals:[...document.querySelectorAll('.proto-modal-scrim')].map(x=>x.textContent.slice(0,60))};
  return {found:true, title:(s.querySelector('.proto-modal-head')||{}).textContent||'', days:[...s.querySelectorAll('[data-occ]')].map(b=>b.dataset.occ), note:s.textContent};
})()""")
print('occ modal', json.dumps(occ_modal, ensure_ascii=False)[:600])
assert occ_modal['found'] is True
assert '2026-11-27' in occ_modal['days']
assert '不会默认' in occ_modal['note']
c.ev("document.querySelector('[data-occ=\"2026-11-27\"]').click()")
time.sleep(0.4)
state = c.ev("""(function(){
  const planScrim=[...document.querySelectorAll('.proto-modal-scrim')].find(x=>/写入计划/.test(x.textContent));
  return {planOpen:!!planScrim, text:planScrim?planScrim.textContent.slice(0,300):''};
})()""")
print('after pick', json.dumps(state, ensure_ascii=False))
assert state['planOpen'] is True and '2026-11-27' in state['text']
c.ev("""(function(){
  const s=[...document.querySelectorAll('.proto-modal-scrim')].find(x=>/写入计划/.test(x.textContent));
  s.querySelector('.proto-btn.primary').click();
})()""")
time.sleep(0.8)
res = c.ev("""(function(){
  const t=todoById('recurring');
  const allocs=(t.plans||[]).filter(p=>p&&p.state==='active');
  const nov27=plansOn('2026-11-27').filter(x=>x.todo.id==='recurring');
  const nov20=plansOn('2026-11-20').filter(x=>x.todo.id==='recurring');
  const nov06=plansOn('2026-11-06').filter(x=>x.todo.id==='recurring');
  return {
    allocs:allocs.map(p=>({date:p.date,start:p.start,end:p.end,occ:p.occurrenceDate,state:p.state})),
    nov27:nov27.map(x=>({allocId:x.allocId,start:x.start,end:x.end})),
    nov20Count:nov20.length, nov06Count:nov06.length,
    directPlanDate:t.plan&&t.plan.date, toast:(document.querySelector('.toast')||{}).textContent||''
  };
})()""")
print('repeat result', json.dumps(res, ensure_ascii=False, indent=2))
assert len(res['allocs'])==1, res['allocs']
a=res['allocs'][0]
assert a['occ']=='2026-11-27' and a['date']=='2026-11-27', a
assert len(res['nov27'])==1
assert res['nov20Count']==0 and res['nov06Count']==0
assert '2026-11-27' in res['toast']
# ---- normal todo: second segment must not overwrite the first ----
reload(c); time.sleep(0.5)
go_ai()
send('安排一下提交周报给林总')
print('chip2', click_last_plan_chip())
c.wait("!!document.querySelector('.proto-modal-scrim')",5); time.sleep(0.4)
no_occ = c.ev("!!document.querySelector('[data-occ]')")
print('instance picker for normal todo?', no_occ)
assert no_occ is False
c.ev("""(function(){
  const s=[...document.querySelectorAll('.proto-modal-scrim')].find(x=>/写入计划/.test(x.textContent));
  s.querySelector('.proto-btn.primary').click();
})()""")
time.sleep(0.8)
res2 = c.ev("""(function(){
  const t=todoById('report');
  const allocs=(t.plans||[]).filter(p=>p&&p.state==='active');
  const day=plansOn('2026-11-20').filter(x=>x.todo.id==='report');
  return {allocs:allocs.map(p=>({id:p.id,date:p.date,start:p.start,end:p.end,occ:p.occurrenceDate,legacy:!!p.legacy})),
    day:day.map(x=>({allocId:x.allocId,start:x.start,end:x.end})),
    toast:(document.querySelector('.toast')||{}).textContent||''};
})()""")
print('normal result', json.dumps(res2, ensure_ascii=False, indent=2))
assert len(res2['allocs'])==2, res2['allocs']
first=res2['allocs'][0]
assert first['date']=='2026-11-20' and first['start']=='15:15' and first['end']=='16:00', first
assert len(res2['day'])==2
errs=[e for e in c.errors() if 'favicon' not in e and '404' not in e and 'File not found' not in e]
print('errors', errs); assert not errs, errs
assert c.ev('Proto.lastEnhancerError') is None
print('TEST5 PASS')
