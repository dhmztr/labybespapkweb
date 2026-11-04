var KLUCZ = "token";
var KLUCZ_OCEN = "doOceny";
var zapamietany = null;
var oceny = {};
try { zapamietany = localStorage.getItem(KLUCZ); } catch (e) {}
try { oceny = JSON.parse(localStorage.getItem(KLUCZ_OCEN)) || {}; } catch (e) {}
var app = Elm.Main.init({ node: document.getElementById("app"), flags: { token: zapamietany, oceny: oceny } });
app.ports.zapiszToken.subscribe(function (token) {
  try { localStorage.setItem(KLUCZ, token); } catch (e) {}
});
app.ports.usunToken.subscribe(function () {
  try { localStorage.removeItem(KLUCZ); } catch (e) {}
});
// auta do oceny, per e-mail: pozwolenie na opinię przeżywa odświeżenie strony
app.ports.zapiszOceny.subscribe(function (mapa) {
  try { localStorage.setItem(KLUCZ_OCEN, JSON.stringify(mapa)); } catch (e) {}
});

// Postęp przewijania nagłówka (0..1) w zmiennej --p: z niej CSS przesuwa taśmę kadrów.
// Elm nie ustawia stylu na #hero, więc nie nadpisze tej zmiennej przy rysowaniu.
(function () {
  var czeka = false;
  function hero() {
    czeka = false;
    var el = document.getElementById("hero");
    if (!el) return;
    var zakres = el.offsetHeight - window.innerHeight;
    var p = zakres > 0 ? Math.min(1, Math.max(0, -el.getBoundingClientRect().top / zakres)) : 0;
    el.style.setProperty("--p", p.toFixed(4));
  }
  function zaplanuj() { if (!czeka) { czeka = true; requestAnimationFrame(hero); } }
  addEventListener("scroll", zaplanuj, { passive: true });
  addEventListener("resize", zaplanuj);
  new MutationObserver(zaplanuj).observe(document.body, { childList: true });
  hero();
})();

// Wejścia sekcji: elementy z data-wejdz dostają data-widoczne, gdy wjadą na ekran.
(function () {
  if (!("IntersectionObserver" in window)) return;
  document.documentElement.classList.add("ruch");
  var io = new IntersectionObserver(function (wpisy) {
    wpisy.forEach(function (w) {
      if (w.isIntersecting) { w.target.setAttribute("data-widoczne", ""); io.unobserve(w.target); }
    });
  }, { rootMargin: "0px 0px -8% 0px" });
  function obserwuj() {
    document.querySelectorAll("[data-wejdz]:not([data-obserwowane])").forEach(function (el) {
      el.setAttribute("data-obserwowane", "");
      io.observe(el);
    });
  }
  new MutationObserver(obserwuj).observe(document.body, { childList: true, subtree: true });
  obserwuj();
})();
