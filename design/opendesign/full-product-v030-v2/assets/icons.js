/* One icon family: 24px grid, 1.8 stroke, round caps, outline only. */
(function () {
  var P = {
    today: '<path d="M4 7h16M8 3v4M16 3v4M5 7a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2H5Z"/><path d="M8 12h4M8 16h7"/>',
    calendar: '<rect x="3" y="5" width="18" height="16" rx="2.5"/><path d="M8 3v4M16 3v4M3 10h18"/><path d="M8 14h2M14 14h2M8 17.5h2"/>',
    todo: '<rect x="3.5" y="3.5" width="17" height="17" rx="4"/><path d="m8 12.5 2.6 2.6L16.5 9"/>',
    search: '<circle cx="11" cy="11" r="6.5"/><path d="m16 16 4.5 4.5"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    more: '<circle cx="6" cy="12" r="1.4"/><circle cx="12" cy="12" r="1.4"/><circle cx="18" cy="12" r="1.4"/>',
    tag: '<path d="M4 4h7l9 9-7 7-9-9V4Z"/><circle cx="8.2" cy="8.2" r="1.4"/>',
    trash: '<path d="M4 7h16M9 7V4.5h6V7M6.5 7l1 13h9l1-13M10 11v6M14 11v6"/>',
    back: '<path d="M20 12H4M10 6l-6 6 6 6"/>',
    chevronLeft: '<path d="m14.5 5-7 7 7 7"/>',
    chevronRight: '<path d="m9.5 5 7 7-7 7"/>',
    chevronDown: '<path d="m5 9 7 7 7-7"/>',
    close: '<path d="M6 6l12 12M18 6 6 18"/>',
    clock: '<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>',
    flag: '<path d="M6 21V4M6 4h11l-1.6 3.6L17 11H6"/>',
    bell: '<path d="M6 9a6 6 0 0 1 12 0v4.5l1.8 3H4.2L6 13.5V9Z"/><path d="M9.5 19a2.5 2.5 0 0 0 5 0"/>',
    repeat: '<path d="M4 9a4 4 0 0 1 4-4h9l-2.5-2.5M20 15a4 4 0 0 1-4 4H7l2.5 2.5"/>',
    check: '<path d="m5 12.5 4.2 4.2L19 7"/>',
    settings: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1Z"/>',
    sync: '<path d="M4 11a8 8 0 0 1 13.7-5.6L20 8M20 13a8 8 0 0 1-13.7 5.6L4 16"/><path d="M20 4v4h-4M4 20v-4h4"/>',
    sparkle: '<path d="M12 3.5 13.8 9l5.5 1.8-5.5 1.8L12 18.2l-1.8-5.6L4.7 10.8 10.2 9 12 3.5Z"/><path d="M18.5 16.5 19.2 18.6 21 19.3l-1.8.7-.7 2.1-.7-2.1-1.8-.7 1.8-.7.7-2.1Z"/>',
    file: '<path d="M6 3.5h7.5L19 9v11.5H6z"/><path d="M13.5 3.5V9H19"/>',
    download: '<path d="M12 4v10M8 10.5l4 4 4-4M5 19.5h14"/>',
    upload: '<path d="M12 15V5M8 8.5l4-4 4 4M5 19.5h14"/>',
    moon: '<path d="M20 14.5A8.5 8.5 0 0 1 9.5 4 8.5 8.5 0 1 0 20 14.5Z"/>',
    sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2.5v2M12 19.5v2M2.5 12h2M19.5 12h2M5.2 5.2l1.4 1.4M17.4 17.4l1.4 1.4M18.8 5.2l-1.4 1.4M6.6 17.4l-1.4 1.4"/>',
    list: '<path d="M8 6.5h12M8 12h12M8 17.5h12M4 6.5h.01M4 12h.01M4 17.5h.01"/>',
    grid: '<rect x="3.5" y="3.5" width="7" height="7" rx="1.5"/><rect x="13.5" y="3.5" width="7" height="7" rx="1.5"/><rect x="3.5" y="13.5" width="7" height="7" rx="1.5"/><rect x="13.5" y="13.5" width="7" height="7" rx="1.5"/>',
    edit: '<path d="M4 20h4l10.5-10.5a2.1 2.1 0 0 0-3-3L5 17v3Z"/><path d="m14 6 3 3"/>',
    filter: '<path d="M4 6h16M7 12h10M10 18h4"/>',
    restore: '<path d="M4 10a8 8 0 1 1 2.3 5.7"/><path d="M4 4v6h6"/>',
    location: '<path d="M12 21s6-5.2 6-10a6 6 0 1 0-12 0c0 4.8 6 10 6 10Z"/><circle cx="12" cy="11" r="2.2"/>',
    note: '<path d="M5 4h14v16H5z"/><path d="M8 8.5h8M8 12h8M8 15.5h5"/>',
    tagPlus: '<path d="M4 4h7l8 8-6 6-9-9V4Z"/><path d="M12.5 15.5h5M15 13v5"/>',
    calendarPlus: '<rect x="3" y="5" width="18" height="16" rx="2.5"/><path d="M8 3v4M16 3v4M3 10h18M12 13v6M9 16h6"/>',
    inbox: '<path d="M4 13.5 6.5 5h11L20 13.5V19H4v-5.5Z"/><path d="M4 13.5h4.5l1 2.5h5l1-2.5H20"/>',
    eye: '<path d="M2.5 12S6 6.5 12 6.5 21.5 12 21.5 12 18 17.5 12 17.5 2.5 12 2.5 12Z"/><circle cx="12" cy="12" r="2.6"/>',
    eyeOff: '<path d="M4 4l16 16"/><path d="M9.8 6.9A9.7 9.7 0 0 1 12 6.7c6 0 9.5 5.3 9.5 5.3a17 17 0 0 1-3 3.4M6.4 8.2A17 17 0 0 0 2.5 12s3.5 5.3 9.5 5.3c1 0 2-.2 2.8-.5"/>',
    keyboard: '<rect x="2.5" y="6" width="19" height="12" rx="2"/><path d="M6 10h.01M9.5 10h.01M13 10h.01M16.5 10h.01M6 13.5h.01M8 13.5h8M17.5 13.5h.01"/>'
  };

  window.icon = function (name, size) {
    var body = P[name] || P.todo;
    var s = size || 20;
    return '<svg class="od-icon" style="--od-icon-size:' + s + 'px" viewBox="0 0 24 24" fill="none" ' +
      'stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + body + '</svg>';
  };
})();
