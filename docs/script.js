// StatusBar Landing Page — Minimal JS
// Mobile nav, smooth scroll, copy buttons, collapsible, active nav

(function () {
  'use strict';

  // --- Mobile nav toggle ---
  const toggle = document.getElementById('nav-toggle');
  const links = document.getElementById('nav-links');

  if (toggle && links) {
    toggle.addEventListener('click', function () {
      links.classList.toggle('open');
    });

    // Close mobile nav when a link is clicked
    links.addEventListener('click', function (e) {
      if (e.target.tagName === 'A') {
        links.classList.remove('open');
      }
    });
  }

  // --- Smooth scroll for anchor links ---
  document.querySelectorAll('a[href^="#"]').forEach(function (anchor) {
    anchor.addEventListener('click', function (e) {
      var target = document.querySelector(this.getAttribute('href'));
      if (target) {
        e.preventDefault();
        target.scrollIntoView({ behavior: 'smooth' });
      }
    });
  });

  // --- Copy-to-clipboard on code blocks ---
  document.querySelectorAll('.copy-btn').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var code = this.parentElement.querySelector('code');
      if (!code) return;
      navigator.clipboard.writeText(code.textContent).then(function () {
        btn.textContent = 'Copied!';
        setTimeout(function () {
          btn.textContent = 'Copy';
        }, 1500);
      });
    });
  });

  // --- Collapsible sections ---
  var trigger = document.getElementById('build-trigger');
  var content = document.getElementById('build-content');

  if (trigger && content) {
    trigger.addEventListener('click', function () {
      trigger.classList.toggle('open');
      content.classList.toggle('open');
    });
  }

  // --- IntersectionObserver for active nav link ---
  var sections = document.querySelectorAll('section[id]');
  var navLinks = document.querySelectorAll('.nav-links a[href^="#"]');

  if (sections.length && navLinks.length && 'IntersectionObserver' in window) {
    var observer = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) {
            var id = entry.target.getAttribute('id');
            navLinks.forEach(function (link) {
              link.classList.toggle(
                'active',
                link.getAttribute('href') === '#' + id
              );
            });
          }
        });
      },
      { rootMargin: '-30% 0px -70% 0px' }
    );

    sections.forEach(function (section) {
      observer.observe(section);
    });
  }
})();
