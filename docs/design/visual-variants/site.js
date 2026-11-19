(function () {
  'use strict';

  function qs(name, fallback) {
    var v = new URLSearchParams(location.search).get(name);
    return v || fallback;
  }

  function mountFrame(wrap, src, width, height, options) {
    var opts = options || {};
    wrap.textContent = '';
    var iframe = document.createElement('iframe');
    iframe.src = src;
    iframe.title = opts.title || 'DaySpark preview';
    iframe.style.width = width + 'px';
    iframe.style.height = height + 'px';
    iframe.style.transformOrigin = 'top left';
    iframe.setAttribute('loading', 'eager');
    wrap.appendChild(iframe);

    var fixedWidth = opts.width || null;
    function fit() {
      var box = fixedWidth || wrap.clientWidth || wrap.parentElement.clientWidth;
      if (!box) return;
      var maxHeight = typeof opts.maxHeight === 'function' ? opts.maxHeight() : opts.maxHeight;
      var scale = Math.min(box / width, opts.maxScale || 1);
      if (maxHeight) scale = Math.min(scale, maxHeight / height);
      iframe.style.transform = 'scale(' + scale + ')';
      if (opts.shrink) wrap.style.width = (Math.ceil(width * scale) + 2) + 'px';
      wrap.style.height = (Math.ceil(height * scale) + 2) + 'px';
    }
    fit();
    if (window.ResizeObserver) {
      var ro = new ResizeObserver(fit);
      ro.observe(wrap);
    }
    window.addEventListener('resize', fit);
    return iframe;
  }

  function segments(root, onChange) {
    var buttons = Array.prototype.slice.call(root.querySelectorAll('button'));
    function select(value, silent) {
      buttons.forEach(function (b) {
        b.classList.toggle('is-active', b.getAttribute('data-value') === value);
        b.setAttribute('aria-pressed', b.getAttribute('data-value') === value ? 'true' : 'false');
      });
      if (!silent) onChange(value);
    }
    buttons.forEach(function (b) {
      b.addEventListener('click', function () { select(b.getAttribute('data-value')); });
    });
    return {
      select: select,
      value: function () {
        var active = buttons.filter(function (b) { return b.classList.contains('is-active'); })[0];
        return active ? active.getAttribute('data-value') : null;
      },
    };
  }

  function ready(frame) {
    return frame && frame.contentWindow && frame.contentWindow.__READY__ === true;
  }

  function waitReady(frame) {
    return new Promise(function (resolve) {
      if (ready(frame)) return resolve();
      var t = setInterval(function () {
        if (ready(frame)) { clearInterval(t); resolve(); }
      }, 60);
      setTimeout(function () { clearInterval(t); resolve(); }, 6000);
    });
  }

  window.Site = { qs: qs, mountFrame: mountFrame, segments: segments, waitReady: waitReady };
})();
