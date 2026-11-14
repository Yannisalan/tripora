// Applies the user's saved Tripora theme (Profile > Theme) to the page
// background BEFORE Flutter boots, so someone who chose Dark on a light-mode
// OS (or Light on a dark-mode OS) never sees the loading page flash in the
// wrong colours. "system" (the default) keeps following prefers-color-scheme.
//
// shared_preferences on the web stores 'preferred_theme_mode' as
// localStorage['flutter.preferred_theme_mode'] holding a JSON string.
// Loaded as a same-origin file (not inline) to satisfy CSP script-src 'self'.
(function () {
  try {
    var raw = window.localStorage.getItem('flutter.preferred_theme_mode');
    var mode = raw ? JSON.parse(raw) : 'system';
    if (mode === 'dark' || mode === 'light') {
      document.documentElement.setAttribute('data-theme', mode);
    }
  } catch (e) {
    // Storage blocked (private mode, policy): fall back to the OS scheme.
  }
})();
