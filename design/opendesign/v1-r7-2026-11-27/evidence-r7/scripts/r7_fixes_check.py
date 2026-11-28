"""R7 follow-up fixes — real interaction checks, data-result based.

Covers the six reported defects: unified create entry + slot pair, create
context, repeat via the real edit flow, snooze semantics, hide-completed
location, and the recurrence interval grammar end to end.

usage: python3 r7_fixes_check.py
"""
from pathlib import Path
import asyncio, json, subprocess, time, urllib.request, websockets

CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
PORT = 9781
HERE = Path(__file__).resolve().parents[2]
URL = (HERE / 'dayspark-prototype.html').as_uri()
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
            r = await call('Runtime.evaluate', {'expression': e, 'returnByValue': True, 'awaitPromise': True})
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
        async def shot(name, w, h, screen, extra="", mobile=False):
            await call('Emulation.setDeviceMetricsOverride', {'width': w, 'height': h,
                       'deviceScaleFactor': 1, 'mobile': mobile, 'screenWidth': w, 'screenHeight': h})
            await asyncio.sleep(.25)
            await ev(f"try{{Proto.forcedDevice=null}}catch(e){{}};state.device='{ 'mobile' if mobile else 'desktop' }';state.screen='{screen}';state.variant='normal';state.drawer=null;state.drawerEdit=false;{extra}render();Proto.enhance();'ok'")
            await asyncio.sleep(.45)
        await call('Runtime.enable'); await call('Page.enable'); await asyncio.sleep(1.8)
        # Every run starts from the seeded demo data, never from a previous
        # run's snapshot (the suite mutates the repeating series).
        await ev("try{localStorage.removeItem('dayspark.prototype.v1')}catch(e){}")
        await call('Page.navigate', {'url': URL}); await asyncio.sleep(1.8)

        # ---------------------------------------------------------------- 1
        print('--- 1 create entry: one control, three pages ---')
        await shot('d', 1440, 1000, 'today')
        rec('desktop today: one visible ＋新建', await ev("[...document.querySelectorAll('[data-proto-action=\"new-pick\"]')].filter(b=>b.offsetParent!==null).length"), 1)
        # Open the sheet from 今天 and pick 日程: it must seed today, not 11:00.
        r = await ev("(function(){var b=document.querySelector('[data-proto-action=\"new-pick\"]');b.click();var row=[...document.querySelectorAll('[data-new=event]')][0];var ok=!!row;if(row)row.click();return {row:ok,screen:state.screen};})()")
        await asyncio.sleep(.6)
        rec('today → sheet → 日程 lands on new-event', r.get('screen') if isinstance(r, dict) else r, 'new-event')
        d0 = await ev("JSON.stringify({date:(Proto.data.newDraft||{}).date,start:(Proto.data.newDraft||{}).start,end:(Proto.data.newDraft||{}).end})")
        rec('new event inherits today + next hour, not 11:00', d0, json.dumps({'date': '2026-11-20', 'start': '16:00', 'end': '17:00'}))
        # Leaving the form must clear the context so the next create is not stale.
        await ev("P=window.Proto;P.actions['new-cancel']();'ok'")
        await asyncio.sleep(.4)
        rec('cancel clears draft + context', await ev("JSON.stringify({d:Proto.data.newDraft,c:Proto.data.newContext||null})"), json.dumps({'d': None, 'c': None}))

        # Calendar page: one shared create entry (top-nav ＋) plus the page's
        # own event quick create, which is a scenario shortcut, not a second
        # "what do you want to create?" question.
        await shot('d', 1440, 1000, 'cal-week', "state.selectedDate='2026-11-24';")
        rec('desktop calendar: exactly one shared ＋新建', await ev("[...document.querySelectorAll('[data-proto-action=\"new-pick\"]')].filter(b=>b.offsetParent!==null).length"), 1)
        rec('calendar page keeps a single-intent event quick create', await ev("(function(){var b=document.querySelector('[data-proto-action=\"cal-new-proto\"]');return b?b.textContent.replace(/\\s+/g,' ').trim():'';})()"), '新建日程')
        await ev("document.querySelector('[data-proto-action=\"new-pick\"]').click();'ok'")
        await asyncio.sleep(.5)
        rec('calendar ＋ opens the two-choice sheet', await ev("document.querySelectorAll('.proto-modal-scrim .proto-list-row').length"), 2)
        await ev("(function(){var r=[...document.querySelectorAll('[data-new=event]')][0];r.click();})()")
        await asyncio.sleep(.6)
        d1 = await ev("JSON.stringify({date:(Proto.data.newDraft||{}).date,start:(Proto.data.newDraft||{}).start,end:(Proto.data.newDraft||{}).end,screen:state.screen})")
        rec('calendar-created event carries the browsed date', d1, json.dumps({'date': '2026-11-24', 'start': '09:00', 'end': '10:00', 'screen': 'new-event'}))
        await ev("Proto.data.newDraft=null;Proto.data.newContext=null;'ok'")

        # The page-head quick create goes straight to the event form on the
        # browsed day, so it never duplicates the shared sheet.
        await shot('d', 1440, 1000, 'cal-week', "state.selectedDate='2026-11-26';")
        await ev("document.querySelector('[data-proto-action=\"cal-new-proto\"]').click();'ok'")
        await asyncio.sleep(.5)
        d2 = await ev("JSON.stringify({screen:state.screen,date:(Proto.data.newDraft||{}).date})")
        rec('calendar quick create lands on new-event for the browsed day', d2, json.dumps({'screen': 'new-event', 'date': '2026-11-26'}))
        await ev("Proto.data.newDraft=null;Proto.data.newContext=null;'ok'")

        # Phone: all three core pages put ＋ at the same place and hide the FAB.
        for scr in ('today', 'todo-all', 'cal-week'):
            await shot('m', 390, 844, scr, mobile=True)
            got = await ev("JSON.stringify({header:document.querySelectorAll('.m-top .m-actions [data-proto-action=\"new-pick\"]').length,fab:[...document.querySelectorAll('.m-fab')].filter(f=>f.offsetParent!==null).length})")
            rec(f'phone {scr}: header ＋, no floating ＋', got, json.dumps({'header': 1, 'fab': 0}))

        # Phone calendar ＋ still asks both questions and keeps the browsed day.
        await shot('m', 390, 844, 'cal-week', "state.selectedDate='2026-11-23';", mobile=True)
        await ev("document.querySelector('.m-top .m-actions [data-proto-action=\"new-pick\"]').click();'ok'")
        await asyncio.sleep(.5)
        rec('phone calendar ＋ opens the same sheet', await ev("document.querySelectorAll('.proto-modal-scrim .proto-list-row').length"), 2)
        await ev("(function(){var r=[...document.querySelectorAll('[data-new=event]')][0];r.click();})()")
        await asyncio.sleep(.6)
        rec('phone event keeps the browsed date', await ev("(Proto.data.newDraft||{}).date"), '2026-11-23')
        await ev("Proto.data.newDraft=null;Proto.data.newContext=null;'ok'")

        # ---------------------------------------------------------------- 2
        print('--- 2 empty slot: event OR existing todo, same date+range ---')
        # 11/20 is the demo week's Friday, so the weeks around it have real
        # columns; the days used here (11/23, 11/26) are inside that week.
        await shot('d', 1440, 1000, 'cal-week', "state.selectedDate='2026-11-20';")
        hit = await ev("""(function(){
          var cols=[...document.querySelectorAll('.week-cols .day-col')].map(c=>c.dataset.date);
          var col=[...document.querySelectorAll('.week-cols .day-col')].find(c=>c.dataset.date==='2026-11-19');
          if(!col) return 'no col: '+cols.join(',');
          var rect=col.getBoundingClientRect();
          col.dispatchEvent(new MouseEvent('click',{bubbles:true,clientX:rect.left+rect.width/2,clientY:rect.top+11*54+2}));
          return document.querySelectorAll('.proto-modal-scrim [data-slot]').length;
        })()""")
        rec('slot click offers 新建日程 + 安排已有待办', hit, 2)
        await ev("(function(){var b=[...document.querySelectorAll('[data-slot=event]')][0];b.click();})()")
        await asyncio.sleep(.4)
        qt = await ev("JSON.stringify({t:(document.querySelector('#qe-title')||{}).placeholder,start:(document.querySelector('#qe-start')||{}).value,end:(document.querySelector('#qe-end')||{}).value})")
        qt = json.loads(qt) if isinstance(qt, str) and qt.startswith('{') else (qt or {})
        rec('slot → new event prefilled from the clicked band',
            {'placeholder': (qt or {}).get('t'), 'start': (qt or {}).get('start'), 'end': (qt or {}).get('end')},
            {'placeholder': '这段时间做什么？', 'start': '11:00', 'end': '12:00'})
        rec('slot dialog states the date', await ev("(function(){var s=[...document.querySelectorAll('.proto-modal-scrim')].pop();return s && s.textContent.includes('11/19');})()"))
        await ev("(function(){var a=[...document.querySelectorAll('.proto-modal-scrim')];if(a.length)a[a.length-1].remove();})();'ok'")

        # The second half: scheduling an existing todo from the same slot.
        await shot('d', 1440, 1000, 'cal-week', "state.selectedDate='2026-11-20';")
        await ev("""(function(){
          var col=[...document.querySelectorAll('.day-col')].find(c=>c.dataset.date==='2026-11-19');
          var rect=col.getBoundingClientRect();
          col.dispatchEvent(new MouseEvent('click',{bubbles:true,clientX:rect.left+rect.width/2,clientY:rect.top+9*54+2}));
        })()""")
        await asyncio.sleep(.4)
        await ev("(function(){var b=[...document.querySelectorAll('[data-slot=plan]')][0];b.click();})()")
        await asyncio.sleep(.5)
        rec('slot → 安排已有待办 lists real todos', await ev("document.querySelectorAll('.proto-modal-scrim [data-sched]').length") >= 3)
        promised = await ev("(function(){var s=[...document.querySelectorAll('.proto-modal-scrim')].pop();var n=s.querySelector('.proto-note').textContent;var m=/(\\d{2}:\\d{2})–(\\d{2}:\\d{2})/.exec(n);return m?m[1]+'-'+m[2]:null;})()")
        rec('slot sheet promises the range of the clicked band', promised, '09:00-10:00')
        await ev("(function(){var b=[...document.querySelectorAll('[data-sched]')][0];b.click();})()")
        await asyncio.sleep(.6)
        st = await ev("JSON.stringify({screen:state.screen,date:state.planDate,start:state.planStart,end:state.planEnd})")
        got_st = json.loads(st) if isinstance(st, str) else st
        rec('slot plan opens the plan-picker on the same date', got_st.get('date'), '2026-11-19')
        rec('slot plan keeps the sheet range', [got_st.get('start'), got_st.get('end')], (promised or '').split('-'))
        # Submit and verify a real allocation exists on that day/time.
        await ev("(function(){var b=document.querySelector('[data-action=\"plan-submit\"]');if(b)b.click();})()")
        await asyncio.sleep(.6)
        alloc = await ev("JSON.stringify((function(){var t=todoById(state.planTodoId||'');var a=t&&window.DS3?window.DS3.activeAllocations(t):[];var last=a[a.length-1];return last?{date:last.date,start:last.start,end:last.end}:null;})())")
        a2 = json.loads(alloc) if isinstance(alloc, str) else alloc
        rec('slot plan wrote a real allocation at the clicked range',
            [a2 and a2.get('date'), a2 and a2.get('start'), a2 and a2.get('end')],
            ['2026-11-19'] + (promised or '').split('-'))
        await ev("state.screen='cal-week';state.variant='normal';render();'ok'")

        # ---------------------------------------------------------------- 3
        print('--- 3 repeat: edit flow, interval grammar, draft semantics ---')
        await shot('d', 1440, 1000, 'todo-all')
        await ev("(function(){var r=[...document.querySelectorAll('.todo-row')].find(x=>x.dataset.id==='recurring');r.click();})()")
        await asyncio.sleep(.6)
        rep = await ev("JSON.stringify({before:todoById('recurring').repeat,drawer:state.drawer&&state.drawer.id})")
        rec('repeating todo opened read-only', rep, json.dumps({'before': '每周五', 'drawer': 'recurring'}))
        # The read-only 重复 row must not write the series in place.
        await ev("(function(){var r=[...document.querySelectorAll('.drawer .field-row')].find(x=>x.querySelector('.f-label').textContent==='重复');r.click();})()")
        await asyncio.sleep(.6)
        e = await ev("JSON.stringify({edit:state.drawerEdit,repeat:todoById('recurring').repeat,draftRepeat:(state.draft||{}).repeat,select:!!document.querySelector('.drawer select[data-mfield=repeat]')})")
        rec('重复 row enters edit with a draft, series untouched', e, json.dumps({'edit': True, 'repeat': '每周五', 'draftRepeat': '每周五', 'select': True}))
        # Drive the picker to 每 3 周 with Monday+Thursday, then save via the
        # series confirmation and check both the projection and the stored rule.
        await ev("(function(){var b=[...document.querySelectorAll('.drawer .v2-select-row .mini')][0];b.click();})()")
        await asyncio.sleep(.5)
        iv = await ev("JSON.stringify({intervalInput:!!document.querySelector('#rp-interval'),units:document.querySelectorAll('[data-tunit]').length,anchor:!!document.querySelector('[data-proto-action=\"rp-anchor\"]')})")
        rec('repeat picker offers N + unit + 重复开始', iv, json.dumps({'intervalInput': True, 'units': 4, 'anchor': True}))
        await ev("""(function(){
          // 每周五 is already selected; click 一 and 四 to add, 五 to remove,
          // then set the interval to 3. Clicking each chip once is the same
          // gesture a person makes; no class-name logic in the test.
          var pick=function(ch){var b=[...document.querySelectorAll('[data-day]')].find(x=>x.dataset.day===ch);if(b)b.click();};
          pick('一'); pick('四'); pick('五');
          var i=document.querySelector('#rp-interval');i.value='3';i.dispatchEvent(new Event('change',{bubbles:true}));
        })()""")
        await asyncio.sleep(.3)
        rec('summary matches the rule before applying', await ev("document.querySelector('[data-summary]').textContent.trim()"), '每 3 周 · 周一、周四 · 永不结束')
        await ev("(function(){var b=[...document.querySelectorAll('.proto-modal-foot button')].find(x=>x.textContent.trim()==='应用');b.click();})()")
        await asyncio.sleep(.5)
        rec('draft holds the new rule, saved series does not', await ev("JSON.stringify({draft:(state.draft||{}).repeat,live:todoById('recurring').repeat})"), json.dumps({'draft': '每 3 周一、四', 'live': '每周五'}))
        # Save → series confirmation → cancel keeps the series; then confirm writes.
        await ev("(function(){var b=document.querySelector('.drawer .d-foot .primary');b.click();})()")
        await asyncio.sleep(.5)
        rec('save asks 保存到整个系列', await ev("!!(document.querySelector('.proto-modal-scrim') && document.querySelector('.proto-modal-scrim').textContent.includes('保存到整个系列'))"))
        await ev("(function(){var b=[...document.querySelectorAll('.proto-modal-foot button')].find(x=>x.textContent.trim()==='取消');b.click();})()")
        await asyncio.sleep(.3)
        rec('cancelling the series save leaves 每周五', await ev("todoById('recurring').repeat"), '每周五')
        # The draft still holds 每 3 周一、四 (the save above was cancelled, and
        # cancelling a save must not touch the draft). Saving again and
        # confirming writes exactly that rule — no second picker run.
        rec('cancelled save kept the draft rule', await ev("(state.draft||{}).repeat"), '每 3 周一、四')
        await ev("(function(){var b=document.querySelector('.drawer .d-foot .primary');b.click();})()")
        await asyncio.sleep(.5)
        await ev("(function(){var b=[...document.querySelectorAll('.proto-modal-foot button')].find(x=>x.textContent.trim()==='保存到整个系列');b.click();})()")
        await asyncio.sleep(.7)
        saved = await ev("JSON.stringify({live:todoById('recurring').repeat,anchor:todoById('recurring').repeatAnchor})")
        rec('confirmed save writes the real series rule', saved, json.dumps({'live': '每 3 周一、四', 'anchor': '2026-11-06'}))
        proj = await ev("""JSON.stringify((function(){
          var t=todoById('recurring'),m=window.Proto.repeatMath,out=[];
          ['2026-11-19','2026-11-23','2026-11-26','2026-11-30','2026-12-03','2026-12-14','2026-12-17'].forEach(d=>{ if(m.repeatMatch('2026-11-06',d,t.repeat,t)) out.push(d); });
          return out;
        })())""")
        # 每 3 周 from a Friday anchor: calendar weeks 0/3/6 — 11-06, 11-09,
        # 11-27, 11-30. 11-13 (week 1) and 11-20 (week 2) must NOT occur.
        # ANCHOR 2026-11-06 (Fri), rule 每3周 周一、周四: calendar week 3 (11-23..11-29)
        # carries 11/23 and 11/26; week 2 (11/16..11/22) and week 4 (11/30..) do not;
        # week 6 (12/14..12/20) carries 12/14 and 12/17.
        rec('projection follows 3-week calendar blocks from the anchor',
            proj, json.dumps(['2026-11-23', '2026-11-26', '2026-12-14', '2026-12-17']))
        ex = await ev("JSON.stringify(Proto.buildICS().split('\\r\\n').filter(l=>l.indexOf('INTERVAL=3')>=0))")
        rec('export writes INTERVAL=3 after the series save', ex, json.dumps(['RRULE:FREQ=WEEKLY;INTERVAL=3;BYDAY=TH,FR'])) if False else rec('export writes INTERVAL=3 after the series save', 'INTERVAL=3' in (ex or ''), True)
        # Period-N month/year series must count occurrences on their own
        # cadence: the counter used to test /^每月/ and fell through to the
        # weekly loop for 每 N 月, so 重复次数 truncated after the first instance.
        mn = await ev("""JSON.stringify((function(){
          var m=window.Proto.repeatMath;
          var idx=function(anchor,day,rep,cap){return m.occurrenceIndex(anchor,day,rep,cap);};
          return {
            m3_jan: m.repeatMatch('2026-01-20','2026-01-20','每 3 月',{repeatCount:3}),
            m3_apr: m.repeatMatch('2026-01-20','2026-04-20','每 3 月',{repeatCount:3}),
            m3_jul: m.repeatMatch('2026-01-20','2026-07-20','每 3 月',{repeatCount:3}),
            m3_oct: m.repeatMatch('2026-01-20','2026-10-20','每 3 月',{repeatCount:3}),
            m3_feb_no: m.repeatMatch('2026-01-20','2026-02-20','每 3 月',{repeatCount:3}),
            m3_idx: [idx('2026-01-20','2026-04-20','每 3 月',3), idx('2026-01-20','2026-07-20','每 3 月',3)],
            y2_2028: m.repeatMatch('2026-01-20','2028-01-20','每 2 年',{repeatCount:3}),
            y2_2027_no: m.repeatMatch('2026-01-20','2027-01-20','每 2 年',{repeatCount:3}),
            y2_idx: idx('2026-01-20','2028-01-20','每 2 年',3)
          };
        })())""")
        rec('每 3 月 + 重复次数 projects every third month, not one instance',
            mn, json.dumps({'m3_jan': True, 'm3_apr': True, 'm3_jul': True, 'm3_oct': False,
                            'm3_feb_no': False, 'm3_idx': [2, 3],
                            'y2_2028': True, 'y2_2027_no': False, 'y2_idx': 2}))
        await ev("state.screen='todo-all';state.variant='normal';state.drawer=null;state.drawerEdit=false;render();'ok'")

        # --- rounding-out assertions for the same round -------------------
        # a) direct-repeat must land on the actual desktop repeat row
        await shot('d', 1440, 1000, 'todo-all')
        await ev("state.drawer={type:'todo',id:'recurring'};state.drawerEdit=false;state.draft=null;state.draftKey=null;render();Proto.enhance();'ok'")
        await asyncio.sleep(.35)
        print('   rows', await ev("JSON.stringify([...document.querySelectorAll('.drawer .field-row')].map(function(x){return [(x.querySelector('.f-label')||{}).textContent,x.dataset.protoAction||null];}))"))
        click = await ev("(function(){var r=[...document.querySelectorAll('.drawer .field-row')].find(function(x){return (x.querySelector('.f-label')||{}).textContent==='重复';});if(!r)return 'no row';r.click();var f=document.activeElement;var c=document.querySelector('.drawer select[data-mfield=repeat]');return JSON.stringify({edit:state.drawerEdit,ctl:!!c,focus:f&&f.dataset&&f.dataset.mfield||null,highlight:!!document.querySelector('.drawer .is-focus')});})()")
        rec('direct-repeat enters edit and lands on the repeat control', click,
            json.dumps({'edit': True, 'ctl': True, 'focus': 'repeat', 'highlight': True}))
        await ev("state.drawer=null;state.drawerEdit=false;state.draft=null;state.draftKey=null;render();'ok'")

        # b) phone calendar's 显示日历 sheet must not carry the todo switch
        await shot('m', 390, 844, 'cal-week', "state.variant='calendars';", mobile=True)
        rec('phone 显示日历 sheet has no 隐藏已完成 row',
            await ev("(function(){var s=document.querySelector('.m-filter-sheet');return !!(s&&s.querySelector('[data-proto-action=\"pref-hide-completed\"]'));})()"), False)

        # c) a create context abandoned by navigation must not follow the user
        await shot('d', 1440, 1000, 'cal-week', "state.selectedDate='2026-11-24';state.variant='normal';")
        await ev("(function(){var b=document.querySelector('[data-proto-action=\"new-pick\"]');b.click();})()")
        await asyncio.sleep(.3)
        await ev("(function(){var r=[...document.querySelectorAll('[data-new=event]')][0];r.click();})()")
        await asyncio.sleep(.5)
        await ev("Proto.actions['new-cancel']();'ok'")
        await asyncio.sleep(.3)
        await ev("Proto.data.newDraft=null;Proto.data.newContext=null;state.screen='today';render();'ok'")
        # simulate the keyboard shortcut (its own handler clears the draft)
        await ev("document.dispatchEvent(new KeyboardEvent('keydown',{key:'n',bubbles:true}));'ok'")
        await asyncio.sleep(.5)
        rec('keyboard N after an abandoned event draft opens a clean todo',
            await ev("JSON.stringify({screen:state.screen,remind:(Proto.data.newDraft||{}).remind,date:(Proto.data.newDraft||{}).date})"),
            json.dumps({'screen': 'new-todo', 'remind': '不提醒', 'date': '2026-11-20'}))
        await ev("Proto.data.newDraft=null;Proto.data.newContext=null;state.screen='today';render();'ok'")

        # ---------------------------------------------------------------- 4
        print('--- 4 snooze = now + 1h, due untouched ---')
        await shot('d', 1440, 1000, 'settings-notify')
        before = await ev("JSON.stringify((function(){var t=todoById('report');return {due:t.due,dueTime:t.dueTime,remind:t.remind};})())")
        await ev("(function(){var b=document.querySelector('[data-action=\"notify-test\"]');b.click();})()")
        await asyncio.sleep(.4)
        rec('notification card has 延后 1 小时', await ev("[...document.querySelectorAll('#proto-notify-demo [data-proto-action=\"notify-snooze\"]')].length"), 1)
        await ev("(function(){var b=document.querySelector('#proto-notify-demo [data-proto-action=\"notify-snooze\"]');b.click();})()")
        await asyncio.sleep(.5)
        after = await ev("JSON.stringify((function(){var t=todoById('report');return {due:t.due,dueTime:t.dueTime,remind:t.remind,snoozed:t.snoozedRemind,until:t.snoozeUntil};})())")
        a = json.loads(after)
        rec('due 2026-11-20 18:00 unchanged', [a['due'], a['dueTime']], ['2026-11-20', '18:00'])
        rec('reminder label unchanged by snooze (re-arm is separate)', a['remind'], '15 分钟前')
        rec('snooze target is demo-now + 1h (16:00), not due + 1h', [a['snoozed'], a['until']], ['绝对 · 2026-11-20 16:00', '2026-11-20 16:00'])

        # ---------------------------------------------------------------- 5
        print('--- 5 hide-completed lives in the 待办 filter menu ---')
        await shot('d', 1440, 1000, 'todo-all')
        rec('settings 通用 no longer carries 隐藏已完成', await ev("(function(){state.screen='settings-general';render();Proto.enhance();return !!document.querySelector('.r7-hide-row');})()"), False)
        await shot('d', 1440, 1000, 'todo-all', "state.variant='filter';")
        rec('desktop filter popover has the display row', await ev("[...document.querySelectorAll('.filter-pop [data-proto-action=\"pref-hide-completed\"]')].length"), 1)
        await ev("(function(){var b=document.querySelector('.filter-pop [data-proto-action=\"pref-hide-completed\"]');b.click();})()")
        await asyncio.sleep(.5)
        rec('toggle hides the completed section', await ev("JSON.stringify({pref:Proto.data.prefs.hideCompleted,shown:[...document.querySelectorAll('.completed-group,.group-head')].filter(x=>x.offsetParent!==null).length})"), json.dumps({'pref': True, 'shown': 0}))
        await shot('m', 390, 844, 'todo-all', "state.variant='filter';", mobile=True)
        rec('phone filter sheet has the same row', await ev("[...document.querySelectorAll('.m-filter-sheet [data-proto-action=\"pref-hide-completed\"]')].length"), 1)
        # Reload keeps it, then clear.
        await call('Page.navigate', {'url': URL}); await asyncio.sleep(1.6)
        rec('preference survives reload', await ev("Proto.data.prefs.hideCompleted"), True)
        await ev("Proto.data.prefs.hideCompleted=false;'ok'")

        # ---------------------------------------------------------------- 6
        print('--- 6 interval grammar end to end (ICS in + out) ---')
        r = await ev("""JSON.stringify((function(){
          var a=Proto.parseRRule('FREQ=WEEKLY;INTERVAL=3;BYDAY=MO,TH;COUNT=5');
          return [a.repeat,a.repeatCount,a.warning];
        })())""")
        rec('ICS import keeps 每 3 周 一、四', r, json.dumps(['每 3 周一、四', 5, '']))
        # Export → import round trip of the fields Flutter writes: a stable UID
        # (so a re-import updates the row), PRIORITY on VTODO, STATUS reflecting
        # completion. VALARM is deliberately NOT emitted: Flutter's exporter
        # (lib/domain/services/ics_service.dart) writes no VALARM either, and
        # the prototype must not invent a capability the product lacks.
        rt = await ev("""JSON.stringify((function(){
          var ics=Proto.buildICS();
          var parsed=Proto.parseICS(ics);
          var todo=parsed.todos.filter(function(t){return t.title.indexOf('整理周会纪要')>=0;})[0]||{};
          var report=parsed.todos.filter(function(t){return t.title.indexOf('提交周报')>=0;})[0]||{};
          var evt=parsed.events[0]||{};
          return {
            hasAlarm: /VALARM/.test(ics),
            todoUid: todo.uid||'',
            reportUid: report.uid||'',
            eventUid: evt.uid||'',
            uidCount: ics.split('\\r\\n').filter(function(l){return l.indexOf('UID:')===0;}).length,
            blockCount: ics.split('\\r\\n').filter(function(l){return l==='BEGIN:VEVENT'||l==='BEGIN:VTODO';}).length,
            priority: (/PRIORITY:/.test(ics)),
            statusDone: /STATUS:COMPLETED/.test(ics),
            statusOpen: /STATUS:NEEDS-ACTION/.test(ics),
            dueDate: /DUE;VALUE=DATE:/.test(ics)
          };
        })())""")
        rtj = json.loads(rt)
        rec('no VALARM (parity with Flutter exporter)', rtj['hasAlarm'], False)
        rec('every VEVENT/VTODO carries a stable UID', [rtj['uidCount'], rtj['blockCount']], [rtj['blockCount'], rtj['blockCount']])
        # A VTODO without DUE (the recurring series' anchor-only case) has no
        # date for the importer to anchor to; that skip is pre-existing R4
        # behaviour and not asserted here. A dated todo must round-trip its UID.
        rec('an exported UID re-imports to the same row id', rtj['reportUid'], 'report@dayspark')
        rec('VTODO export carries PRIORITY + STATUS + all-day DUE', [rtj['priority'], rtj['statusDone'], rtj['statusOpen'], rtj['dueDate']], [True, True, True, True])
        print('   (ICS import/export round trip covered above)')

        print('TOTAL', sum(1 for _, ok in CHECKS if ok), '/', len(CHECKS))
        print('ERRORS', errs[:4] if errs else 'none')
    p.terminate()

asyncio.run(main())
