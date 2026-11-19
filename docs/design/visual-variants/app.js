(function () {
  'use strict';

  var DS = window.DS;
  var root = document.documentElement;
  var isPhone = function () { return root.getAttribute('data-platform') === 'phone'; };

  function pad(n) { return n < 10 ? '0' + n : String(n); }

  function minutes(hhmm) {
    var p = hhmm.split(':');
    return parseInt(p[0], 10) * 60 + parseInt(p[1], 10);
  }

  function duration(start, end) {
    return minutes(end) - minutes(start);
  }

  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text !== undefined && text !== null) n.textContent = text;
    return n;
  }

  function icon(id, cls) {
    var svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('class', 'icon' + (cls ? ' ' + cls : ''));
    svg.setAttribute('aria-hidden', 'true');
    var use = document.createElementNS('http://www.w3.org/2000/svg', 'use');
    use.setAttribute('href', '#' + id);
    svg.appendChild(use);
    return svg;
  }

  function catName(cat) {
    return DS.categories[cat] ? DS.categories[cat].label : '';
  }

  function catDot(cat) {
    var d = el('span', 'cat-dot');
    d.setAttribute('data-cat', cat);
    return d;
  }

  function catLabel(cat) {
    var w = el('span', 'cat-label');
    w.appendChild(catDot(cat));
    w.appendChild(el('span', 'cat-text', catName(cat)));
    return w;
  }

  var nowMin = DS.now.minutes;

  function eventRow(ev, live) {
    var row = el('div', 'row row-event');
    row.setAttribute('data-cat', ev.cat);
    row.setAttribute('data-id', ev.id);
    if (live) row.setAttribute('data-live', 'true');

    var time = el('div', 'row-time');
    time.appendChild(el('span', 't-start', ev.start));
    time.appendChild(el('span', 't-end', ev.end));
    row.appendChild(time);

    var body = el('div', 'row-body');
    var title = el('div', 'row-title');
    title.appendChild(el('span', 'row-title-text', ev.title));
    if (ev.place) title.appendChild(el('span', 'row-sub', '· ' + ev.place));
    body.appendChild(title);

    var meta = el('div', 'row-meta');
    meta.appendChild(catLabel(ev.cat));
    body.appendChild(meta);
    row.appendChild(body);

    var tail = el('div', 'row-tail');
    if (live) {
      tail.appendChild(el('span', 'tag tag-live', '进行中'));
    } else {
      tail.appendChild(el('span', 'tag', duration(ev.start, ev.end) + ' 分钟'));
    }
    row.appendChild(tail);
    return row;
  }

  function todoFeedRow(todo) {
    var row = el('div', 'row row-todo');
    row.setAttribute('data-cat', todo.cat);
    row.setAttribute('data-id', todo.id);

    var time = el('div', 'row-time');
    if (todo.status === 'overdue') {
      time.appendChild(el('span', 't-start', todo.dueShort));
      time.appendChild(el('span', 't-end is-overdue', '逾期'));
    } else {
      time.appendChild(el('span', 't-start', todo.dueShort));
      time.appendChild(el('span', 't-end', '截止'));
    }
    row.appendChild(time);

    row.appendChild(el('span', 'checkbox'));

    var body = el('div', 'row-body');
    body.appendChild(el('div', 'row-title', todo.title));
    var meta = el('div', 'row-meta');
    if (todo.planned) {
      meta.appendChild(el('span', 'meta-text', '计划 ' + todo.planned.start + '–' + todo.planned.end));
      meta.appendChild(el('span', 'meta-sep', '·'));
    }
    meta.appendChild(catLabel(todo.cat));
    body.appendChild(meta);
    row.appendChild(body);
    row.appendChild(el('div', 'row-tail'));
    return row;
  }

  function groupBlock(title, meta, rows, key) {
    var g = el('div', 'group group-' + key);
    var head = el('div', 'group-head');
    head.appendChild(el('span', 'group-title', title));
    if (meta) head.appendChild(el('span', 'group-meta', meta));
    head.appendChild(el('span', 'group-spacer'));
    head.appendChild(el('span', 'group-count', String(rows.length)));
    g.appendChild(head);
    var list = el('div', 'group-rows');
    rows.forEach(function (r) { list.appendChild(r); });
    g.appendChild(list);
    return g;
  }

  function renderToday() {
    var feed = document.getElementById('today-feed');
    feed.textContent = '';

    var live = [];
    var next = [];
    DS.events.forEach(function (ev) {
      if (ev.start <= DS.now.label && minutes(ev.end) > nowMin) live.push(ev);
      else if (minutes(ev.start) > nowMin) next.push(ev);
    });

    var dueToday = DS.todos.filter(function (t) { return t.status === 'today'; });
    var overdue = DS.todos.filter(function (t) { return t.status === 'overdue'; });

    feed.appendChild(groupBlock('现在', DS.now.label, live.map(function (e) { return eventRow(e, true); }), 'now'));
    feed.appendChild(groupBlock('接下来', '', next.map(function (e) { return eventRow(e, false); }), 'next'));
    feed.appendChild(groupBlock('今天截止', '', dueToday.map(todoFeedRow), 'due'));
    feed.appendChild(groupBlock('已逾期', '', overdue.map(todoFeedRow), 'overdue'));

    var side = document.getElementById('uns-list');
    side.textContent = '';
    DS.todos.filter(function (t) { return !t.planned; }).forEach(function (t) {
      var item = el('a', 'side-item' + (t.done ? ' is-done' : ''));
      item.href = '#todo';
      item.setAttribute('data-id', t.id);
      item.setAttribute('data-cat', t.cat);
      item.appendChild(catDot(t.cat));
      item.appendChild(el('span', 'side-item-title', t.title));
      item.appendChild(el('span', 'side-item-meta', t.status === 'overdue' ? t.dueShort : ''));
      side.appendChild(item);
    });
  }

  function renderTodo(filter) {
    var list = document.getElementById('todo-list');
    list.textContent = '';

    var rows = DS.todos.slice();
    if (filter === 'unscheduled') rows = rows.filter(function (t) { return !t.planned && !t.done; });

    if (filter === 'date') {
      var buckets = [
        { key: 'today', label: '今天' },
        { key: 'upcoming', label: '稍后' },
        { key: 'none', label: '无日期' },
        { key: 'done', label: '已完成' },
      ];
      var order = [];
      rows.forEach(function (t) {
        var k = t.done ? 'done' : t.status;
        if (!order.some(function (o) { return o.key === k; })) order.push({ key: k });
        var b = buckets.filter(function (x) { return x.key === k; })[0];
        t._bucket = b ? b.label : '稍后';
      });
      var current = null;
      rows.forEach(function (t) {
        if (t._bucket !== current) {
          current = t._bucket;
          list.appendChild(el('div', 'list-group-label', current));
        }
        list.appendChild(todoRow(t));
      });
    } else {
      rows.forEach(function (t) { list.appendChild(todoRow(t)); });
    }

    document.getElementById('todo-count').textContent = String(rows.length);
    var active = document.querySelector('.chip.is-active');
    Array.prototype.forEach.call(document.querySelectorAll('.chip'), function (c) {
      var on = c === active;
      c.setAttribute('aria-selected', on ? 'true' : 'false');
    });
  }

  function todoRow(t) {
    var row = el('button', 'todo-row' + (t.done ? ' is-done' : ''));
    row.type = 'button';
    row.setAttribute('data-id', t.id);
    row.setAttribute('data-cat', t.cat);

    var box = el('span', 'checkbox');
    if (t.done) box.appendChild(icon('i-check', 'check-icon'));
    row.appendChild(box);
    row.appendChild(el('span', 'todo-title', t.title));

    var meta = el('span', 'todo-meta');
    if (t.dueLabel) {
      meta.appendChild(el('span', 'due' + (t.status === 'overdue' ? ' is-overdue' : ''), t.dueLabel));
    } else {
      meta.appendChild(el('span', 'due is-none', '—'));
    }
    row.appendChild(meta);

    var cat = el('span', 'todo-cat');
    cat.appendChild(catDot(t.cat));
    cat.appendChild(el('span', 'cat-text', catName(t.cat)));
    row.appendChild(cat);

    row.addEventListener('click', function () {
      renderDetail(t.id);
      if (isPhone()) root.setAttribute('data-view', 'detail');
    });
    return row;
  }

  function renderDetail(id) {
    var pane = document.getElementById('todo-detail');
    var t = DS.todos.filter(function (x) { return x.id === id; })[0] || DS.todos[0];
    pane.textContent = '';

    var head = el('div', 'detail-head');
    var back = el('button', 'detail-back');
    back.type = 'button';
    back.setAttribute('aria-label', '返回列表');
    back.appendChild(icon('i-back'));
    back.appendChild(el('span', 'detail-back-text', '待办'));
    back.addEventListener('click', function () { root.setAttribute('data-view', 'list'); });
    head.appendChild(back);
    var kicker = el('div', 'detail-kicker');
    kicker.appendChild(catDot(t.cat));
    kicker.appendChild(el('span', 'kicker-text', catName(t.cat)));
    head.appendChild(kicker);
    pane.appendChild(head);

    pane.appendChild(el('h2', 'detail-title', t.title));

    var toggle = el('button', 'detail-toggle' + (t.done ? ' is-done' : ''));
    toggle.type = 'button';
    var box = el('span', 'checkbox');
    if (t.done) box.appendChild(icon('i-check', 'check-icon'));
    toggle.appendChild(box);
    toggle.appendChild(el('span', 'detail-toggle-text', t.done ? '已完成' : '标记完成'));
    pane.appendChild(toggle);

    var fields = el('dl', 'detail-fields');
    function field(label, valueEl) {
      var row = el('div', 'field');
      row.appendChild(el('dt', '', label));
      var dd = el('dd');
      if (typeof valueEl === 'string') dd.textContent = valueEl;
      else dd.appendChild(valueEl);
      row.appendChild(dd);
      fields.appendChild(row);
    }

    field('截止', t.due ? t.dueLabel : '无日期');
    field('计划', t.planned ? '今天 ' + t.planned.start + '–' + t.planned.end : '未安排');
    field('类别', catLabel(t.cat));
    field('重复', '不重复');
    field('提醒', '提前 30 分钟');
    pane.appendChild(fields);

    var notes = el('div', 'detail-notes');
    notes.appendChild(el('div', 'notes-label', '备注'));
    notes.appendChild(el('div', 'notes-empty', '添加备注…'));
    pane.appendChild(notes);
  }

  function renderCalendar() {
    var grid = document.getElementById('cal-grid');
    grid.textContent = '';
    var phone = isPhone();
    var cfg = phone
      ? { start: 480, end: 1200, hourH: 51, days: DS.calendar.phoneDays }
      : { start: 480, end: 1260, hourH: 48, days: DS.calendar.days };
    var dayCount = cfg.days.length;

    grid.style.setProperty('--days', String(dayCount));
    grid.style.setProperty('--hour-h', cfg.hourH + 'px');
    grid.style.setProperty('--body-h', ((cfg.end - cfg.start) / 60 * cfg.hourH) + 'px');

    document.getElementById('cal-range').textContent = phone ? DS.date.weekShort : DS.date.week;

    var head = el('div', 'cal-head');
    head.appendChild(el('div', 'cal-corner'));
    cfg.days.forEach(function (d) {
      var cell = el('div', 'cal-daycell' + (d.iso === DS.date.iso ? ' is-today' : ''));
      cell.appendChild(el('span', 'wd', d.weekday));
      cell.appendChild(el('span', 'num', String(d.num)));
      head.appendChild(cell);
    });
    grid.appendChild(head);

    var lane = el('div', 'cal-lane');
    lane.appendChild(el('div', 'cal-lane-label', '截止'));
    cfg.days.forEach(function (d) {
      var cell = el('div', 'cal-lane-cell');
      DS.todos.forEach(function (t) {
        if (t.done || !t.due) return;
        if (t.due.slice(0, 10) !== d.iso) return;
        var chip = el('span', 'due-chip' + (t.status === 'overdue' ? ' is-overdue' : ''));
        chip.setAttribute('data-cat', t.cat);
        chip.appendChild(el('span', 'due-chip-title', t.title));
        var clock = t.due.indexOf('T') > -1 ? t.due.split('T')[1] : '';
        chip.appendChild(el('span', 'due-chip-time', clock && clock !== '00:00' ? clock : t.dueShort));
        cell.appendChild(chip);
      });
      lane.appendChild(cell);
    });
    grid.appendChild(lane);

    var body = el('div', 'cal-body');
    var hours = el('div', 'cal-hours');
    for (var h = cfg.start / 60; h < cfg.end / 60; h++) {
      var slot = el('div', 'cal-hour');
      slot.appendChild(el('span', '', pad(h) + ':00'));
      hours.appendChild(slot);
    }
    body.appendChild(hours);

    var cols = el('div', 'cal-cols');
    cfg.days.forEach(function (d) {
      var col = el('div', 'cal-col' + (d.iso === DS.date.iso ? ' is-today' : ''));
      col.setAttribute('data-date', d.iso);
      var blocks = [];

      if (d.iso === DS.date.iso) {
        DS.events.forEach(function (ev) {
          blocks.push({
            start: minutes(ev.start),
            end: minutes(ev.end),
            cat: ev.cat,
            title: ev.title,
            time: ev.start + ' – ' + ev.end,
            startLabel: ev.start,
            planned: false,
          });
        });
      }
      DS.todos.forEach(function (t) {
        if (!t.planned) return;
        if (t.due.slice(0, 10) !== d.iso) return;
        blocks.push({
          start: minutes(t.planned.start),
          end: minutes(t.planned.end),
          cat: t.cat,
          title: t.title,
          time: '计划 · ' + t.planned.start + ' – ' + t.planned.end,
          startLabel: t.planned.start,
          planned: true,
        });
      });

      blocks.sort(function (a, b) { return a.start - b.start || b.end - a.end; });

      var clusters = [];
      blocks.forEach(function (b) {
        var c = clusters[clusters.length - 1];
        if (!c || b.start >= c.end) {
          c = { end: b.end, items: [] };
          clusters.push(c);
        }
        c.items.push(b);
        if (b.end > c.end) c.end = b.end;
      });

      clusters.forEach(function (c) {
        var laneEnds = [];
        c.items.forEach(function (b) {
          var ln = 0;
          while (ln < laneEnds.length && laneEnds[ln] > b.start) ln++;
          b.lane = ln;
          laneEnds[ln] = b.end;
        });
        var laneCount = laneEnds.length;
        c.items.forEach(function (b) {
          b.lanes = laneCount;
        });
      });

      blocks.forEach(function (b) {
        var top = (b.start - cfg.start) / 60 * cfg.hourH;
        var height = (b.end - b.start) / 60 * cfg.hourH;
        var leftPct = (b.lane / b.lanes) * 100;
        var widthPct = 100 / b.lanes;

        var node = el('div', 'cal-event' + (b.planned ? ' is-planned' : '') + (height < 34 ? ' is-short' : '') + (b.lanes > 1 ? ' is-narrow' : ''));
        node.setAttribute('data-cat', b.cat);
        node.style.top = top + 'px';
        node.style.height = Math.max(height, 22) + 'px';
        node.style.left = 'calc(' + leftPct + '% + 3px)';
        node.style.width = 'calc(' + widthPct + '% - 6px)';
        var timeText = b.lanes > 1 ? (b.planned ? '计划' : b.startLabel) : b.time;
        node.appendChild(el('div', 'cal-event-title', b.title));
        node.appendChild(el('div', 'cal-event-time', timeText));
        col.appendChild(node);
      });

      cols.appendChild(col);
    });

    var nowTop = (nowMin - cfg.start) / 60 * cfg.hourH;
    if (nowMin >= cfg.start && nowMin <= cfg.end) {
      var nowLine = el('div', 'cal-now');
      nowLine.style.top = nowTop + 'px';
      cols.appendChild(nowLine);
    }

    body.appendChild(cols);
    grid.appendChild(body);
  }

  function setScreen(name) {
    root.setAttribute('data-screen', name);
    root.setAttribute('data-view', 'list');
    Array.prototype.forEach.call(document.querySelectorAll('[data-nav]'), function (n) {
      var on = n.getAttribute('data-nav') === name;
      n.classList.toggle('is-active', on);
      if (on) n.setAttribute('aria-current', 'page');
      else n.removeAttribute('aria-current');
    });
  }

  document.addEventListener('click', function (e) {
    var nav = e.target.closest('[data-nav]');
    if (nav) {
      e.preventDefault();
      setScreen(nav.getAttribute('data-nav'));
      return;
    }
    var side = e.target.closest('.side-item');
    if (side) {
      e.preventDefault();
      setScreen('todo');
      renderDetail(side.getAttribute('data-id'));
      if (isPhone()) root.setAttribute('data-view', 'detail');
    }
  });

  Array.prototype.forEach.call(document.querySelectorAll('.chip'), function (chip) {
    chip.addEventListener('click', function () {
      Array.prototype.forEach.call(document.querySelectorAll('.chip'), function (c) {
        c.classList.toggle('is-active', c === chip);
        c.setAttribute('aria-selected', c === chip ? 'true' : 'false');
      });
      renderTodo(chip.getAttribute('data-filter'));
    });
  });

  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') root.setAttribute('data-view', 'list');
  });

  renderToday();
  renderTodo('all');
  renderDetail('t1');
  renderCalendar();
  setScreen(root.getAttribute('data-screen') || 'today');

  requestAnimationFrame(function () {
    requestAnimationFrame(function () {
      document.body.classList.add('is-ready');
      window.__READY__ = true;
    });
  });
})();
