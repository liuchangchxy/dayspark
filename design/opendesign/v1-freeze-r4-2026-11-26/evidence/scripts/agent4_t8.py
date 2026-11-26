import sys,json,time,re
sys.path.insert(0,'/tmp')
from agent4_cdp import *
p=new_page('http://127.0.0.1:8765/index.html'); c=CDP(p['webSocketDebuggerUrl']); open_app(c)
c.ev("localStorage.clear()"); reload(c); time.sleep(0.5)
c.ev("location.hash='#/ai'"); c.wait("state.screen==='ai-chat'",5); time.sleep(0.5)
# Default AI message chip -> plan modal with no target.
c.ev("""(function(){const b=[...document.querySelectorAll('.ai-msg')].find(x=>/AI 助手/.test((x.querySelector('.ai-msg-head')||{}).textContent||'')); const chip=[...b.querySelectorAll('.ai-chip')].find(c=>/安排时间/.test(c.textContent)); chip.click();})()""")
c.wait("!!document.querySelector('[data-proto-action=\"ai-plan-target\"]')",5); time.sleep(0.3)
assert c.ev("!!document.querySelector('[data-occ]')") is False, 'no target -> no instance picker yet'
c.ev("document.querySelector('[data-proto-action=\"ai-plan-target\"]').click()")
c.wait("!!document.querySelector('[data-todo]')",5); time.sleep(0.2)
c.ev("document.querySelector('[data-todo=\"recurring\"]').click()")
time.sleep(0.5)
occ = c.ev("""(function(){const s=[...document.querySelectorAll('.proto-modal-scrim')].find(x=>x.querySelector('[data-occ]')); return !!s;})()""")
print('picker after choosing repeat target:', occ)
assert occ is True
# cancel the picker, then try to write without selecting -> blocked
c.ev("""(function(){const s=[...document.querySelectorAll('.proto-modal-scrim')].find(x=>x.querySelector('[data-occ]')); s.querySelector('.proto-btn').click();})()""")
time.sleep(0.3)
txt=c.ev("(document.querySelector('.proto-modal')||{}).textContent||''")
print('plan modal after cancel:', re.sub(r'\s+',' ',txt)[:160])
assert '选择这一次实例' in txt
before=c.ev("Object.keys((todoById('recurring').plans||[])).length")
c.ev("""(function(){const s=[...document.querySelectorAll('.proto-modal-scrim')].find(x=>/写入计划/.test(x.textContent)); s.querySelector('.proto-btn.primary').click();})()""")
time.sleep(0.4)
after=c.ev("Object.keys((todoById('recurring').plans||[])).length")
print('plans before/after blocked write:', before, after, 'toast', c.ev("(document.querySelector('.toast')||{}).textContent||''"))
assert after==before==0
errs=[e for e in c.errors() if 'favicon' not in e and '404' not in e and 'File not found' not in e]
print('errors',errs); assert not errs
assert c.ev('Proto.lastEnhancerError') is None
print('TEST8 PASS')
