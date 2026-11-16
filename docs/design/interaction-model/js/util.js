/* Small helpers: dates, DOM, formatting. No framework. */
(function () {
  const MS_MIN = 60000;
  const MS_HOUR = 3600000;
  const MS_DAY = 86400000;

  function pad(n) { return String(n).padStart(2, '0'); }
  // Single clock read point. Tests and the "time of day" demo control can pin
  // it so behaviour is reproducible; everything else calls U.now().
  let clockOffsetMs = 0;
  function setClockOffset(ms) { clockOffsetMs = ms; }
  function now() { return new Date(Date.now() + clockOffsetMs); }
  function startOfDay(d) { const x = new Date(d); x.setHours(0, 0, 0, 0); return x; }
  function endOfDay(d) { const x = new Date(d); x.setHours(23, 59, 59, 999); return x; }
  function addDays(d, n) { const x = new Date(d); x.setDate(x.getDate() + n); return x; }
  function addMinutes(d, n) { return new Date(d.getTime() + n * MS_MIN); }
  function sameDay(a, b) { return !!a && !!b && a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate(); }
  function sameMonth(a, b) { return !!a && !!b && a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth(); }
  function startOfWeek(d, weekStartsOn) {
    const x = startOfDay(d);
    const ws = weekStartsOn === undefined ? 1 : weekStartsOn;
    const diff = (x.getDay() - ws + 7) % 7;
    return addDays(x, -diff);
  }
  function startOfMonth(d) { return new Date(d.getFullYear(), d.getMonth(), 1); }
  function endOfMonth(d) { return new Date(d.getFullYear(), d.getMonth() + 1, 0, 23, 59, 59, 999); }
  function minutesBetween(a, b) { return Math.round((b - a) / MS_MIN); }
  function clamp(n, lo, hi) { return Math.max(lo, Math.min(hi, n)); }

  function fmtTime(d) { return d ? `${pad(d.getHours())}:${pad(d.getMinutes())}` : ''; }
  function fmtClockNoMidnight(d) { return d && (d.getHours() || d.getMinutes()) ? fmtTime(d) : ''; }
  function fmtMonthDay(d) { return I18N.t('dateLabel', { m: d.getMonth() + 1, d: d.getDate() }); }
  function fmtMonthDayTime(d) { return I18N.t('dateTimeLabel', { m: d.getMonth() + 1, d: d.getDate(), t: fmtTime(d) }); }
  function fmtWeekdayLong(d) { return I18N.t('weekdaysLong')[d.getDay()]; }
  function fmtWeekdayShort(d) { return I18N.t('weekdaysShort')[d.getDay()]; }
  function fmtMonthYear(d) {
    if (I18N.getLang() === 'zh') return `${d.getFullYear()}年${d.getMonth() + 1}月`;
    return `${I18N.t('monthsShort')[d.getMonth()]} ${d.getFullYear()}`;
  }
  function fmtFullDate(d) {
    if (I18N.getLang() === 'zh') return `${d.getMonth() + 1}月${d.getDate()}日`;
    return `${I18N.t('monthsShort')[d.getMonth()]} ${d.getDate()}`;
  }
  function fmtRelativeDay(d, now) {
    const t0 = startOfDay(now || new Date());
    const diff = Math.round((startOfDay(d) - t0) / MS_DAY);
    if (diff === 0) return I18N.t('today');
    if (diff === 1) return I18N.t('tomorrow');
    if (diff === -1) return I18N.t('yesterday');
    return fmtMonthDay(d);
  }
  function fmtDeadline(d) {
    if (!d) return '';
    const hasTime = d.getHours() || d.getMinutes();
    return hasTime ? fmtMonthDayTime(d) : fmtMonthDay(d);
  }
  function fmtDuration(min) {
    const h = Math.floor(min / 60), m = Math.round(min % 60);
    return { h, m };
  }
  function fmtTimeRange(a, b) { return I18N.t('timeRange', { a: fmtTime(a), b: fmtTime(b) }); }

  function toInputDateTime(d) {
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }
  function toInputDate(d) { return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`; }
  function fromInputDateTime(v) {
    if (!v) return null;
    const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/.exec(v);
    if (!m) return null;
    return new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], 0, 0);
  }
  function fromInputDate(v) {
    if (!v) return null;
    const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(v);
    if (!m) return null;
    return new Date(+m[1], +m[2] - 1, +m[3]);
  }

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  }
  function hl(text, q) {
    if (!q) return esc(text);
    const s = String(text);
    const idx = s.toLowerCase().indexOf(q.toLowerCase());
    if (idx < 0) return esc(s);
    return esc(s.slice(0, idx)) + '<mark>' + esc(s.slice(idx, idx + q.length)) + '</mark>' + esc(s.slice(idx + q.length));
  }
  let seq = 1;
  function uid(prefix) { return `${prefix || 'id'}_${Date.now().toString(36)}_${seq++}`; }
  function el(tag, attrs, html) {
    const node = document.createElement(tag);
    if (attrs) for (const k in attrs) {
      if (k === 'class') node.className = attrs[k];
      else if (k === 'text') node.textContent = attrs[k];
      else if (k === 'html') node.innerHTML = attrs[k];
      else if (k.startsWith('on') && typeof attrs[k] === 'function') node.addEventListener(k.slice(2), attrs[k]);
      else if (attrs[k] !== undefined && attrs[k] !== null) node.setAttribute(k, attrs[k]);
    }
    if (html !== undefined) node.innerHTML = html;
    return node;
  }
  function qs(sel, root) { return (root || document).querySelector(sel); }
  function qsa(sel, root) { return Array.from((root || document).querySelectorAll(sel)); }
  function debounce(fn, ms) {
    let timer = null;
    return function (...args) {
      clearTimeout(timer);
      timer = setTimeout(() => fn.apply(this, args), ms);
    };
  }
  function isNarrow() { return window.innerWidth < 900; }
  // Master-detail is a pane, not a route: at this width the list stays and the
  // detail opens beside it. Mirrors kMasterDetailBreakpoint in the app.
  function isSplit() { return window.innerWidth >= 1180; }

  window.U = {
    MS_MIN, MS_HOUR, MS_DAY, pad, startOfDay, endOfDay, addDays, addMinutes, sameDay, sameMonth,
    startOfWeek, startOfMonth, endOfMonth, minutesBetween, clamp, fmtTime, fmtClockNoMidnight,
    fmtMonthDay, fmtMonthDayTime, fmtWeekdayLong, fmtWeekdayShort, fmtMonthYear, fmtFullDate,
    fmtRelativeDay, fmtDeadline, fmtDuration, fmtTimeRange, toInputDateTime, toInputDate,
    fromInputDateTime, fromInputDate, esc, hl, uid, el, qs, qsa, debounce, isNarrow, isSplit,
    now, setClockOffset,
  };
})();
