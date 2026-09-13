/* Copyright © 2026 GhostPunishR
   SPDX-License-Identifier: AGPL-3.0-only
   Bascule de thème du site. Trois états comme dans l'application : clair,
   sombre, ou le réglage du système tant que le visiteur n'a rien choisi. */

(function () {
  var root = document.documentElement;
  var button = document.getElementById('theme-toggle');
  if (!button) {
    return;
  }
  var label = button.querySelector('[data-theme-label]');
  var system = window.matchMedia('(prefers-color-scheme: dark)');

  function current() {
    var explicit = root.getAttribute('data-theme');
    if (explicit === 'light' || explicit === 'dark') {
      return explicit;
    }
    return system.matches ? 'dark' : 'light';
  }

  function render() {
    var dark = current() === 'dark';
    if (label) {
      label.textContent = dark ? 'Clair' : 'Sombre';
    }
    button.setAttribute(
      'aria-label',
      dark ? 'Passer au thème clair' : 'Passer au thème sombre'
    );
  }

  button.addEventListener('click', function () {
    var next = current() === 'dark' ? 'light' : 'dark';
    root.setAttribute('data-theme', next);
    try {
      localStorage.setItem('foxllm-theme', next);
    } catch (error) {
      /* Navigation privée ou stockage refusé : le choix vaut pour la page. */
    }
    render();
  });

  if (typeof system.addEventListener === 'function') {
    system.addEventListener('change', render);
  }

  render();
})();
