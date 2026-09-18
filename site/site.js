// MANA LINE public site — progressive-enhancement scripts only.
//
// Every page must work with this file absent or failing: it upgrades markup
// that already renders correctly without it. Nothing here is required to
// read the content of any page.

(function () {
  'use strict';

  /* --- Video carousel (site/videos.html) ---------------------------------
     Without this script #video-list is a plain <ol>: every slide visible,
     in order, readable top to bottom. This turns it into a one-slide-at-a-
     -time carousel — driven by visible buttons, arrow keys, or a swipe,
     never by itself. */

  function initVideoCarousel() {
    var carousel = document.getElementById('video-carousel');
    var list = document.getElementById('video-list');
    if (!carousel || !list) return;

    var slides = Array.prototype.slice.call(list.querySelectorAll('.video-slide'));
    if (slides.length < 2) return;

    var current = 0;

    carousel.classList.add('video-carousel--js');
    carousel.setAttribute('role', 'region');
    carousel.setAttribute('aria-roledescription', 'carousel');
    carousel.setAttribute('aria-label', 'Feature videos');
    carousel.setAttribute('tabindex', '0');

    var status = document.createElement('p');
    status.className = 'visually-hidden';
    status.setAttribute('aria-live', 'polite');
    carousel.appendChild(status);

    var controls = document.createElement('div');
    controls.className = 'video-carousel__controls';

    var prevBtn = document.createElement('button');
    prevBtn.type = 'button';
    prevBtn.className = 'video-carousel__btn';
    prevBtn.setAttribute('aria-label', 'Previous slide');
    prevBtn.innerHTML = '<span aria-hidden="true">&#8249;</span>';

    var position = document.createElement('span');
    position.className = 'video-carousel__position';

    var nextBtn = document.createElement('button');
    nextBtn.type = 'button';
    nextBtn.className = 'video-carousel__btn';
    nextBtn.setAttribute('aria-label', 'Next slide');
    nextBtn.innerHTML = '<span aria-hidden="true">&#8250;</span>';

    controls.appendChild(prevBtn);
    controls.appendChild(position);
    controls.appendChild(nextBtn);
    carousel.appendChild(controls);

    function slideTitle(slide) {
      var heading = slide.querySelector('h3');
      return heading ? heading.textContent.trim() : '';
    }

    function render() {
      slides.forEach(function (slide, i) {
        var active = i === current;
        slide.hidden = !active;
        slide.setAttribute('role', 'group');
        slide.setAttribute('aria-roledescription', 'slide');
        slide.setAttribute(
          'aria-label',
          'Slide ' + (i + 1) + ' of ' + slides.length + ': ' + slideTitle(slide)
        );
      });
      position.textContent = (current + 1) + ' / ' + slides.length;
      status.textContent = 'Slide ' + (current + 1) + ' of ' + slides.length + ': ' + slideTitle(slides[current]);
      prevBtn.disabled = current === 0;
      nextBtn.disabled = current === slides.length - 1;
    }

    function goTo(index) {
      var clamped = Math.max(0, Math.min(slides.length - 1, index));
      if (clamped === current) return;
      current = clamped;
      render();
    }

    prevBtn.addEventListener('click', function () { goTo(current - 1); });
    nextBtn.addEventListener('click', function () { goTo(current + 1); });

    carousel.addEventListener('keydown', function (event) {
      if (event.key === 'ArrowRight') {
        event.preventDefault();
        goTo(current + 1);
      } else if (event.key === 'ArrowLeft') {
        event.preventDefault();
        goTo(current - 1);
      }
    });

    // Touch swipe: a horizontal drag past the threshold moves one slide.
    var touchStartX = null;
    var touchStartY = null;
    var SWIPE_THRESHOLD = 40;

    list.addEventListener('touchstart', function (event) {
      var touch = event.changedTouches[0];
      touchStartX = touch.clientX;
      touchStartY = touch.clientY;
    }, { passive: true });

    list.addEventListener('touchend', function (event) {
      if (touchStartX === null) return;
      var touch = event.changedTouches[0];
      var dx = touch.clientX - touchStartX;
      var dy = touch.clientY - touchStartY;
      touchStartX = null;
      touchStartY = null;
      if (Math.abs(dx) < SWIPE_THRESHOLD || Math.abs(dx) < Math.abs(dy)) return;
      if (dx < 0) {
        goTo(current + 1);
      } else {
        goTo(current - 1);
      }
    }, { passive: true });

    render();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initVideoCarousel);
  } else {
    initVideoCarousel();
  }
})();

/* --- Scroll reveal ------------------------------------------------------

   Fades sections in as they arrive.

   THE HARD RULE: THIS MAY NEVER BE THE REASON SOMETHING CANNOT BE READ.
   The .reveal class works by setting opacity to 0, so every path that fails
   to take it back off leaves a blank page with nothing logged. There are
   three such paths and all three are handled here:

     1. Reduced motion, or no IntersectionObserver  -> never start.
     2. Scripts blocked entirely                    -> .reveal is added by
        THIS file, so with no JS nothing is ever hidden in the first place.
     3. The observer exists but its callback never runs.

   (3) is not hypothetical. Measured on the deployed site: a freshly
   constructed IntersectionObserver did not emit even the initial
   isIntersecting:false record it is specified to, and ten sections sat at
   opacity 0 on live production. Whether that was the page or the automated
   browser looking at it, the honest conclusion is the same -- a decoration
   must not depend on a callback arriving.

   So there is a FAILSAFE: if the observer has not reported anything within
   1.2s of setup, everything is revealed and the observer is thrown away. The
   animation is lost, the content is not, and that is the correct trade every
   time. */
(function () {
  'use strict';

  var reduced = window.matchMedia
    && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  if (reduced || !('IntersectionObserver' in window)) return;

  function init() {
    var targets = Array.prototype.slice.call(document.querySelectorAll(
      '.section__inner, .screen-card, .cta-band, .hero__lede'));
    if (!targets.length) return;

    var io = null;
    var failsafe = null;
    var heard = false;

    function show(el) { el.classList.add('is-in'); }

    function revealAll() {
      if (io) { io.disconnect(); io = null; }
      targets.forEach(show);
    }

    io = new IntersectionObserver(function (entries) {
      heard = true;
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        show(entry.target);
        if (io) io.unobserve(entry.target);   // reveal once; not a toy
      });
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.08 });

    targets.forEach(function (el, i) {
      el.classList.add('reveal');
      // A small stagger inside a group, capped: by the fourth card a visitor
      // is waiting rather than being delighted.
      el.style.transitionDelay = Math.min(i, 3) * 60 + 'ms';
      io.observe(el);
    });

    failsafe = setTimeout(function () {
      if (!heard) revealAll();
    }, 1200);

    // Nothing here should keep a page alive on the way out.
    window.addEventListener('pagehide', function () {
      clearTimeout(failsafe);
      if (io) io.disconnect();
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
