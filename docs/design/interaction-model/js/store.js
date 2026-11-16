/* State, domain rules and derived projections.
   Mirrors SPEC.md: Todo.dueDate is a deadline; TaskAllocation is movable execution
   time; Event occupies time. The three never collapse into one another. */
(function () {
  const U = window.U;

  const TODO_STATUS = { OPEN: 'NEEDS-ACTION', DONE: 'COMPLETED', CANCELLED: 'CANCELLED' };
  const ALLOC = { ACTIVE: 'active', CANCELLED: 'cancelledByUser', INVALIDATED: 'invalidatedByCompletion' };
  const PRIORITY = { none: 0, low: 1, medium: 5, high: 9 };

  const state = {
    lang: 'zh',
    langPref: 'zh',
    theme: 'light',
    accent: 'blue',
    tab: 'action',
    route: { name: 'action', params: {} },
    todosView: { kind: 'day', day: null },
    overdueExpanded: false,
    deadlineExpanded: false,
    hideCompleted: false,
    defaultTab: 'action',
    weekStartsOn: 1,
    showLunar: true,
    calendars: [],
    tags: [],
    todos: [],
    events: [],
    allocations: [],
    reminders: [],
    calendarView: 'week',
    calendarAnchor: null,
    browseDate: null,
    actionDate: null,
    selection: null,
    todoSelection: null,
    // Which record the desktop detail pane is showing. A selection, not a
    // route: it lives only while Todo is the active destination, so arriving
    // from another tab never resurrects a detail the user did not ask for.
    paneSelection: null,
    selectedTagIds: [],
    searchQuery: '',
    account: { signedIn: false, email: null, server: null, lastSync: null, phase: 'idle', rejected: [] },
    ai: { enabled: true, configured: true, provider: 'OpenAI', model: 'gpt-4o-mini', messages: [], pending: false },
    notificationsEnabled: true,
    exactAlarm: true,
    offline: false,
    settingsOpen: {},
    toast: null,
    modal: null,
    menu: null,
    loading: {},
    error: null,
    undoStack: [],
    highlight: null,
    lastCreated: null,
    calendarFocusDay: null,
    settingsSection: 'appearance',
    composer: null,
    history: [],
  };

  let listeners = [];
  function subscribe(fn) { listeners.push(fn); return () => { listeners = listeners.filter((x) => x !== fn); }; }
  let pending = false;
  function emit(reason) {
    if (pending) return;
    pending = true;
    requestAnimationFrame(() => {
      pending = false;
      listeners.forEach((fn) => fn(reason));
    });
  }

  // ---------- seed ----------
  function seed() {
    const today = U.startOfDay(U.now());
    state.actionDate = today;
    state.calendarAnchor = today;
    state.browseDate = today;
    state.todosView = { kind: 'day', day: today };
    state.calendarFocusDay = today;
    const now = U.now();
    const at = (dayOffset, h, m) => {
      const d = U.addDays(today, dayOffset);
      // at(n) with no hour is a whole-day marker; setHours(undefined) would
      // produce an Invalid Date instead of midnight.
      d.setHours(h || 0, m || 0, 0, 0);
      return d;
    };

    state.calendars = [
      { id: 1, name: '个人', color: '#2457d6', timezone: 'Asia/Shanghai' },
      { id: 2, name: '工作', color: '#2f7d5a', timezone: 'Asia/Shanghai' },
      { id: 3, name: '家庭', color: '#c2410c', timezone: 'Asia/Shanghai' },
    ];
    state.tags = [
      { id: 1, name: '工作', color: '#2457d6' },
      { id: 2, name: '家', color: '#2f7d5a' },
      { id: 3, name: '健康', color: '#c2410c' },
      { id: 4, name: '学习', color: '#6d4aa0' },
    ];

    let tid = 1, eid = 1, aid = 1, rid = 1;
    const mkTodo = (o) => {
      const t = {
        id: tid++, calendarId: 1, summary: '', dueDate: null, startDate: null,
        priority: 0, status: TODO_STATUS.OPEN, description: null, completedAt: null,
        createdAt: now, updatedAt: now, deletedAt: null, sortOrder: tid * 10,
        parentId: null, tagIds: [], recurrence: null, occurrenceStates: {},
        attachments: [], reminderOffsets: [],
      };
      Object.assign(t, o);
      state.todos.push(t);
      return t;
    };
    const mkEvent = (o) => {
      const e = {
        id: eid++, calendarId: 1, summary: '', startDt: now, endDt: now,
        isAllDay: false, description: null, location: null, deletedAt: null,
        createdAt: now, updatedAt: now, rrule: null, exdates: [], reminderOffsets: [],
        tagIds: [],
      };
      Object.assign(e, o);
      state.events.push(e);
      return e;
    };
    const mkAlloc = (o) => {
      const a = { id: aid++, todoId: null, occurrenceId: null, startAt: now, endAt: now, state: ALLOC.ACTIVE, createdAt: now, updatedAt: now };
      Object.assign(a, o);
      state.allocations.push(a);
      return a;
    };
    const mkReminder = (o) => {
      const r = { id: rid++, parentType: 'todo', parentId: 0, triggerTime: now, isTriggered: false };
      Object.assign(r, o);
      state.reminders.push(r);
      return r;
    };

    const morning = mkTodo({ summary: '晨间回顾：今天最重要的一件事', priority: PRIORITY.medium, dueDate: at(0, 9), startDate: at(0, 8), tagIds: [1], reminderOffsets: [0] });
    const releaseNotes = mkTodo({ summary: '写 v0.29 发布说明', priority: PRIORITY.high, dueDate: at(0, 18), tagIds: [1] });
    const replyEmail = mkTodo({ summary: '回复客户邮件：北岸项目排期', priority: PRIORITY.high, dueDate: at(0, 15), tagIds: [1] });
    const reviewNotes = mkTodo({ summary: '整理评审纪要', priority: PRIORITY.medium, dueDate: at(0, 16, 30), tagIds: [1] });
    const designPrep = mkTodo({ summary: '设计走查准备：把原型挂到内网', priority: PRIORITY.low, tagIds: [1] });
    const budget = mkTodo({ summary: 'Q4 预算表', priority: PRIORITY.high, dueDate: at(0, 18), tagIds: [1] });
    const dentist = mkTodo({ summary: '预约牙医', priority: PRIORITY.medium, dueDate: at(2, 10), tagIds: [3] });
    const travelClaim = mkTodo({ summary: '差旅报销', priority: PRIORITY.medium, dueDate: at(-2, 12), tagIds: [1] });
    const groceries = mkTodo({ summary: '买牛奶和咖啡豆', priority: PRIORITY.low, dueDate: at(0, 20), tagIds: [2] });
    const reading = mkTodo({
      summary: '读 20 页《设计中的设计》', priority: PRIORITY.low, tagIds: [4],
      recurrence: { freq: 'DAILY', interval: 1, byday: [], until: null, timeZone: 'Asia/Shanghai', anchor: 'due', valueType: 'date' },
      dueDate: at(0, 22), startDate: at(0, 22),
    });
    const standup = mkTodo({
      summary: '每日站会记录', priority: PRIORITY.medium, tagIds: [1],
      recurrence: { freq: 'WEEKLY', interval: 1, byday: [1, 2, 3, 4, 5], until: null, timeZone: 'Asia/Shanghai', anchor: 'due', valueType: 'date' },
      dueDate: at(0, 9, 30), startDate: at(0, 9, 30),
    });
    const weeklyReview = mkTodo({
      summary: '每周复盘', priority: PRIORITY.medium, tagIds: [1],
      recurrence: { freq: 'WEEKLY', interval: 1, byday: [5], until: null, timeZone: 'Asia/Shanghai', anchor: 'due', valueType: 'date' },
      dueDate: at(4, 17),
    });
    const inbox1 = mkTodo({ summary: '查一下 NAS 备份策略', tagIds: [] });
    const inbox2 = mkTodo({ summary: '给团队写一条同步说明', tagIds: [1] });
    const inbox3 = mkTodo({ summary: '换掉厨房的灯泡', tagIds: [2] });
    const done1 = mkTodo({ summary: '提交上周的工时', status: TODO_STATUS.DONE, completedAt: at(0, 10, 20), dueDate: at(0, 12), tagIds: [1] });
    const done2 = mkTodo({ summary: '回复设计评审的三条意见', status: TODO_STATUS.DONE, completedAt: at(0, 11, 5), tagIds: [1] });
    const done3 = mkTodo({ summary: '晨跑 5 公里', status: TODO_STATUS.DONE, completedAt: at(-1, 7, 10), tagIds: [3] });
    const parent = mkTodo({ summary: '准备季度评审', priority: PRIORITY.high, dueDate: at(3, 18), tagIds: [1] });
    const sub1 = mkTodo({ summary: '收集各组数据', parentId: parent.id, priority: PRIORITY.medium, dueDate: at(1, 18), tagIds: [1] });
    const sub2 = mkTodo({ summary: '写一页结论', parentId: parent.id, priority: PRIORITY.medium, tagIds: [1] });
    const deletedTodo = mkTodo({ summary: '旧版发布检查清单', deletedAt: U.addDays(today, -1), tagIds: [1] });

    const lunch = mkEvent({ summary: '与设计师午餐', startDt: at(0, 11, 30), endDt: at(0, 12, 30), calendarId: 2, location: '楼下小馆', tagIds: [1] });
    const clientCall = mkEvent({ summary: '客户电话 · 北岸', startDt: at(0, 12), endDt: at(0, 13), calendarId: 2, location: '线上', tagIds: [1] });
    const designReview = mkEvent({ summary: '设计走查', startDt: at(0, 14), endDt: at(0, 15, 30), calendarId: 2, location: '会议室 A', tagIds: [1], description: '带上 D Final 三张图与移动端截图。' });
    const allDayHoliday = mkEvent({ summary: '国庆假期', startDt: at(2), endDt: at(4, 23, 59), isAllDay: true, calendarId: 3 });
    const standupEvent = mkEvent({
      summary: '周会', startDt: at(1, 10), endDt: at(1, 11), calendarId: 2,
      rrule: { freq: 'WEEKLY', interval: 1, byday: [U.addDays(today, 1).getDay()], until: null }, tagIds: [1],
    });
    const deletedEvent = mkEvent({ summary: '已取消的访谈', startDt: at(-1, 15), endDt: at(-1, 16), deletedAt: U.addDays(today, -1), calendarId: 2 });

    mkAlloc({ todoId: morning.id, startAt: at(0, 8, 30), endAt: at(0, 9) });
    mkAlloc({ todoId: releaseNotes.id, startAt: at(0, 9, 30), endAt: at(0, 10, 30) });
    mkAlloc({ todoId: replyEmail.id, startAt: at(0, 15, 30), endAt: at(0, 16, 10) });
    mkAlloc({ todoId: budget.id, startAt: at(0, 16, 30), endAt: at(0, 17, 30) });
    mkAlloc({ todoId: designPrep.id, startAt: at(0, 17, 30), endAt: at(0, 18, 15) });
    mkAlloc({ todoId: reading.id, occurrenceId: occurrenceIdFor(reading, today), startAt: at(0, 21), endAt: at(0, 21, 40) });
    mkAlloc({ todoId: reviewNotes.id, startAt: at(0, 13, 30), endAt: at(0, 14) });
    mkAlloc({ todoId: travelClaim.id, startAt: at(-1, 9), endAt: at(-1, 10), state: ALLOC.CANCELLED });

    mkReminder({ parentType: 'todo', parentId: morning.id, triggerTime: at(0, 9) });
    mkReminder({ parentType: 'event', parentId: clientCall.id, triggerTime: at(0, 11, 45) });

    state.todos.forEach((t) => { t.sortOrder = t.id * 10; });
    state.loading = {};
    // Seed records are sample text, not user data: they are localized with the
    // rest of the product. A user edit stops matching either variant and is
    // never rewritten.
    state.seedLocale = {
      cal: state.calendars.map((c) => ({ id: c.id, zh: c.name, en: SEED_EN[c.name] || c.name })),
      tag: state.tags.map((g) => ({ id: g.id, zh: g.name, en: SEED_EN[g.name] || g.name })),
      todo: state.todos.map((t) => ({ id: t.id, zh: t.summary, en: SEED_EN[t.summary] || t.summary })),
      event: state.events.map((e) => ({
        id: e.id,
        zh: e.summary,
        en: SEED_EN[e.summary] || e.summary,
        locZh: e.location || null,
        locEn: e.location ? (SEED_EN[e.location] || e.location) : null,
        descZh: e.description || null,
        descEn: e.description ? (SEED_EN[e.description] || e.description) : null,
      })),
    };
    localizeSeed();
  }

  const SEED_EN = {
    '个人': 'Personal', '家庭': 'Family', '家': 'Home', '健康': 'Health', '学习': 'Study', '工作': 'Work',
    '晨间回顾：今天最重要的一件事': 'Morning review: the one thing that matters today',
    '写 v0.29 发布说明': 'Write the v0.29 release notes',
    '回复客户邮件：北岸项目排期': 'Reply to the client: Northshore schedule',
    '整理评审纪要': 'Tidy up the review notes',
    '设计走查准备：把原型挂到内网': 'Design review prep: put the prototype on the intranet',
    'Q4 预算表': 'Q4 budget sheet',
    '预约牙医': 'Book the dentist',
    '差旅报销': 'Travel expense claim',
    '买牛奶和咖啡豆': 'Buy milk and coffee beans',
    '读 20 页《设计中的设计》': 'Read 20 pages of Designing Design',
    '每日站会记录': 'Daily standup notes',
    '每周复盘': 'Weekly retro',
    '查一下 NAS 备份策略': 'Check the NAS backup policy',
    '给团队写一条同步说明': 'Write the team a sync note',
    '换掉厨房的灯泡': 'Replace the kitchen bulb',
    '提交上周的工时': 'Submit last week’s timesheet',
    '回复设计评审的三条意见': 'Answer the three review comments',
    '晨跑 5 公里': 'Morning run, 5 km',
    '准备季度评审': 'Prepare the quarterly review',
    '收集各组数据': 'Collect each team’s numbers',
    '写一页结论': 'Write the one-page conclusion',
    '旧版发布检查清单': 'Old release checklist',
    '与设计师午餐': 'Lunch with the designer',
    '客户电话 · 北岸': 'Client call · Northshore',
    '设计走查': 'Design walkthrough',
    '国庆假期': 'National Day holiday',
    '周会': 'Weekly meeting',
    '已取消的访谈': 'Cancelled interview',
    '楼下小馆': 'Bistro downstairs',
    '线上': 'Online',
    '会议室 A': 'Meeting room A',
    '带上 D Final 三张图与移动端截图。': 'Bring the three D Final frames and the mobile screenshots.',
  };

  function localizeSeed() {
    const map = state.seedLocale;
    if (!map) return;
    const pick = (zh, en) => (state.lang === 'en' ? en : zh);
    map.cal.forEach((p) => {
      const r = state.calendars.find((x) => x.id === p.id);
      if (r && (r.name === p.zh || r.name === p.en)) r.name = pick(p.zh, p.en);
    });
    map.tag.forEach((p) => {
      const r = state.tags.find((x) => x.id === p.id);
      if (r && (r.name === p.zh || r.name === p.en)) r.name = pick(p.zh, p.en);
    });
    map.todo.forEach((p) => {
      const r = state.todos.find((x) => x.id === p.id);
      if (r && (r.summary === p.zh || r.summary === p.en)) r.summary = pick(p.zh, p.en);
    });
    map.event.forEach((p) => {
      const r = state.events.find((x) => x.id === p.id);
      if (!r) return;
      if (r.summary === p.zh || r.summary === p.en) r.summary = pick(p.zh, p.en);
      if (p.locZh && (r.location === p.locZh || r.location === p.locEn)) r.location = pick(p.locZh, p.locEn);
      if (p.descZh && (r.description === p.descZh || r.description === p.descEn)) r.description = pick(p.descZh, p.descEn);
    });
  }

  // ---------- recurrence ----------
  function occurrenceIdFor(todo, date) {
    if (!todo.recurrence) return null;
    const d = U.startOfDay(date);
    if (todo.recurrence.valueType === 'date') {
      return `v2:DATE:${d.getFullYear()}-${U.pad(d.getMonth() + 1)}-${U.pad(d.getDate())}`;
    }
    return `v1:DT:${d.getFullYear()}-${U.pad(d.getMonth() + 1)}-${U.pad(d.getDate())}T00:00:00@${todo.recurrence.timeZone}`;
  }

  function occurrenceDateFromId(id) {
    if (!id) return null;
    const m = /^(?:v2:DATE|v1:DT):(\d{4})-(\d{2})-(\d{2})/.exec(id);
    if (!m) return null;
    return new Date(+m[1], +m[2] - 1, +m[3]);
  }

  function seriesAnchor(todo) {
    const d = todo.startDate || todo.dueDate;
    return d ? U.startOfDay(d) : null;
  }

  function matchesRule(todo, date) {
    const rec = todo.recurrence;
    const anchor = seriesAnchor(todo);
    if (!rec || !anchor) return false;
    const d = U.startOfDay(date);
    if (d < anchor) return false;
    if (rec.until && d > U.endOfDay(rec.until)) return false;
    const days = Math.round((d - anchor) / U.MS_DAY);
    switch (rec.freq) {
      case 'DAILY': {
        if (days % rec.interval !== 0) return false;
        if (rec.byday && rec.byday.length) return rec.byday.includes(d.getDay());
        return true;
      }
      case 'WEEKLY': {
        const weeks = Math.floor(days / 7);
        if (weeks % rec.interval !== 0) return false;
        const dayset = rec.byday && rec.byday.length ? rec.byday : [anchor.getDay()];
        return dayset.includes(d.getDay());
      }
      case 'MONTHLY': {
        const months = (d.getFullYear() - anchor.getFullYear()) * 12 + (d.getMonth() - anchor.getMonth());
        if (months % rec.interval !== 0) return false;
        return d.getDate() === anchor.getDate();
      }
      case 'YEARLY': {
        const years = d.getFullYear() - anchor.getFullYear();
        if (years % rec.interval !== 0) return false;
        return d.getMonth() === anchor.getMonth() && d.getDate() === anchor.getDate();
      }
      default:
        return false;
    }
  }

  function occurrencesInWindow(todo, from, to) {
    if (!todo.recurrence) return [];
    const out = [];
    let d = U.startOfDay(from);
    const end = U.startOfDay(to);
    while (d <= end) {
      if (matchesRule(todo, d)) out.push(d);
      d = U.addDays(d, 1);
    }
    return out;
  }

  function occurrenceState(todo, occId) {
    return todo.occurrenceStates && todo.occurrenceStates[occId] ? todo.occurrenceStates[occId] : null;
  }

  function isOccurrenceDone(todo, occId) {
    const s = occurrenceState(todo, occId);
    return !!(s && s.completedAt);
  }

  // A repeating to-do is never COMPLETED as a series, so "is this row done"
  // has to ask about the occurrence that row stands for. Without this the list
  // kept showing a ticked instance as open and ticking it again silently undid
  // the completion.
  function isOpenOn(todo, day) {
    if (!isOpen(todo)) return false;
    if (!todo.recurrence) return true;
    if (!day || !matchesRule(todo, day)) return true;
    return !isOccurrenceDone(todo, occurrenceIdFor(todo, day));
  }

  // ---------- queries ----------
  function liveTodos() { return state.todos.filter((t) => !t.deletedAt); }
  function liveEvents() { return state.events.filter((e) => !e.deletedAt); }
  function todoById(id) { return state.todos.find((t) => t.id === id) || null; }
  function eventById(id) { return state.events.find((e) => e.id === id) || null; }
  function tagById(id) { return state.tags.find((t) => t.id === id) || null; }
  function calendarById(id) { return state.calendars.find((c) => c.id === id) || null; }
  function calendarColor(id) { const c = calendarById(id); return c ? c.color : 'var(--accent)'; }
  function isOpen(t) { return t.status === TODO_STATUS.OPEN; }
  function isDone(t) { return t.status === TODO_STATUS.DONE; }
  function subtasksOf(id) { return liveTodos().filter((t) => t.parentId === id); }

  function isAllocationLive(a) {
    if (a.state !== ALLOC.ACTIVE) return false;
    const todo = todoById(a.todoId);
    if (!todo || todo.deletedAt) return false;
    if (todo.recurrence) {
      if (a.occurrenceId) return !isOccurrenceDone(todo, a.occurrenceId);
      return false;
    }
    if (todo.status === TODO_STATUS.CANCELLED) return false;
    if (todo.completedAt && a.startAt >= todo.completedAt) return false;
    return true;
  }

  function allocationsForTodo(todoId) {
    return state.allocations.filter((a) => a.todoId === todoId).sort((x, y) => x.startAt - y.startAt);
  }

  function allocationsOnDay(day) {
    const from = U.startOfDay(day), to = U.endOfDay(day);
    return state.allocations
      .filter((a) => isAllocationLive(a) && a.endAt > from && a.startAt <= to)
      .sort((a, b) => a.startAt - b.startAt);
  }

  function eventsOnDay(day) {
    const from = U.startOfDay(day), to = U.endOfDay(day);
    const out = [];
    liveEvents().forEach((e) => {
      if (e.rrule) {
        const spansDays = Math.round((U.startOfDay(e.endDt) - U.startOfDay(e.startDt)) / U.MS_DAY);
        const candidates = [U.startOfDay(day)];
        for (let i = 1; i <= Math.max(0, spansDays); i++) candidates.push(U.addDays(U.startOfDay(day), -i));
        const seen = new Set();
        candidates.forEach((anchorDay) => {
          const occStart = new Date(anchorDay);
          occStart.setHours(e.startDt.getHours(), e.startDt.getMinutes(), 0, 0);
          const occEnd = new Date(occStart.getTime() + (e.endDt - e.startDt));
          if (!matchesEventRule(e, anchorDay)) return;
          if (e.exdates.some((x) => U.sameDay(x, anchorDay))) return;
          if (occEnd <= from || occStart > to) return;
          const key = occStart.getTime();
          if (seen.has(key)) return;
          seen.add(key);
          out.push(cloneEventOccurrence(e, occStart, occEnd, anchorDay));
        });
      } else if (e.endDt > from && e.startDt <= to) {
        out.push(e);
      }
    });
    return out.sort((a, b) => a.startDt - b.startDt);
  }

  function matchesEventRule(e, anchorDay) {
    const r = e.rrule;
    const base = U.startOfDay(e.startDt);
    if (anchorDay < base) return false;
    if (r.until && anchorDay > U.endOfDay(r.until)) return false;
    const days = Math.round((anchorDay - base) / U.MS_DAY);
    if (r.freq === 'DAILY') return days % r.interval === 0;
    if (r.freq === 'WEEKLY') {
      const weeks = Math.floor(days / 7);
      if (weeks % r.interval !== 0) return false;
      const set = r.byday && r.byday.length ? r.byday : [base.getDay()];
      return set.includes(anchorDay.getDay());
    }
    if (r.freq === 'MONTHLY') {
      const months = (anchorDay.getFullYear() - base.getFullYear()) * 12 + (anchorDay.getMonth() - base.getMonth());
      return months % r.interval === 0 && anchorDay.getDate() === base.getDate();
    }
    if (r.freq === 'YEARLY') {
      const years = anchorDay.getFullYear() - base.getFullYear();
      return years % r.interval === 0 && anchorDay.getMonth() === base.getMonth() && anchorDay.getDate() === base.getDate();
    }
    return false;
  }

  function cloneEventOccurrence(e, start, end, anchorDay) {
    return Object.assign({}, e, {
      startDt: start, endDt: end, occurrenceAnchor: anchorDay, isOccurrence: true,
    });
  }

  // Action projection (SPEC rule 16/18)
  function actionProjection(day) {
    const now = U.now();
    const d = U.startOfDay(day || state.actionDate || now);
    const isToday = U.sameDay(d, now);
    const events = eventsOnDay(d);
    // A to-do completed before a scheduled slot ends makes that slot history, not
    // current work: the same rule isAllocationLive applies to the calendar.
    const allocs = allocationsOnDay(d).filter((a) => isAllocationLive(a));
    const live = liveTodos();

    const dueTodayTodos = live.filter((t) => {
      if (t.recurrence || t.parentId) return false;
      if (!isOpen(t) || !t.dueDate) return false;
      return U.sameDay(t.dueDate, d) && !(isToday && t.dueDate < now && !U.sameDay(t.dueDate, now));
    }).filter((t) => U.sameDay(t.dueDate, d));

    const overdueTodos = live.filter((t) => {
      if (t.recurrence || t.parentId || !isOpen(t) || !t.dueDate) return false;
      const dueDay = U.startOfDay(t.dueDate);
      if (isToday) return dueDay < d;
      return dueDay < d;
    });

    const missedFrom = U.addDays(d, -30);
    const todayTaskInstances = [];
    const missedTaskInstances = [];
    const completedTodayTaskInstances = [];
    live.filter((t) => t.recurrence && !t.parentId).forEach((t) => {
      occurrencesInWindow(t, U.addDays(d, -30), d).forEach((occDay) => {
        const occId = occurrenceIdFor(t, occDay);
        const st = occurrenceState(t, occId);
        if (U.sameDay(occDay, d)) {
          if (st && st.completedAt) completedTodayTaskInstances.push({ todo: t, occurrenceId: occId, day: occDay, completedAt: st.completedAt });
          else todayTaskInstances.push({ todo: t, occurrenceId: occId, day: occDay });
        } else if (occDay < d && occDay >= missedFrom) {
          if (st && st.completedAt) {
            // A missed instance completed today is work finished today: it
            // belongs in 今天完成 with its own undo, not silently nowhere.
            if (U.sameDay(st.completedAt, d)) {
              completedTodayTaskInstances.push({ todo: t, occurrenceId: occId, day: occDay, completedAt: st.completedAt });
            }
          } else {
            missedTaskInstances.push({ todo: t, occurrenceId: occId, day: occDay });
          }
        }
      });
    });

    const completedTodayTodos = live.filter((t) => !t.parentId && isDone(t) && t.completedAt && U.sameDay(t.completedAt, d));

    const inboxCount = inboxTodos().length;

    return {
      day: d, events, allocations: allocs.map((a) => ({ allocation: a, todo: todoById(a.todoId) })).filter((x) => x.todo),
      dueTodayTodos, overdueTodos, todayTaskInstances, missedTaskInstances,
      completedTodayTodos, completedTodayTaskInstances, inboxCount, now,
    };
  }

  function pendingTodos() {
    return liveTodos().filter((t) => isOpen(t) && !t.parentId);
  }

  function completedTodos() {
    // A subtask is part of its parent, never a row in a top-level list: the
    // inventories, 未安排 and every Today section take parents only.
    return liveTodos().filter((t) => isDone(t) && !t.parentId);
  }

  function todosForDay(day) {
    const d = U.startOfDay(day);
    const now = U.now();
    const today = U.startOfDay(now);
    const pending = pendingTodos();
    const overdue = [];
    const dated = [];
    const doneInstances = [];
    pending.forEach((t) => {
      if (t.recurrence) {
        // A repeating to-do appears on a day through its occurrence, and that
        // occurrence's own completion state decides whether it is still open.
        if (!matchesRule(t, d)) return;
        const occ = occurrenceIdFor(t, d);
        if (isOccurrenceDone(t, occ)) {
          doneInstances.push({ todo: t, occurrenceId: occ });
          return;
        }
        dated.push(t);
        return;
      }
      if (!t.dueDate) return;
      const due = U.startOfDay(t.dueDate);
      if (due < today && U.sameDay(d, today)) overdue.push(t);
      else if (U.sameDay(due, d)) dated.push(t);
    });
    const done = completedTodos().filter((t) => t.completedAt && U.sameDay(t.completedAt, d));
    return {
      overdue,
      dated: dated.sort((a, b) => a.sortOrder - b.sortOrder),
      done,
      doneInstances,
    };
  }

  function plannedTodoIds() {
    const ids = new Set();
    state.allocations.forEach((a) => { if (isAllocationLive(a)) ids.add(a.todoId); });
    return ids;
  }

  function inboxTodos() {
    const planned = plannedTodoIds();
    return pendingTodos()
      .filter((t) => !planned.has(t.id))
      .sort((a, b) => a.sortOrder - b.sortOrder);
  }

  function schedulableTodos() {
    return liveTodos().filter((t) => isOpen(t)).sort((a, b) => a.sortOrder - b.sortOrder);
  }

  function searchAll(q) {
    const needle = q.trim().toLowerCase();
    if (!needle) return { todos: [], events: [] };
    const todos = liveTodos().filter((t) =>
      t.summary.toLowerCase().includes(needle) || (t.description || '').toLowerCase().includes(needle));
    const events = liveEvents().filter((e) =>
      e.summary.toLowerCase().includes(needle) || (e.description || '').toLowerCase().includes(needle) || (e.location || '').toLowerCase().includes(needle));
    return { todos, events };
  }

  // ---------- mutations ----------
  function touch(t) { t.updatedAt = U.now(); }

  function createTodo(input) {
    const now = U.now();
    const t = {
      id: Math.max(0, ...state.todos.map((x) => x.id)) + 1,
      calendarId: input.calendarId || state.calendars[0].id,
      summary: (input.summary || '').trim(),
      dueDate: input.dueDate || null,
      startDate: input.startDate || null,
      priority: input.priority || 0,
      status: TODO_STATUS.OPEN,
      description: input.description || null,
      completedAt: null,
      createdAt: now, updatedAt: now, deletedAt: null,
      sortOrder: Math.max(0, ...state.todos.map((x) => x.sortOrder || 0)) + 10,
      parentId: input.parentId || null,
      tagIds: input.tagIds ? input.tagIds.slice() : [],
      recurrence: input.recurrence || null,
      occurrenceStates: {},
      attachments: input.attachments || [],
      reminderOffsets: input.reminderOffsets || [],
    };
    state.todos.push(t);
    state.lastCreated = { type: 'todo', id: t.id };
    emit('todo:create');
    return t;
  }

  function updateTodo(id, patch) {
    const t = todoById(id);
    if (!t) return null;
    Object.assign(t, patch);
    touch(t);
    emit('todo:update');
    return t;
  }

  function createEvent(input) {
    const now = U.now();
    const e = {
      id: Math.max(0, ...state.events.map((x) => x.id)) + 1,
      calendarId: input.calendarId || state.calendars[0].id,
      summary: (input.summary || '').trim(),
      startDt: input.startDt || now,
      endDt: input.endDt || U.addMinutes(input.startDt || now, 60),
      isAllDay: !!input.isAllDay,
      description: input.description || null,
      location: input.location || null,
      deletedAt: null, createdAt: now, updatedAt: now,
      rrule: input.rrule || null, exdates: [], reminderOffsets: input.reminderOffsets || [],
      tagIds: input.tagIds || [],
      splitFrom: input.splitFrom || null, splitAnchor: input.splitAnchor || null,
    };
    state.events.push(e);
    state.lastCreated = { type: 'event', id: e.id };
    emit('event:create');
    return e;
  }

  // Editing one occurrence of a series: exclude that anchor from the series and
  // write a standalone event carrying the edits. Undo merges it back.
  function splitEventOccurrence(id, anchorMs, patch) {
    const series = eventById(id);
    if (!series || !series.rrule) return null;
    const anchor = U.startOfDay(new Date(anchorMs));
    const occStart = new Date(anchorMs);
    const occEnd = new Date(occStart.getTime() + (series.endDt - series.startDt));
    series.exdates = series.exdates || [];
    // Splitting the same occurrence twice must not mint a second copy or push
    // the anchor twice: the second edit belongs to the copy the first one made.
    const existing = state.events.find(
      (e) => !e.deletedAt && e.splitFrom === series.id && e.splitAnchor === anchor.getTime(),
    );
    if (!series.exdates.some((d) => d.getTime() === anchor.getTime())) {
      series.exdates.push(anchor);
    }
    let copy;
    if (existing) {
      Object.assign(existing, patch || {});
      existing.updatedAt = U.now();
      copy = existing;
    } else {
      copy = createEvent(Object.assign({
        summary: series.summary, calendarId: series.calendarId,
        startDt: occStart, endDt: occEnd, isAllDay: series.isAllDay,
        description: series.description, location: series.location, tagIds: (series.tagIds || []).slice(),
        reminderOffsets: (series.reminderOffsets || []).slice(),
        splitFrom: series.id, splitAnchor: anchor.getTime(),
      }, patch || {}));
    }
    emit('event:update');
    return { series, copy, updated: !!existing };
  }

  // "This and following": the old series stops the day before the chosen
  // occurrence, and the record continues from that day with the edited values.
  // Weekday is re-derived from the new day; the end date and reminders carry.
  function splitEventFuture(id, occurrenceMs, patch) {
    const e = eventById(id);
    if (!e || !e.rrule) return null;
    const occStart = new Date(occurrenceMs);
    const duration = e.endDt - e.startDt;
    const oldUntil = e.rrule.until || null;
    e.rrule = Object.assign({}, e.rrule, { until: U.addDays(U.startOfDay(occStart), -1) });
    Object.assign(e, patch || {});
    e.startDt = occStart;
    e.endDt = new Date(occStart.getTime() + duration);
    if (!(patch && patch.rrule)) {
      e.rrule = oldUntil ? Object.assign({}, e.rrule, { until: oldUntil }) : e.rrule;
    }
    if (e.rrule && e.rrule.freq === 'WEEKLY') {
      e.rrule = Object.assign({}, e.rrule, { byday: [occStart.getDay()] });
    }
    e.updatedAt = U.now();
    emit('event:update');
    return e;
  }

  function updateEvent(id, patch) {
    const e = eventById(id);
    if (!e) return null;
    Object.assign(e, patch);
    e.updatedAt = U.now();
    emit('event:update');
    return e;
  }

  function createAllocation(input) {
    const now = U.now();
    let startAt = input.startAt;
    let endAt = input.endAt;
    // An occurrence is a claim about one day. A slot on another day is moved
    // onto the occurrence's day at the same clock time, so a block can never
    // be bound to an instance that does not own its date.
    if (input.occurrenceId) {
      const occDay = occurrenceDateFromId(input.occurrenceId);
      if (occDay && !U.sameDay(occDay, startAt)) {
        const delta = Math.round((U.startOfDay(occDay) - U.startOfDay(startAt)) / U.MS_DAY);
        startAt = U.addDays(startAt, delta);
        endAt = U.addDays(endAt, delta);
      }
    }
    const a = {
      id: Math.max(0, ...state.allocations.map((x) => x.id)) + 1,
      todoId: input.todoId, occurrenceId: input.occurrenceId || null,
      startAt, endAt, state: ALLOC.ACTIVE,
      createdAt: now, updatedAt: now,
    };
    state.allocations.push(a);
    emit('allocation:create');
    return a;
  }

  function rescheduleAllocation(id, startAt, endAt) {
    const a = state.allocations.find((x) => x.id === id);
    if (!a) return null;
    const todo = todoById(a.todoId);
    if (a.occurrenceId) {
      const occDay = occurrenceDateFromId(a.occurrenceId);
      if (!occDay || !U.sameDay(occDay, startAt)) {
        // A cross-day move rebinds the block to the new day's occurrence; a
        // day the series never reaches cannot own the block at all.
        if (!todo || !todo.recurrence || !matchesRule(todo, startAt)) return null;
        a.occurrenceId = occurrenceIdFor(todo, startAt);
      }
    } else if (todo && todo.recurrence) {
      if (!matchesRule(todo, startAt)) return null;
      a.occurrenceId = occurrenceIdFor(todo, startAt);
    }
    a.startAt = startAt;
    a.endAt = endAt;
    a.updatedAt = U.now();
    emit('allocation:update');
    return a;
  }

  function cancelAllocation(id) {
    const a = state.allocations.find((x) => x.id === id);
    if (!a) return null;
    a.state = ALLOC.CANCELLED;
    a.updatedAt = U.now();
    emit('allocation:cancel');
    return a;
  }

  function completeTodo(id, opts) {
    const t = todoById(id);
    if (!t) return null;
    const occId = opts && opts.occurrenceId;
    if (t.recurrence) {
      if (!occId) return null;
      const now = U.now();
      const prev = t.occurrenceStates[occId];
      if (prev && prev.completedAt) {
        const wasAt = prev.completedAt;
        delete t.occurrenceStates[occId];
        // Undo has to give back what completion took. Otherwise the to-do
        // reopens but its reserved block stays gone from Today and Calendar,
        // and nothing in the UI ever says where it went.
        state.allocations.forEach((a) => {
          if (a.todoId === t.id && a.occurrenceId === occId
              && a.state === ALLOC.INVALIDATED && a.startAt >= wasAt) {
            a.state = ALLOC.ACTIVE;
          }
        });
        emit('todo:uncomplete');
        return t;
      }
      t.occurrenceStates[occId] = { completedAt: now };
      state.allocations.forEach((a) => {
        if (a.todoId === t.id && a.occurrenceId === occId && a.state === ALLOC.ACTIVE && a.startAt >= now) {
          a.state = ALLOC.INVALIDATED;
        }
      });
      touch(t);
      emit('todo:complete');
      return t;
    }
    if (isDone(t)) {
      const wasAt = t.completedAt;
      t.status = TODO_STATUS.OPEN;
      t.completedAt = null;
      t.percentComplete = 0;
      state.allocations.forEach((a) => {
        if (a.todoId === t.id && a.state === ALLOC.INVALIDATED && wasAt && a.startAt >= wasAt) {
          a.state = ALLOC.ACTIVE;
        }
      });
      touch(t);
      emit('todo:uncomplete');
      return t;
    }
    const now = U.now();
    t.status = TODO_STATUS.DONE;
    t.completedAt = now;
    t.percentComplete = 100;
    state.allocations.forEach((a) => {
      if (a.todoId === t.id && a.state === ALLOC.ACTIVE && a.startAt >= now) a.state = ALLOC.INVALIDATED;
    });
    touch(t);
    emit('todo:complete');
    return t;
  }

  function softDeleteTodo(id) {
    const t = todoById(id);
    if (!t) return null;
    // Re-deleting an already trashed row would move its timestamp, breaking the
    // stamp match that lets undo restore a parent together with its subtasks.
    if (t.deletedAt) return t;
    t.deletedAt = U.now();
    subtasksOf(id).forEach((s) => { s.deletedAt = t.deletedAt; });
    dropPaneIfGone();
    touch(t);
    emit('todo:delete');
    return t;
  }

  function softDeleteEvent(id) {
    const e = eventById(id);
    if (!e) return null;
    e.deletedAt = U.now();
    e.updatedAt = U.now();
    dropPaneIfGone();
    emit('event:delete');
    return e;
  }

  function restoreTodo(id) {
    const t = todoById(id);
    if (!t) return null;
    if (t.parentId != null) {
      const p = todoById(t.parentId);
      // A subtask whose parent was purged has nowhere to live: restoring it would
      // clear deletedAt while parentId still points at a removed row, so it would
      // never appear in any list again. Refuse instead of reporting a false restore.
      if (!p) return null;
      // A subtask cascaded into Trash with its parent cannot come back alone: it
      // would sit under a still-deleted parent and never be reachable. Bring the
      // parent back instead, which restores the whole cascade.
      if (p.deletedAt) {
        if (p.deletedAt !== t.deletedAt) return null;
        if (!restoreTodo(p.id)) return null;
      }
    }
    const stamp = t.deletedAt;
    t.deletedAt = null;
    touch(t);
    // Deleting a parent takes its subtasks with it, so undo has to bring them
    // back too. Only children deleted at that same moment belong to this undo;
    // ones the user deleted separately keep their own place in Trash.
    if (stamp) {
      state.todos
        .filter((x) => x.parentId === id && x.deletedAt === stamp)
        .forEach((s) => { s.deletedAt = null; touch(s); });
    }
    emit('todo:restore');
    return t;
  }

  function restoreEvent(id) {
    const e = eventById(id);
    if (!e) return null;
    e.deletedAt = null;
    e.updatedAt = U.now();
    emit('event:restore');
    return e;
  }

  function purgeTodo(id) {
    const t = todoById(id);
    if (!t) return null;
    if (state.paneSelection && state.paneSelection.type === 'todo' && Number(state.paneSelection.id) === Number(id)) state.paneSelection = null;
    // Purging a parent purges its subtasks too. Leaving them behind stranded
    // rows in Trash that could never be restored (their parent is gone).
    // subtasksOf only sees live rows, and a soft-deleted parent's children are
    // already deleted, so this must scan the whole table.
    state.todos.filter((x) => x.parentId === id).forEach((s) => { purgeTodo(s.id); });
    state.allocations = state.allocations.filter((a) => a.todoId !== id);
    state.todos = state.todos.filter((x) => x.id !== id);
    emit('todo:purge');
    return t;
  }

  function purgeEvent(id) {
    const e = eventById(id);
    if (!e) return null;
    if (state.paneSelection && state.paneSelection.type === 'event' && Number(state.paneSelection.id) === Number(id)) state.paneSelection = null;
    state.events = state.events.filter((x) => x.id !== id);
    emit('event:purge');
    return e;
  }

  function emptyTrash() {
    state.paneSelection = null;
    const ids = state.todos.filter((t) => t.deletedAt).map((t) => t.id);
    const eids = state.events.filter((e) => e.deletedAt).map((e) => e.id);
    ids.forEach(purgeTodo);
    eids.forEach(purgeEvent);
    emit('trash:empty');
    return { todos: ids.length, events: eids.length };
  }

  function deletedTodos() { return state.todos.filter((t) => t.deletedAt).sort((a, b) => b.deletedAt - a.deletedAt); }
  function deletedEvents() { return state.events.filter((e) => e.deletedAt).sort((a, b) => b.deletedAt - a.deletedAt); }

  function reorderTodos(ids) {
    // Renumber the given rows into the slots they already occupy. A reorder in
    // a filtered/day view then cannot push rows the user cannot see.
    const given = new Set(ids);
    const slots = state.todos.filter((t) => given.has(t.id)).map((t) => t.sortOrder).sort((a, b) => a - b);
    ids.forEach((id, i) => {
      const t = todoById(id);
      if (t && slots[i] !== undefined) t.sortOrder = slots[i];
    });
    emit('todo:reorder');
  }

  function createTag(name, color) {
    const t = { id: Math.max(0, ...state.tags.map((x) => x.id)) + 1, name: name.trim(), color: color || '#6b7280' };
    state.tags.push(t);
    emit('tag:create');
    return t;
  }
  function updateTag(id, patch) {
    const t = tagById(id);
    if (!t) return null;
    Object.assign(t, patch);
    emit('tag:update');
    return t;
  }
  function deleteTag(id) {
    state.tags = state.tags.filter((t) => t.id !== id);
    state.todos.forEach((t) => { t.tagIds = t.tagIds.filter((x) => x !== id); });
    state.events.forEach((e) => { e.tagIds = (e.tagIds || []).filter((x) => x !== id); });
    state.selectedTagIds = state.selectedTagIds.filter((x) => x !== id);
    emit('tag:delete');
  }

  function createCalendar(name, color) {
    const c = { id: Math.max(0, ...state.calendars.map((x) => x.id)) + 1, name: name.trim(), color: color || '#2457d6', timezone: 'Asia/Shanghai' };
    state.calendars.push(c);
    emit('calendar:create');
    return c;
  }
  function updateCalendar(id, patch) {
    const c = calendarById(id);
    if (!c) return null;
    Object.assign(c, patch);
    emit('calendar:update');
    return c;
  }
  function deleteCalendar(id, opts) {
    if (state.calendars.length <= 1) return { ok: false, reason: 'only' };
    const target = state.calendars.find((c) => c.id !== id);
    const move = opts && opts.move;
    if (move) {
      state.todos.forEach((t) => { if (t.calendarId === id) t.calendarId = target.id; });
      state.events.forEach((e) => { if (e.calendarId === id) e.calendarId = target.id; });
    } else {
      // Deleting a calendar with its contents is a soft delete: the records
      // move to 回收站 where they can be restored, as they can in the app.
      // Permanent deletion exists only inside Trash (INV-148).
      state.todos.filter((t) => t.calendarId === id).forEach((t) => softDeleteTodo(t.id));
      state.events.filter((e) => e.calendarId === id).forEach((e) => softDeleteEvent(e.id));
    }
    state.calendars = state.calendars.filter((c) => c.id !== id);
    // A filter that names the deleted calendar would hide every remaining row
    // and read as "nothing left" rather than "that calendar is gone".
    if (state.filterCalendarId === id) state.filterCalendarId = null;
    emit('calendar:delete');
    return { ok: true };
  }

  // ---------- settings ----------
  function setSetting(key, value) {
    state[key] = value;
    emit('setting:' + key);
  }

  function setLang(lang) {
    state.langPref = lang === 'system' ? 'system' : lang;
    state.lang = lang === 'system' ? (String(navigator.language || 'zh').toLowerCase().startsWith('zh') ? 'zh' : 'en') : lang;
    I18N.setLang(state.lang);
    // Sample records are part of what the user reads: they follow the language
    // switch with everything else.
    localizeSeed();
    savePrefs();
    emit('lang');
  }

  function applyTheme() {
    // "System" is resolved only when painting: the preference stays "system"
    // so a later OS change follows without rewriting the setting.
    let theme = state.theme;
    if (theme === 'system') {
      theme = (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) ? 'dark' : 'light';
    }
    document.documentElement.dataset.theme = theme;
    document.documentElement.dataset.accent = state.accent;
  }

  // Preferences that outlive a reload. "Opens on" is only meaningful if it
  // survives one, so the few settings that are launch or shell choices persist;
  // nothing else does, because the prototype's data is in memory only.
  const PREFS_KEY = 'dayspark.g0.prefs';
  const PREF_KEYS = ['lang', 'langPref', 'theme', 'accent', 'defaultTab', 'showLunar', 'hideCompleted', 'weekStartsOn', 'notificationsEnabled', 'exactAlarm'];
  function savePrefs() {
    try {
      const out = {};
      PREF_KEYS.forEach((k) => { out[k] = state[k]; });
      localStorage.setItem(PREFS_KEY, JSON.stringify(out));
    } catch (_) { /* storage may be blocked */ }
  }
  function loadPrefs() {
    try {
      const raw = localStorage.getItem(PREFS_KEY);
      if (!raw) return;
      const saved = JSON.parse(raw);
      PREF_KEYS.forEach((k) => { if (saved[k] !== undefined) state[k] = saved[k]; });
      // "Follow system" is a live preference, not the language that happened to
      // be resolved in the old session: re-resolve it on every boot.
      if (state.langPref === 'system') {
        state.lang = String(navigator.language || 'zh').toLowerCase().startsWith('zh') ? 'zh' : 'en';
      }
    } catch (_) { /* ignore a corrupt or blocked store */ }
  }

  // ---------- undo ----------
  function pushUndo(entry) {
    state.undoStack.push(entry);
    if (state.undoStack.length > 30) state.undoStack.shift();
  }
  function takeUndo() { return state.undoStack.pop() || null; }

  // ---------- history (in-app navigation) ----------
  function navigate(name, params, opts) {
    if (!opts || !opts.replace) state.history.push({ name: state.route.name, params: state.route.params });
    // Public section keys are stable; the view's internal keys are not.
    if (name === 'settings' && params && params.section) {
      const alias = { sync: 'account', ai: 'advanced', general: 'appearance', notifications: 'notifications' };
      state.settingsSection = alias[params.section] || params.section;
    }
    // The pane belongs to the Todo list. Any other destination (including a
    // tool such as Search or Settings) retires it — except the composer, which
    // is where editing the selected record happens; cancelling must come back
    // to the same pane.
    if (name !== 'todos' && name !== 'composer') state.paneSelection = null;
    state.route = { name, params: params || {} };
    state.menu = null;
    if (window.UI) { window.UI.closeAll(); window.UI.closeMenu(); window.UI.hideToast(); }
    emit('navigate');
  }
  function back() {
    const prev = state.history.pop();
    if (!prev) {
      // 今天 is the root of the ladder: standing on it, Back has nothing to do.
      if (state.route.name === 'action') return;
      state.route = { name: 'action', params: {} };
      state.tab = 'action';
      if (window.UI) { window.UI.closeAll(); window.UI.closeMenu(); window.UI.hideToast(); }
      emit('navigate');
      return;
    }
    state.route = prev;
    if (window.UI) { window.UI.closeAll(); window.UI.closeMenu(); window.UI.hideToast(); }
    emit('navigate');
  }

  // ---------- browse date ----------
  // CORE_UX_SPEC 16.1: Todo · 按日期 and the Calendar share one browsed date.
  // Today is not part of this: it always reads the clock, so it can never be
  // dragged off to some other day by browsing.
  function browseDate() {
    return state.browseDate ? new Date(state.browseDate.getTime()) : U.startOfDay(U.now());
  }
  function setBrowseDate(d) {
    state.browseDate = U.startOfDay(d);
    // A day-browsing Todo list follows it, or the two surfaces would disagree
    // about which day "the" browsed day is.
    if (state.todosView && state.todosView.kind === 'day') {
      state.todosView = { kind: 'day', day: state.browseDate };
    }
    emit('browse');
  }

  // ---------- detail pane selection ----------
  // Setting it never pushes history: the pane is not a place you can go back
  // to, it is what the current list has selected.
  function selectPane(type, id, occurrence, day) {
    state.paneSelection = { type, id, occurrence: occurrence || null, day: day || null };
    emit('select');
  }
  function clearPane() {
    if (!state.paneSelection) return;
    state.paneSelection = null;
    emit('select');
  }
  // A pane may only show a record that still exists and is not in the trash.
  function dropPaneIfGone() {
    const sel = state.paneSelection;
    if (!sel) return;
    const rec = sel.type === 'event' ? eventById(sel.id) : todoById(sel.id);
    if (!rec || rec.deletedAt) state.paneSelection = null;
  }

  window.Store = {
    state, subscribe, emit, seed, occurrenceIdFor, occurrenceDateFromId, occurrencesInWindow, occurrenceState,
    isOccurrenceDone, isOpenOn, matchesRule, liveTodos, liveEvents, todoById, eventById, tagById, calendarById,
    calendarColor, isOpen, isDone, subtasksOf, isAllocationLive, allocationsForTodo, allocationsOnDay,
    splitEventOccurrence, splitEventFuture, eventsOnDay, actionProjection, pendingTodos, completedTodos, todosForDay, inboxTodos, schedulableTodos, plannedTodoIds,
    searchAll, createTodo, updateTodo, createEvent, updateEvent, createAllocation, rescheduleAllocation,
    cancelAllocation, completeTodo, softDeleteTodo, softDeleteEvent, restoreTodo, restoreEvent, purgeTodo,
    purgeEvent, emptyTrash, deletedTodos, deletedEvents, reorderTodos, createTag, updateTag, deleteTag,
    createCalendar, updateCalendar, deleteCalendar, setSetting, setLang, localizeSeed, applyTheme, savePrefs, loadPrefs, pushUndo, takeUndo,
    navigate, back, selectPane, clearPane, browseDate, setBrowseDate, TODO_STATUS, ALLOC, PRIORITY,
  };
})();
