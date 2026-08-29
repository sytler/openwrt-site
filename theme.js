(function () {
  var root = document.documentElement;
  try {
    var saved = localStorage.getItem('site-theme');
    var mq = window.matchMedia('(prefers-color-scheme: light)');
    root.classList.toggle('light', saved === 'light' || (!saved && mq.matches));
  } catch (e) { /* storage blocked — keep dark default */ }
  var btn = document.getElementById('themeToggle');
  if (btn) btn.addEventListener('click', function () {
    root.classList.toggle('light');
    try { localStorage.setItem('site-theme', root.classList.contains('light') ? 'light' : 'dark'); } catch (e) {}
  });
})();