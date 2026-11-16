/* Quick add parser.
   One line in, one record out. The rule mirrors v0.34.0: a clock time makes an
   Event, a date without a time becomes a Todo deadline, and no date at all is
   an undated Todo. Nothing is invented to fill a gap. */
(function () {
  const U = window.U;

  const DIGITS = { 零: 0, 一: 1, 二: 2, 两: 2, 三: 3, 四: 4, 五: 5, 六: 6, 七: 7, 八: 8, 九: 9 };
  const WEEKDAYS = { 日: 0, 天: 0, 一: 1, 二: 2, 三: 3, 四: 4, 五: 5, 六: 6 };

  function cnNumber(raw) {
    const s = raw.trim();
    if (!s) return null;
    if (/^\d+$/.test(s)) return parseInt(s, 10);
    if (s === '十') return 10;
    if (s === '半') return 0.5;
    const m = s.match(/^([一二两三四五六七八九])?十([一二三四五六七八九])?$/);
    if (m) return (m[1] ? DIGITS[m[1]] : 1) * 10 + (m[2] ? DIGITS[m[2]] : 0);
    let n = 0;
    for (const ch of s) {
      if (DIGITS[ch] === undefined) return null;
      n = n * 10 + DIGITS[ch];
    }
    return n;
  }

  function dayAt(base, days) {
    return new Date(base.getFullYear(), base.getMonth(), base.getDate() + days);
  }

  function parse(text, now) {
    const source = String(text || '');
    const base = now ? new Date(now.getTime()) : U.now();
    let rest = source;
    let date = null;
    let hours = null;
    let minutes = 0;
    let durationMin = null;
    let sawTime = false;
    let sawDate = false;

    function cut(fragment) {
      if (!fragment) return;
      const at = rest.indexOf(fragment);
      if (at >= 0) rest = rest.slice(0, at) + ' ' + rest.slice(at + fragment.length);
    }

    // Duration first: "1小时" must not be read as the start time 1 o'clock.
    const durHour = rest.match(/(\d+|[一二两三四五六七八九十])\s*个?\s*半?\s*小时/);
    if (durHour) {
      durationMin = Math.round((cnNumber(durHour[1]) || 1) * 60);
      if (/半/.test(durHour[0])) durationMin += 30;
      cut(durHour[0]);
    } else {
      const durMin = rest.match(/(\d+|[一二两三四五六七八九十])\s*分钟/);
      if (durMin) {
        durationMin = cnNumber(durMin[1]) || 0;
        cut(durMin[0]);
      } else if (/半小时/.test(rest)) {
        durationMin = 30;
        cut('半小时');
      }
    }

    // Date words.
    const dayWords = [['大后天', 3], ['后天', 2], ['明天', 1], ['今天', 0], ['今日', 0]];
    for (const [word, offset] of dayWords) {
      if (rest.includes(word)) {
        date = dayAt(base, offset);
        sawDate = true;
        cut(word);
        break;
      }
    }

    if (!date) {
      const weekday = rest.match(/(下周|下星期|本周|这周|这星期|周|星期)([一二三四五六日天])/);
      if (weekday) {
        const target = WEEKDAYS[weekday[2]];
        const today = base.getDay();
        const delta = /下周|下星期/.test(weekday[1])
          ? 7 - today + target
          : (target - today + 7) % 7;
        date = dayAt(base, delta);
        sawDate = true;
        cut(weekday[0]);
      }
    }

    if (!date) {
      const md = rest.match(/(\d{1,2})\s*月\s*(\d{1,2})\s*[日号]?/);
      if (md) {
        const month = parseInt(md[1], 10) - 1;
        const day = parseInt(md[2], 10);
        let year = base.getFullYear();
        const candidate = new Date(year, month, day);
        if (candidate < U.startOfDay(base)) year += 1;
        date = new Date(year, month, day);
        sawDate = true;
        cut(md[0]);
      }
    }

    // Clock time. A qualifier moves a 12-hour reading into the right half of
    // the day; without one the number is taken literally.
    const clock = rest.match(/(上午|早上|早晨|中午|下午|傍晚|晚上|夜里)?\s*(\d{1,2}|[一二两三四五六七八九十]{1,3})\s*(?:点|时|:)\s*(半|[0-5]?\d\s*分?)?/);
    if (clock) {
      let h = cnNumber(clock[2]);
      let m = clock[3] ? (clock[3] === '半' ? 30 : parseInt(clock[3], 10)) : 0;
      if (h !== null && h >= 0 && h <= 24 && m >= 0 && m < 60) {
        const period = clock[1] || '';
        if (/下午|傍晚|晚上|夜里/.test(period) && h < 12) h += 12;
        if (/中午/.test(period) && h < 11) h = 12;
        if (/上午|早上|早晨/.test(period) && h === 12) h = 0;
        if (h === 24) h = 0;
        hours = h;
        minutes = m;
        sawTime = true;
        cut(clock[0]);
      }
    }

    let start = null;
    if (sawDate || sawTime) {
      const d = date || U.startOfDay(base);
      if (sawTime) {
        start = new Date(d.getFullYear(), d.getMonth(), d.getDate(), hours, minutes);
        // "今天下午3点" said at 16:00 is a past instant, not a plan. Roll it to
        // the next day instead of writing something the calendar cannot show.
        if (!sawDate && start.getTime() <= base.getTime()) {
          start = new Date(start.getTime() + 24 * 60 * 60 * 1000);
        }
      } else {
        start = new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0);
      }
    }

    const title = rest.replace(/\s+/g, ' ').replace(/^[\s,，。.、;；:：-]+|[\s,，。.、;；:：-]+$/g, '').trim();

    if (sawTime) {
      const end = U.addMinutes(start, durationMin || 60);
      return {
        kind: 'event', title: title || source.trim(), start, end,
        sawDate, sawTime, durationMin: durationMin || 60,
      };
    }
    return {
      kind: 'todo', title: title || source.trim(),
      dueDate: sawDate ? new Date(start.getFullYear(), start.getMonth(), start.getDate(), 0, 0) : null,
      sawDate, sawTime: false,
    };
  }

  window.QuickParse = { parse, cnNumber };
})();
