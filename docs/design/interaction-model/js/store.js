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
    theme: 'light',
    accent: 'blue',
    tab: 'action',
    route: { name: 'action', params: {} },
    todosView: { kind: 'day', day: null },
    sixThings: false,
    overdueExpanded: false,
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
    actionDate: null,
    selection: null,
    todoSelection: null,
    selectedTagIds: [],
    searchQuery: '',
    account: { signedIn: false, email: null, server: null, lastSync: null, phase: 'idle', rejected: [] },
    ai: { configured: true, provider: 'OpenAI', model: 'gpt-4o-mini', messages: [], pending: false },
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
    state.todosView = { kind: 'day', day: today };
    state.calendarFocusDay = today;
    const now = U.now();
    const at = (dayOffset, h, m) => {
      const d = U.addDays(today, dayOffset);
      d.setHours(h, m || 0, 0, 0);
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
    const allocs = allocationsOnDay(d);
    const live = liveTodos();

    const dueTodayTodos = live.filter((t) => {
      if (t.recurrence) return false;
      if (!isOpen(t) || !t.dueDate) return false;
      return U.sameDay(t.dueDate, d) && !(isToday && t.dueDate < now && !U.sameDay(t.dueDate, now));
    }).filter((t) => U.sameDay(t.dueDate, d));

    const overdueTodos = live.filter((t) => {
      if (t.recurrence || !isOpen(t) || !t.dueDate) return false;
      const dueDay = U.startOfDay(t.dueDate);
      if (isToday) return dueDay < d;
      return dueDay < d;
    });

    const missedFrom = U.addDays(d, -30);
    const todayTaskInstances = [];
    const missedTaskInstances = [];
    const completedTodayTaskInstances = [];
    live.filter((t) => t.recurrence).forEach((t) => {
      occurrencesInWindow(t, U.addDays(d, -30), d).forEach((occDay) => {
        const occId = occurrenceIdFor(t, occDay);
        const st = occurrenceState(t, occId);
        if (U.sameDay(occDay, d)) {
          if (st && st.completedAt) completedTodayTaskInstances.push({ todo: t, occurrenceId: occId, day: occDay, completedAt: st.completedAt });
          else todayTaskInstances.push({ todo: t, occurrenceId: occId, day: occDay });
        } else if (occDay < d && occDay >= missedFrom) {
          if (!st || !st.completedAt) missedTaskInstances.push({ todo: t, occurrenceId: occId, day: occDay });
        }
      });
    });

    const completedTodayTodos = live.filter((t) => isDone(t) && t.completedAt && U.sameDay(t.completedAt, d));

    const inboxCount = live.filter((t) => isOpen(t) && !t.dueDate && !t.parentId && !t.recurrence).length;

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
    return liveTodos().filter((t) => isDone(t));
  }

  function todosForDay(day) {
    const d = U.startOfDay(day);
    const now = U.now();
    const today = U.startOfDay(now);
    const pending = pendingTodos();
    const overdue = [];
    const dated = [];
    pending.forEach((t) => {
      if (!t.dueDate || t.recurrence) return;
      const due = U.startOfDay(t.dueDate);
      if (due < today && U.sameDay(d, today)) overdue.push(t);
      else if (U.sameDay(due, d)) dated.push(t);
    });
    const done = completedTodos().filter((t) => t.completedAt && U.sameDay(t.completedAt, d));
    return { overdue, dated: dated.sort((a, b) => a.sortOrder - b.sortOrder), done };
  }

  function inboxTodos() {
    return pendingTodos().filter((t) => !t.dueDate && !t.recurrence).sort((a, b) => a.sortOrder - b.sortOrder);
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
    };
    state.events.push(e);
    state.lastCreated = { type: 'event', id: e.id };
    emit('event:create');
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
    const a = {
      id: Math.max(0, ...state.allocations.map((x) => x.id)) + 1,
      todoId: input.todoId, occurrenceId: input.occurrenceId || null,
      startAt: input.startAt, endAt: input.endAt, state: ALLOC.ACTIVE,
      createdAt: now, updatedAt: now,
    };
    state.allocations.push(a);
    emit('allocation:create');
    return a;
  }

  function rescheduleAllocation(id, startAt, endAt) {
    const a = state.allocations.find((x) => x.id === id);
    if (!a) return null;
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
        delete t.occurrenceStates[occId];
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
      t.status = TODO_STATUS.OPEN;
      t.completedAt = null;
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
    t.deletedAt = U.now();
    subtasksOf(id).forEach((s) => { s.deletedAt = t.deletedAt; });
    touch(t);
    emit('todo:delete');
    return t;
  }

  function softDeleteEvent(id) {
    const e = eventById(id);
    if (!e) return null;
    e.deletedAt = U.now();
    e.updatedAt = U.now();
    emit('event:delete');
    return e;
  }

  function restoreTodo(id) {
    const t = todoById(id);
    if (!t) return null;
    t.deletedAt = null;
    touch(t);
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
    state.allocations = state.allocations.filter((a) => a.todoId !== id);
    state.todos = state.todos.filter((x) => x.id !== id);
    emit('todo:purge');
    return t;
  }

  function purgeEvent(id) {
    const e = eventById(id);
    if (!e) return null;
    state.events = state.events.filter((x) => x.id !== id);
    emit('event:purge');
    return e;
  }

  function emptyTrash() {
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
    ids.forEach((id, i) => {
      const t = todoById(id);
      if (t) t.sortOrder = (i + 1) * 10;
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
      state.todos.filter((t) => t.calendarId === id).forEach((t) => purgeTodo(t.id));
      state.events.filter((e) => e.calendarId === id).forEach((e) => purgeEvent(e.id));
    }
    state.calendars = state.calendars.filter((c) => c.id !== id);
    emit('calendar:delete');
    return { ok: true };
  }

  // ---------- settings ----------
  function setSetting(key, value) {
    state[key] = value;
    emit('setting:' + key);
  }

  function setLang(lang) {
    state.lang = lang;
    I18N.setLang(lang);
    emit('lang');
  }

  function applyTheme() {
    document.documentElement.dataset.theme = state.theme;
    document.documentElement.dataset.accent = state.accent;
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
    state.route = { name, params: params || {} };
    state.menu = null;
    if (window.UI) { window.UI.closeAll(); window.UI.closeMenu(); window.UI.hideToast(); }
    emit('navigate');
  }
  function back() {
    const prev = state.history.pop();
    if (!prev) { state.route = { name: 'action', params: {} }; emit('navigate'); return; }
    state.route = prev;
    if (window.UI) { window.UI.closeAll(); window.UI.closeMenu(); window.UI.hideToast(); }
    emit('navigate');
  }

  window.Store = {
    state, subscribe, emit, seed, occurrenceIdFor, occurrenceDateFromId, occurrencesInWindow, occurrenceState,
    isOccurrenceDone, matchesRule, liveTodos, liveEvents, todoById, eventById, tagById, calendarById,
    calendarColor, isOpen, isDone, subtasksOf, isAllocationLive, allocationsForTodo, allocationsOnDay,
    eventsOnDay, actionProjection, pendingTodos, completedTodos, todosForDay, inboxTodos, schedulableTodos,
    searchAll, createTodo, updateTodo, createEvent, updateEvent, createAllocation, rescheduleAllocation,
    cancelAllocation, completeTodo, softDeleteTodo, softDeleteEvent, restoreTodo, restoreEvent, purgeTodo,
    purgeEvent, emptyTrash, deletedTodos, deletedEvents, reorderTodos, createTag, updateTag, deleteTag,
    createCalendar, updateCalendar, deleteCalendar, setSetting, setLang, applyTheme, pushUndo, takeUndo,
    navigate, back, TODO_STATUS, ALLOC, PRIORITY,
  };
})();
