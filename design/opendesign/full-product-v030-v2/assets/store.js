/* DaySpark prototype store — one in-memory model shared by every view.
   Persistence is best-effort localStorage; the prototype works without it. */
(function () {
  'use strict';

  var KEY = 'dayspark-full-product-v030-v2';
  var DAY = 86400000;

  function startOfDay(d) { var x = new Date(d); x.setHours(0, 0, 0, 0); return x; }
  function addDays(d, n) { var x = new Date(d); x.setDate(x.getDate() + n); return x; }
  function at(dayOffset, hour, minute) {
    var d = addDays(startOfDay(new Date()), dayOffset);
    d.setHours(hour, minute || 0, 0, 0);
    return d;
  }
  function iso(d) { return d ? new Date(d).toISOString() : null; }
  function sameDay(a, b) {
    if (!a || !b) return false;
    a = new Date(a); b = new Date(b);
    return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
  }

  // Demo clock: 14:30 keeps "现在 / 接下来 / 今天截止" all meaningful.
  var NOW = (function () { var d = new Date(); d.setHours(14, 30, 0, 0); return d; })();

  function seed() {
    var tomorrow = 1;
    return {
      now: iso(NOW),
      calendars: [
        { id: 'c1', name: '个人', color: '#4F6D8C' },
        { id: 'c2', name: '工作', color: '#6F5D7E' },
        { id: 'c3', name: '学习', color: '#4F7368' }
      ],
      tags: [
        { id: 't1', name: '深度工作', color: '#6F5D7E' },
        { id: 't2', name: '会议', color: '#4F6D8C' },
        { id: 't3', name: '生活', color: '#4F7368' },
        { id: 't4', name: '购物', color: '#9A6248' }
      ],
      todos: [
        {
          id: 'td1', title: '写论文方法章节', notes: '先补完实验设计，再把结果对齐到第三章。',
          due: iso(at(0, 18, 0)), dueHasTime: true, done: false, calendarId: 'c3',
          priority: 2, tags: ['t1'], deleted: false,
          allocation: { start: iso(at(0, 15, 0)), end: iso(at(0, 16, 0)) },
          reminders: [{ id: 'r1', offset: 30 }], repeat: null,
          subtasks: [
            { id: 's1', title: '整理实验数据', done: true },
            { id: 's2', title: '补写 3.2 节', done: false }
          ]
        },
        {
          id: 'td2', title: '回复客户邮件', notes: '', due: iso(at(0, 17, 0)), dueHasTime: true,
          done: false, calendarId: 'c2', priority: 1, tags: ['t2'], deleted: false,
          allocation: null, reminders: [], repeat: null, subtasks: []
        },
        {
          id: 'td3', title: '准备周会材料', notes: '数据看板截图 + 三个风险点。',
          due: iso(at(0, 14, 0)), dueHasTime: true, done: false, calendarId: 'c2',
          priority: 2, tags: ['t2'], deleted: false,
          allocation: { start: iso(at(0, 11, 0)), end: iso(at(0, 12, 0)) },
          reminders: [{ id: 'r2', offset: 10 }], repeat: null, subtasks: []
        },
        {
          id: 'td4', title: '整理上周会议纪要', notes: '', due: iso(at(-1, 18, 0)), dueHasTime: true,
          done: false, calendarId: 'c2', priority: 1, tags: ['t2'], deleted: false,
          allocation: null, reminders: [], repeat: null, subtasks: []
        },
        {
          id: 'td5', title: '修复登录页在深色模式下的对比度', notes: '按钮文字与背景只有 2.8:1。',
          due: iso(at(0, 20, 0)), dueHasTime: true, done: false, calendarId: 'c2',
          priority: 3, tags: [], deleted: false, allocation: null, reminders: [], repeat: null, subtasks: []
        },
        {
          id: 'td6', title: '买牛奶和鸡蛋', notes: '', due: null, dueHasTime: false, done: false,
          calendarId: 'c1', priority: 0, tags: ['t4'], deleted: false, allocation: null,
          reminders: [], repeat: null, subtasks: []
        },
        {
          id: 'td7', title: '预约牙医', notes: '', due: iso(at(3, 0, 0)), dueHasTime: false, done: false,
          calendarId: 'c1', priority: 1, tags: [], deleted: false, allocation: null,
          reminders: [], repeat: null, subtasks: []
        },
        {
          id: 'td8', title: '读完《设计中的设计》第三章', notes: '', due: null, dueHasTime: false,
          done: false, calendarId: 'c3', priority: 0, tags: [], deleted: false, allocation: null,
          reminders: [], repeat: null, subtasks: []
        },
        {
          id: 'td9', title: '跑步 5 公里', notes: '', due: null, dueHasTime: false, done: false,
          calendarId: 'c1', priority: 0, tags: ['t3'], deleted: false,
          allocation: { start: iso(at(0, 19, 0)), end: iso(at(0, 19, 40)) },
          reminders: [], repeat: 'daily', subtasks: []
        },
        {
          id: 'td10', title: '交房租', notes: '', due: iso(at(5, 0, 0)), dueHasTime: false, done: false,
          calendarId: 'c1', priority: 2, tags: [], deleted: false, allocation: null,
          reminders: [{ id: 'r3', offset: 1440 }], repeat: 'monthly', subtasks: []
        },
        {
          id: 'td11', title: '更新简历和作品集', notes: '', due: null, dueHasTime: false, done: false,
          calendarId: 'c1', priority: 0, tags: [], deleted: false, allocation: null,
          reminders: [], repeat: null, subtasks: []
        },
        {
          id: 'td12', title: '给设计稿补上键盘操作说明', notes: '', due: null, dueHasTime: false,
          done: false, calendarId: 'c2', priority: 1, tags: [], deleted: false, allocation: null,
          reminders: [], repeat: null, subtasks: []
        },
        {
          id: 'td13', title: '晨间复盘', notes: '', due: iso(at(0, 9, 0)), dueHasTime: true, done: true,
          completedAt: iso(at(0, 9, 20)), calendarId: 'c1', priority: 0, tags: ['t3'], deleted: false,
          allocation: null, reminders: [], repeat: null, subtasks: []
        },
        {
          id: 'td14', title: '提交报销单', notes: '', due: iso(at(0, 12, 0)), dueHasTime: true, done: true,
          completedAt: iso(at(0, 11, 40)), calendarId: 'c2', priority: 0, tags: [], deleted: false,
          allocation: null, reminders: [], repeat: null, subtasks: []
        },
        {
          id: 'td15', title: '旧版导出脚本清理', notes: '', due: null, dueHasTime: false, done: false,
          calendarId: 'c2', priority: 0, tags: [], deleted: true, deletedAt: iso(at(-2, 10, 0)),
          allocation: null, reminders: [], repeat: null, subtasks: []
        }
      ],
      events: [
        {
          id: 'e1', title: '每日站会', start: iso(at(0, 9, 30)), end: iso(at(0, 10, 0)),
          allDay: false, calendarId: 'c2', location: '会议室 A / 线上', notes: '',
          reminders: [{ id: 'er1', offset: 5 }], repeat: 'weekly', deleted: false
        },
        {
          id: 'e2', title: '产品评审：v0.30 信息架构', start: iso(at(0, 14, 0)), end: iso(at(0, 15, 0)),
          allDay: false, calendarId: 'c2', location: '线上', notes: '确认今天 / 日历 / 待办三段式与创建语义。',
          reminders: [{ id: 'er2', offset: 10 }], repeat: null, deleted: false
        },
        {
          id: 'e3', title: '和朋友吃饭', start: iso(at(0, 18, 30)), end: iso(at(0, 19, 30)),
          allDay: false, calendarId: 'c1', location: '云南小馆', notes: '',
          reminders: [], repeat: null, deleted: false
        },
        {
          id: 'e4', title: '一对一沟通', start: iso(at(tomorrow, 10, 0)), end: iso(at(tomorrow, 11, 0)),
          allDay: false, calendarId: 'c2', location: '线上', notes: '',
          reminders: [], repeat: null, deleted: false
        },
        {
          id: 'e5', title: '牙医复诊', start: iso(at(3, 15, 0)), end: iso(at(3, 16, 0)),
          allDay: false, calendarId: 'c1', location: '口腔医院', notes: '',
          reminders: [{ id: 'er3', offset: 60 }], repeat: null, deleted: false
        }
      ],
      settings: {
        theme: 'light',
        accent: '蓝',
        language: '跟随系统',
        defaultTab: '今天',
        hideCompleted: false,
        weekStart: '周一',
        timeFormat: '24 小时'
      },
      ui: { todoView: 'unplanned', calendarView: 'week' }
    };
  }

  var state = null;

  function load() {
    try {
      var raw = localStorage.getItem(KEY);
      if (raw) {
        state = JSON.parse(raw);
        var muted = {
          '#2563EB': '#4F6D8C', '#2457D6': '#4F6D8C',
          '#7C3AED': '#6F5D7E', '#0D9488': '#4F7368',
          '#2F7D5A': '#4F7368', '#C2410C': '#9A6248',
          '#DB2777': '#8F5A68'
        };
        (state.calendars || []).forEach(function (c) { if (muted[c.color]) c.color = muted[c.color]; });
        (state.tags || []).forEach(function (t) { if (muted[t.color]) t.color = muted[t.color]; });
        var defaults = {
          theme: 'light', accent: '蓝', language: '跟随系统', defaultTab: '今天',
          hideCompleted: false, weekStart: '周一', timeFormat: '24 小时'
        };
        if (!state.settings) state.settings = {};
        for (var k in defaults) if (state.settings[k] === undefined) state.settings[k] = defaults[k];
        return;
      }
    } catch (e) { /* storage blocked — in-memory only */ }
    state = seed();
  }

  function persist() {
    try { localStorage.setItem(KEY, JSON.stringify(state)); } catch (e) { /* ignore */ }
  }

  var listeners = [];
  function subscribe(fn) { listeners.push(fn); return function () { listeners = listeners.filter(function (f) { return f !== fn; }); }; }
  function emit() { persist(); listeners.forEach(function (fn) { try { fn(); } catch (e) { console.error(e); } }); }

  function uid(prefix) { return (prefix || 'x') + Math.random().toString(36).slice(2, 8); }
  function byId(list, id) { return list.filter(function (x) { return x.id === id; })[0] || null; }

  var api = {
    NOW: NOW,
    get state() { return state; },
    subscribe: subscribe,
    emit: emit,
    uid: uid,
    byId: byId,
    sameDay: sameDay,
    addDays: addDays,
    startOfDay: startOfDay,
    weekIndex: function (d) {
      var g = new Date(d).getDay();
      return (g - (state.settings.weekStart === '周日' ? 0 : 1) + 7) % 7;
    },

    calendar: function (id) { return byId(state.calendars, id) || state.calendars[0]; },
    tag: function (id) { return byId(state.tags, id); },

    activeTodos: function () { return state.todos.filter(function (t) { return !t.done && !t.deleted; }); },
    doneTodos: function () { return state.todos.filter(function (t) { return t.done && !t.deleted; }); },
    trashedTodos: function () { return state.todos.filter(function (t) { return t.deleted; }); },
    activeEvents: function () { return state.events.filter(function (e) { return !e.deleted; }); },

    isUnplanned: function (t) { return !t.done && !t.deleted && !t.allocation; },

    unplanned: function () { return api.activeTodos().filter(function (t) { return !t.allocation; }); },
    planned: function () { return api.activeTodos().filter(function (t) { return !!t.allocation; }); },
    dueOn: function (day) {
      return api.activeTodos().filter(function (t) { return t.due && sameDay(t.due, day); });
    },
    overdue: function () {
      return api.activeTodos().filter(function (t) {
        return t.due && new Date(t.due) < NOW && !sameDay(t.due, NOW);
      });
    },
    eventsOn: function (day) {
      return api.activeEvents().filter(function (e) { return sameDay(e.start, day); })
        .sort(function (a, b) { return new Date(a.start) - new Date(b.start); });
    },
    allocationsOn: function (day) {
      return api.activeTodos().filter(function (t) {
        return t.allocation && sameDay(t.allocation.start, day);
      }).sort(function (a, b) { return new Date(a.allocation.start) - new Date(b.allocation.start); });
    },

    todayModel: function () {
      var current = [], later = [], earlier = [];
      api.eventsOn(NOW).forEach(function (e) {
        var item = { kind: 'event', ref: e, start: new Date(e.start), end: new Date(e.end) };
        if (new Date(e.end) <= NOW) earlier.push(item);
        else if (new Date(e.start) <= NOW) current.push(item);
        else later.push(item);
      });
      api.allocationsOn(NOW).forEach(function (t) {
        var item = {
          kind: 'allocation', ref: t, start: new Date(t.allocation.start), end: new Date(t.allocation.end),
          todo: t
        };
        if (new Date(t.allocation.end) <= NOW) earlier.push(item);
        else if (new Date(t.allocation.start) <= NOW) current.push(item);
        else later.push(item);
      });
      var sortFn = function (a, b) { return a.start - b.start; };
      current.sort(sortFn); later.sort(sortFn); earlier.sort(sortFn);
      var plannedIds = api.allocationsOn(NOW).map(function (t) { return t.id; });
      var dueToday = api.dueOn(NOW).filter(function (t) { return plannedIds.indexOf(t.id) < 0; });
      return {
        current: current, later: later, earlier: earlier,
        dueToday: dueToday,
        overdue: api.overdue(),
        unplanned: api.unplanned(),
        completed: state.todos.filter(function (t) {
          return t.done && !t.deleted && t.completedAt && sameDay(t.completedAt, NOW);
        })
      };
    },

    toggleTodo: function (id) {
      var t = byId(state.todos, id);
      if (!t) return;
      t.done = !t.done;
      t.completedAt = t.done ? new Date().toISOString() : null;
      emit();
    },
    upsertTodo: function (draft) {
      if (draft.id) {
        var t = byId(state.todos, draft.id);
        Object.assign(t, draft);
      } else {
        draft.id = uid('td');
        draft.done = !!draft.done;
        draft.deleted = false;
        draft.subtasks = draft.subtasks || [];
        draft.reminders = draft.reminders || [];
        draft.tags = draft.tags || [];
        state.todos.unshift(draft);
      }
      emit();
      return draft.id;
    },
    deleteTodo: function (id) {
      var t = byId(state.todos, id);
      if (t) { t.deleted = true; t.deletedAt = new Date().toISOString(); emit(); }
    },
    restoreTodo: function (id) {
      var t = byId(state.todos, id);
      if (t) { t.deleted = false; t.deletedAt = null; emit(); }
    },
    purgeTodo: function (id) {
      state.todos = state.todos.filter(function (t) { return t.id !== id; });
      emit();
    },
    upsertEvent: function (draft) {
      if (draft.id) {
        Object.assign(byId(state.events, draft.id), draft);
      } else {
        draft.id = uid('e');
        draft.deleted = false;
        draft.reminders = draft.reminders || [];
        state.events.push(draft);
      }
      emit();
      return draft.id;
    },
    deleteEvent: function (id) {
      var e = byId(state.events, id);
      if (e) { e.deleted = true; emit(); }
    },
    addCalendar: function (name, color) {
      var c = { id: uid('c'), name: name, color: color };
      state.calendars.push(c); emit(); return c;
    },
    updateCalendar: function (id, patch) {
      var c = byId(state.calendars, id);
      if (c) { Object.assign(c, patch); emit(); }
    },
    deleteCalendar: function (id) {
      if (state.calendars.length <= 1) return false;
      var fallback = state.calendars.filter(function (c) { return c.id !== id; })[0];
      state.calendars = state.calendars.filter(function (c) { return c.id !== id; });
      state.todos.forEach(function (t) { if (t.calendarId === id) t.calendarId = fallback.id; });
      state.events.forEach(function (e) { if (e.calendarId === id) e.calendarId = fallback.id; });
      emit(); return true;
    },
    addTag: function (name, color) {
      var t = { id: uid('t'), name: name, color: color };
      state.tags.push(t); emit(); return t;
    },
    updateTag: function (id, patch) {
      var t = byId(state.tags, id);
      if (t) { Object.assign(t, patch); emit(); }
    },
    deleteTag: function (id) {
      state.tags = state.tags.filter(function (t) { return t.id !== id; });
      state.todos.forEach(function (t) { t.tags = (t.tags || []).filter(function (x) { return x !== id; }); });
      emit(); return true;
    },
    setSetting: function (k, v) { state.settings[k] = v; emit(); },
    setUi: function (k, v) { state.ui[k] = v; emit(); },

    search: function (q) {
      q = (q || '').trim().toLowerCase();
      if (!q) return { todos: [], events: [] };
      return {
        todos: state.todos.filter(function (t) {
          return !t.deleted && (t.title.toLowerCase().indexOf(q) >= 0 || (t.notes || '').toLowerCase().indexOf(q) >= 0);
        }),
        events: api.activeEvents().filter(function (e) {
          return e.title.toLowerCase().indexOf(q) >= 0 || (e.notes || '').toLowerCase().indexOf(q) >= 0;
        })
      };
    },

    reset: function () { state = seed(); emit(); }
  };

  load();

  // formatting helpers
  var WD = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
  function pad2(n) { return ('0' + n).slice(-2); }
  api.fmt = {
    time: function (d) {
      d = new Date(d);
      var h = d.getHours(), m = pad2(d.getMinutes());
      if (state.settings.timeFormat === '12 小时') {
        var h12 = h % 12 || 12;
        return h12 + ':' + m + (h < 12 ? ' AM' : ' PM');
      }
      return pad2(h) + ':' + m;
    },
    inputTime: function (d) {
      d = new Date(d);
      return pad2(d.getHours()) + ':' + pad2(d.getMinutes());
    },
    hour: function (h) {
      if (state.settings.timeFormat === '12 小时') return (h % 12 || 12) + (h < 12 ? ' AM' : ' PM');
      return pad2(h) + ':00';
    },
    md: function (d) { d = new Date(d); return (d.getMonth() + 1) + '月' + d.getDate() + '日'; },
    weekday: function (d) { return WD[new Date(d).getDay()]; },
    dayLabel: function (d) {
      if (api.sameDay(d, NOW)) return '今天';
      if (api.sameDay(d, addDays(NOW, 1))) return '明天';
      if (api.sameDay(d, addDays(NOW, -1))) return '昨天';
      return api.fmt.md(d);
    },
    range: function (a, b) { return api.fmt.time(a) + '–' + api.fmt.time(b); },
    dateTime: function (d) {
      return api.fmt.md(d) + ' ' + api.fmt.weekday(d) + ' · ' + api.fmt.time(d);
    },
    due: function (t) {
      if (!t.due) return '';
      return t.dueHasTime ? api.fmt.md(t.due) + ' ' + api.fmt.time(t.due) : api.fmt.md(t.due);
    }
  };

  window.DS = api;
})();
