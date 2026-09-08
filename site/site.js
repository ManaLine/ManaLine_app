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
