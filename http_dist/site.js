(() => {
  const languages = new Set(['ja', 'en']);
  const buttons = document.querySelectorAll('[data-language]');
  let version = '';

  function renderVersion(language) {
    const element = document.getElementById('mac-ver');
    if (!element || !version) return;
    element.textContent = `${language === 'en' ? 'Mac version' : 'Mac 版'}: v${version}`;
    element.hidden = false;
  }

  function setLanguage(language, updateURL = false) {
    if (!languages.has(language)) return;
    document.documentElement.lang = language;
    document.querySelectorAll('[data-ja][data-en]').forEach(element => {
      const text = element.getAttribute(`data-${language}`);
      if (element.tagName === 'META') element.setAttribute('content', text);
      else element.textContent = text;
    });
    ['alt', 'aria-label'].forEach(attribute => {
      document.querySelectorAll(`[data-ja-${attribute}][data-en-${attribute}]`).forEach(element => {
        element.setAttribute(attribute, element.getAttribute(`data-${language}-${attribute}`));
      });
    });
    buttons.forEach(button => button.setAttribute('aria-pressed', String(button.dataset.language === language)));
    renderVersion(language);
    try { localStorage.setItem('youyaku-language', language); } catch (_) { /* Storage is optional. */ }
    if (updateURL) {
      const url = new URL(location.href);
      url.searchParams.set('lang', language);
      history.replaceState(null, '', url);
    }
  }

  let stored = '';
  try { stored = localStorage.getItem('youyaku-language') || ''; } catch (_) { /* Use the page default. */ }
  const requested = new URL(location.href).searchParams.get('lang');
  setLanguage(languages.has(requested) ? requested : languages.has(stored) ? stored : 'ja');
  buttons.forEach(button => button.addEventListener('click', () => setLanguage(button.dataset.language, true)));

  // The existing release process supplies this public version file.
  fetch('download/version.txt')
    .then(response => response.ok ? response.text() : '')
    .then(text => {
      const candidate = text.trim();
      if (!/^\d+\.\d+\.\d+(?:[-+][a-zA-Z0-9.-]+)?$/.test(candidate)) return;
      version = candidate;
      renderVersion(document.documentElement.lang);
    })
    .catch(() => { /* The download links remain available without version metadata. */ });
})();
