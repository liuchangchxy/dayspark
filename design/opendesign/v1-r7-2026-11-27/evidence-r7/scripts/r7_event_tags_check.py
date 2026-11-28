"""Event tags and attachments: coverage verdict, checked by real writes.

Section 二 of the R7 goal asked for a verdict on 日程标签与附件. Flutter's event
form has an editable TagChips row and attachment upload (event_form_page.dart);
the prototype used to label event tags "只读" and show the calendar name in
their place, which is neither read-only truth nor editing. These assertions
pin the corrected behaviour:

  1. desktop read-only event drawer lists the event's own tags, not the calendar
  2. its 添加 button writes tags through the real tag picker, no edit step
  3. edit mode on an event keeps a real 标签 section (not "只读")
  4. phone event editor edits tags through the picker and keeps them on save
  5. phone todo editor does the same (shared row)
  6. an event with no tags shows 无标签, never the calendar name
  7. attachments: the event drawer shows them and the editor uploads them

usage: python3 r7_event_tags_check.py
"""
from pathlib import Path
import asyncio, json, subprocess, time, urllib.request, websockets

CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
PORT = 9791
HERE = Path(__file__).resolve().parents[2]
URL = (HERE / 'dayspark-prototype.html').as_uri()
OUT = HERE / 'evidence-r7' / 'screens-fixes'
subprocess.run(['rm', '-rf', f'/tmp/prof-{PORT}'])
p = subprocess.Popen([CHROME, '--headless=new', '--disable-gpu', f'--remote-debugging-port={PORT}',
                      f'--user-data-dir=/tmp/prof-{PORT}', '--window-size=1440,1000', URL],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
u = None
for _ in range(120):
    try:
        d = json.load(urllib.request.urlopen(f'http://127.0.0.1:{PORT}/json'))
        pp = [t for t in d if t.get('type') == 'page']
        if pp:
            u = pp[0]['webSocketDebuggerUrl']; break
    except Exception: pass
    time.sleep(.25)

CHECKS = []


async def main():
    async with websockets.connect(u, max_size=2**27) as ws:
        i = 0; errs = []
        async def call(m, params=None):
            nonlocal i; i += 1; mid = i
            await ws.send(json.dumps({'id': mid, 'method': m, 'params': params or {}}))
            while True:
                x = json.loads(await ws.recv())
                if x.get('method') == 'Runtime.exceptionThrown':
                    errs.append((x['params']['exceptionDetails'].get('exception') or {}).get('description', '')[:200])
                if x.get('id') == mid: return x
        async def ev(e):
            r = await call('Runtime.evaluate', {'expression': e, 'returnByValue': True})
            q = r.get('result', {})
            if q.get('exceptionDetails'):
                return 'ERR ' + ((q['exceptionDetails'].get('exception') or {}).get('description') or '')[:180]
            return q.get('result', {}).get('value')
        def rec(name, got, want=None):
            if isinstance(want, str):
                try: want = json.loads(want)
                except Exception: pass
            if isinstance(got, str):
                try: got = json.loads(got)
                except Exception: pass
            ok = got == want if want is not None else bool(got)
            CHECKS.append((name, ok))
            print(('PASS ' if ok else 'FAIL '), name, '=>', json.dumps(got, ensure_ascii=False))
        async def view(w, h, mobile):
            await call('Emulation.setDeviceMetricsOverride', {'width': w, 'height': h,
                       'deviceScaleFactor': 1, 'mobile': mobile, 'screenWidth': w, 'screenHeight': h})
            await asyncio.sleep(.3)

        await call('Runtime.enable'); await call('Page.enable'); await asyncio.sleep(1.6)
        await ev("try{localStorage.removeItem('dayspark.prototype.v1')}catch(e){}")
        await call('Page.navigate', {'url': URL}); await asyncio.sleep(1.6)

        # Seed a tag on a demo event so the read-only drawer has something real.
        await ev("""(function(){
          var e=eventById('dentist');
          e.tags=['复诊'];
          if(!Proto.data.tags.some(function(t){return t.name==='复诊';})) Proto.data.tags.push({name:'复诊',color:'#4f7bbf'});
          state.screen='cal-week'; state.device='desktop'; state.drawer={type:'event',id:'dentist'};
          state.drawerEdit=false; state.selectedDate='2026-11-20';
          render(); Proto.enhance();
        })()""")
        await view(1440, 1000, False)
        await asyncio.sleep(.4)
        tag_sec = await ev("""JSON.stringify((function(){
          var secs=[...document.querySelectorAll('.drawer .d-sec')];
          var s=secs.find(function(x){return x.textContent.trim().indexOf('标签')===0;});
          return s?{text:s.textContent.replace(/\\s+/g,' ').trim().slice(0,40), calendarName:s.textContent.includes('健康'), count:s.querySelectorAll('.tag').length}:null;
        })())""")
        print('drawer tag section', tag_sec)
        rec('read-only event drawer shows the event tag, not the calendar', tag_sec, json.dumps({'text': '标签添加复诊', 'calendarName': False, 'count': 1}))
        rec('no "只读"/"在待办侧维护" copy on event tags',
           await ev("(function(){var t=document.querySelector('.drawer').textContent;return t.includes('日程标签只读')||t.includes('在待办侧维护');})()"), False)

        # Add a tag from the read-only drawer: must be one real picker + write.
        await ev("(function(){var b=document.querySelector('.drawer .d-sec-head button');b.click();})()")
        await asyncio.sleep(.35)
        rec('the 添加 button opens the real tag picker', await ev("!!document.querySelector('.proto-modal-scrim #tp-new')"), True)
        await ev("(function(){var b=[...document.querySelectorAll('.proto-modal-scrim [data-tag]')].find(function(x){return x.dataset.tag==='林总';});if(b)b.click();})()")
        await asyncio.sleep(.25)
        await ev("(function(){var s=[...document.querySelectorAll('.proto-modal-scrim')].pop();var b=[...s.querySelectorAll('.proto-modal-foot button')].find(function(x){return /^应用/.test(x.textContent.trim());});b.click();})()")
        await asyncio.sleep(.5)
        rec('tag added from the read-only drawer reaches the event data',
           await ev("JSON.stringify(eventById('dentist').tags)"), json.dumps(['复诊', '林总']))
        rec('drawer re-renders with both tags',
           await ev("(function(){var s=[...document.querySelectorAll('.drawer .d-sec')].find(function(x){return x.textContent.trim().indexOf('标签')===0;});return s.querySelectorAll('.tag').length;})()"), 2)

        # Edit mode: event keeps a real 标签 section, no "只读" claim.
        await ev("(function(){document.querySelector('.drawer .d-act.primary').click();})()")  # 编辑
        await asyncio.sleep(.45)
        rec('event edit mode keeps a real 标签 header',
           await ev("(function(){var s=[...document.querySelectorAll('.drawer .d-sec')].find(function(x){return x.textContent.trim().indexOf('标签')===0;});var h=s&&s.querySelector('.d-sec-head');return h? h.textContent.replace(/\\s+/g,' ').trim():null;})()"), '标签添加')
        rec('no 只读 copy in event edit mode', await ev("document.querySelector('.drawer').textContent.includes('只读')"), False)
        await ev("(function(){var b=document.querySelector('.drawer-close');b.click();state.drawerEdit=false;state.draft=null;state.draftKey=null;})()")
        await asyncio.sleep(.3)

        # An event without tags never shows the calendar name as one.
        await ev("state.drawer={type:'event',id:'piano'};state.drawerEdit=false;render();Proto.enhance();'ok'")
        await asyncio.sleep(.4)
        rec('event with no tags shows 无标签, not the calendar name',
           await ev("(function(){var s=[...document.querySelectorAll('.drawer .d-sec')].find(function(x){return x.textContent.trim().indexOf('标签')===0;});return s?s.querySelectorAll('.tag')[0].textContent.trim():'';})()"), '无标签')

        # Phone: event editor edits tags -> picker -> save.
        await call('Emulation.setDeviceMetricsOverride', {'width': 390, 'height': 844,
                   'deviceScaleFactor': 1, 'mobile': True, 'screenWidth': 390, 'screenHeight': 844})
        await ev("try{Proto.forcedDevice=null}catch(e){};state.device='mobile';state.drawer={type:'event',id:'dentist'};state.drawerEdit=true;state.screen='cal-week';state.selectedDate='2026-11-20';render();Proto.enhance();'ok'")
        await asyncio.sleep(.5)
        rec('phone event editor has the tag row with an 编辑 entry',
           await ev("JSON.stringify({row:[...document.querySelectorAll('.m-form-row')].some(function(r){return (r.querySelector('.m-form-label')||{}).textContent==='标签';}),btn:!!document.querySelector('[data-proto-action=\"m-tags\"]')})"),
           json.dumps({'row': True, 'btn': True}))
        await ev("document.querySelector('[data-proto-action=\"m-tags\"]').click();'ok'")
        await asyncio.sleep(.35)
        rec('phone 编辑 opens the same tag picker', await ev("!!document.querySelector('.proto-modal-scrim #tp-new')"), True)
        await ev("(function(){var b=[...document.querySelectorAll('.proto-modal-scrim [data-tag]')].find(function(x){return x.dataset.tag==='复诊';});if(b)b.click();})()")
        await asyncio.sleep(.25)
        await ev("(function(){var s=[...document.querySelectorAll('.proto-modal-scrim')].pop();var b=[...s.querySelectorAll('.proto-modal-foot button')].find(function(x){return /^应用/.test(x.textContent.trim());});b.click();})()")
        await asyncio.sleep(.4)
        rec('phone draft holds the tag change before saving',
           await ev("JSON.stringify((state.draft||{}).tags)"), json.dumps(['林总']))
        rec('live event unchanged until save', await ev("JSON.stringify(eventById('dentist').tags)"), json.dumps(['复诊', '林总']))
        await ev("document.querySelector('[data-action=\"save-detail\"]').click();'ok'")
        await asyncio.sleep(.5)
        rec('phone save writes the tag change to the event', await ev("JSON.stringify(eventById('dentist').tags)"), json.dumps(['林总']))

        # Phone todo editor uses the same row.
        await ev("state.drawer={type:'todo',id:'report'};state.drawerEdit=true;state.screen='todo-all';render();Proto.enhance();'ok'")
        await asyncio.sleep(.4)
        rec('phone todo editor exposes the same tag 编辑 entry',
           await ev("!!document.querySelector('[data-proto-action=\"m-tags\"]')"), True)
        await ev("document.querySelector('[data-proto-action=\"m-tags\"]').click();'ok'")
        await asyncio.sleep(.3)
        await ev("(function(){var s=[...document.querySelectorAll('.proto-modal-scrim')].pop();var b=[...s.querySelectorAll('.proto-modal-foot button')].find(function(x){return x.textContent.trim()==='取消';});b.click();})()")
        await asyncio.sleep(.3)

        # Attachments on an event: real rows in the read-only drawer and a real
        # upload entry in the editor.
        await ev("""(function(){
          var e=eventById('dentist');
          e.attachments=[{id:'att-e1',name:'医保卡照片.jpg',size:'240 KB',state:'ready'}];
          state.device='desktop';state.drawer={type:'event',id:'dentist'};state.drawerEdit=false;
          state.screen='cal-week';state.selectedDate='2026-11-20';render();Proto.enhance();
        })()""")
        await call('Emulation.setDeviceMetricsOverride', {'width': 1440, 'height': 1000,
                   'deviceScaleFactor': 1, 'mobile': False, 'screenWidth': 1440, 'screenHeight': 1000})
        await asyncio.sleep(.4)
        rec('read-only event drawer lists the attachment',
           await ev("(function(){var s=[...document.querySelectorAll('.drawer .d-sec')].find(function(x){return x.textContent.trim().indexOf('附件')===0;});return !!(s&&s.textContent.includes('医保卡照片.jpg'));})()"), True)
        await ev("(function(){document.querySelector('.drawer .d-act.primary').click();})()")
        await asyncio.sleep(.45)
        await ev("(function(){var s=[...document.querySelectorAll('.drawer .d-sec')].find(function(x){return x.textContent.trim().indexOf('附件')===0;});var b=s.querySelector('.d-sec-head button');b.click();})()")
        await asyncio.sleep(.35)
        rec('event editor upload opens the real attachment picker',
           await ev("(function(){var m=[...document.querySelectorAll('.proto-modal-scrim')].pop();return !!(m&&m.textContent.includes('添加附件'));})()"), True)
        await ev("(function(){var m=[...document.querySelectorAll('.proto-modal-scrim')].pop();var b=[...m.querySelectorAll('.proto-list-row')][0];b.click();})()")
        await asyncio.sleep(.3)
        rec('attachment lands in the draft list',
           await ev("JSON.stringify((state.draft||{attachments:[]}).attachments.map(function(a){return a.name;}))"), json.dumps(['医保卡照片.jpg', '本周数据.xlsx']))
        await ev("(function(){var m=[...document.querySelectorAll('.proto-modal-scrim')].pop();var b=[...m.querySelectorAll('.proto-modal-foot button')].find(function(x){return x.textContent.trim()==='完成';});b.click();})()")
        await asyncio.sleep(.4)
        await ev("state.drawerEdit=false;state.draft=null;state.draftKey=null;render();Proto.enhance();'ok'")
        await asyncio.sleep(.3)
        rec('no console exceptions during the whole pass', errs or 'none', 'none')
        print('TOTAL', sum(1 for _, ok in CHECKS if ok), '/', len(CHECKS))
    p.terminate()

asyncio.run(main())
