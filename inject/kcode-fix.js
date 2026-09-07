// KCode — bottom-scroll flicker workaround.
// Kimi's web UI sometimes auto-scrolls to bottom with smooth behavior while
// the compositor is already pinned there. Force every scrollTo/scrollBy call
// to use instant behavior so there is no intermediate repaint fight.
(function () {
  'use strict';

  function normalizeScrollArg(arg) {
    if (arg && typeof arg === 'object') {
      if (arg.behavior === 'smooth') {
        arg.behavior = 'auto';
      }
    }
    return arg;
  }

  const origWindowScrollTo = window.scrollTo;
  window.scrollTo = function (...args) {
    if (args.length === 1) args[0] = normalizeScrollArg(args[0]);
    return origWindowScrollTo.apply(this, args);
  };

  const origWindowScrollBy = window.scrollBy;
  window.scrollBy = function (...args) {
    if (args.length === 1) args[0] = normalizeScrollArg(args[0]);
    return origWindowScrollBy.apply(this, args);
  };

  if (window.Element && Element.prototype.scrollTo) {
    const origElScrollTo = Element.prototype.scrollTo;
    Element.prototype.scrollTo = function (...args) {
      if (args.length === 1) args[0] = normalizeScrollArg(args[0]);
      return origElScrollTo.apply(this, args);
    };
  }

  if (window.Element && Element.prototype.scrollBy) {
    const origElScrollBy = Element.prototype.scrollBy;
    Element.prototype.scrollBy = function (...args) {
      if (args.length === 1) args[0] = normalizeScrollArg(args[0]);
      return origElScrollBy.apply(this, args);
    };
  }
})();
