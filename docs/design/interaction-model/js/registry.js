/* View registry. Loaded before the view files so they can register themselves. */
(function () {
  const VIEWS = {};
  const App = {
    defineView(name, fn) { VIEWS[name] = fn; },
    getView(name) { return VIEWS[name]; },
    names() { return Object.keys(VIEWS); },
  };
  window.App = App;
})();
