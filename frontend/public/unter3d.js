// Trójwymiarowe auta i mapa Wrocławia dla frontendu w Elmie.
//
// Elm renderuje <unter-auto> i <unter-miasto> jak zwykłe węzły HTML i podaje dane atrybutami
// (JSON w stringu). Elementy rysują się w shadow DOM, więc Elm nie widzi canvasu, a jego  // taste-skill-ignore
// własne dzieci (płaska mapa 2D) pokazują się tylko wtedy, gdy przeglądarka nie ma WebGL.
// Z powrotem do Elma idą dwa zdarzenia: "wybierz-auto" {id} i "klik-mapa" {lat, lon}.
import * as THREE from "three";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";
import { RoomEnvironment } from "three/addons/environments/RoomEnvironment.js";

const KOLOR = {
  granat: 0x1f2b4d,
  mandarynka: 0xf7941d,
  biel: 0xf4f4f2,
  grafit: 0x2b3039,
  popiel: 0xb8b4ab,
  opona: 0x15171c,
  felga: 0xc4c7cc,
  szyba: 0x0d1424,
  tlo: 0xeceae5,
};

const OGRANICZ_RUCH = matchMedia("(prefers-reduced-motion: reduce)").matches;

// --- modele aut ---------------------------------------------------------------------------
// Profil boczny w metrach: x od tyłu (-) do przodu (+), y w górę. "dol" to obrys nadwozia od
// przedniego zderzaka, przez maskę i linię okien, do tylnego zderzaka; spód z nadkolami
// dobudowuje się sam. "kabina" to przeszklenie nad linią okien, przykryte dachem.
const MODELE = {
  mini: {
    szer: 1.7, r: 0.31, kola: [-1.2, 1.25], lakier: KOLOR.biel,
    dol: [[1.85, 0.31], [1.9, 0.55], [1.8, 0.78], [1.05, 0.9], [-1.7, 0.95], [-1.85, 0.75], [-1.86, 0.31]],
    kabina: [[1.02, 0.9], [0.3, 1.42], [-1.45, 1.45], [-1.72, 0.95]],
  },
  komfort: {
    szer: 1.8, r: 0.33, kola: [-1.45, 1.45], lakier: KOLOR.granat,
    dol: [[2.3, 0.33], [2.36, 0.55], [2.28, 0.8], [1.2, 0.95], [-1.55, 0.98], [-2.28, 0.95], [-2.36, 0.7], [-2.32, 0.33]],
    kabina: [[1.17, 0.95], [0.35, 1.43], [-0.85, 1.45], [-1.6, 0.98]],
  },
  kombi: {
    szer: 1.82, r: 0.33, kola: [-1.5, 1.5], lakier: KOLOR.grafit,
    dol: [[2.37, 0.33], [2.42, 0.55], [2.33, 0.8], [1.25, 0.95], [-2.25, 1.0], [-2.4, 0.75], [-2.38, 0.33]],
    kabina: [[1.22, 0.95], [0.4, 1.45], [-2.05, 1.47], [-2.28, 1.0]],
  },
  xl: {
    szer: 1.95, r: 0.36, kola: [-1.65, 1.6], lakier: KOLOR.popiel,
    dol: [[2.5, 0.36], [2.55, 0.65], [2.45, 0.98], [1.75, 1.12], [-2.45, 1.15], [-2.55, 0.8], [-2.52, 0.36]],
    kabina: [[1.72, 1.12], [0.95, 1.9], [-2.3, 1.95], [-2.47, 1.15]],
  },
};

// liczba wolnych miejsc z backendu wyznacza klasę auta, tak samo jak w Main.elm
function klasaAuta(wolne) {
  if (wolne <= 2) return "mini";
  if (wolne === 3) return "komfort";
  if (wolne === 4) return "kombi";
  return "xl";
}

function obrysNadwozia(m) {
  const s = new THREE.Shape();
  const y0 = m.r;
  const R = m.r + 0.07;
  const przod = m.dol[0][0];
  const tyl = m.dol[m.dol.length - 1][0];
  s.moveTo(tyl, y0);
  for (const kx of m.kola) {
    s.lineTo(kx - R, y0);
    s.absarc(kx, y0, R, Math.PI, 0, true);
  }
  s.lineTo(przod, y0);
  for (const [x, y] of m.dol) s.lineTo(x, y);
  s.closePath();
  return s;
}

function wielokat(punkty) {
  const s = new THREE.Shape();
  s.moveTo(punkty[0][0], punkty[0][1]);
  for (const [x, y] of punkty.slice(1)) s.lineTo(x, y);
  s.closePath();
  return s;
}

function wyciagnij(ksztalt, glebokosc, fazka) {
  const g = new THREE.ExtrudeGeometry(ksztalt, {
    depth: glebokosc,
    bevelEnabled: true,
    bevelThickness: fazka,
    bevelSize: fazka,
    bevelSegments: 3,
    curveSegments: 18,
  });
  g.translate(0, 0, -glebokosc / 2);
  return g;
}

let cienTekstura = null;
function teksturaCienia() {
  if (cienTekstura) return cienTekstura;
  const c = document.createElement("canvas");
  c.width = c.height = 128;
  const x = c.getContext("2d");
  const g = x.createRadialGradient(64, 64, 8, 64, 64, 64);
  g.addColorStop(0, "rgba(5,7,10,0.55)");
  g.addColorStop(1, "rgba(5,7,10,0)");
  x.fillStyle = g;
  x.fillRect(0, 0, 128, 128);
  cienTekstura = new THREE.CanvasTexture(c);
  return cienTekstura;
}

// Buduje auto jako grupę: przód patrzy w +x, koła stoją na y = 0.
function zbudujAuto(kod, wolne, lakier) {
  const m = MODELE[kod] || MODELE.komfort;
  const auto = new THREE.Group();
  auto.userData.kod = kod;

  const farba = new THREE.MeshPhysicalMaterial({
    color: lakier ?? m.lakier, metalness: 0.45, roughness: 0.32, clearcoat: 1, clearcoatRoughness: 0.08,
  });
  const szklo = new THREE.MeshPhysicalMaterial({ color: KOLOR.szyba, metalness: 0.3, roughness: 0.06, clearcoat: 1 });
  const guma = new THREE.MeshStandardMaterial({ color: KOLOR.opona, roughness: 0.85 });
  const felga = new THREE.MeshStandardMaterial({ color: KOLOR.felga, metalness: 0.9, roughness: 0.25 });
  const czern = new THREE.MeshStandardMaterial({ color: 0x0b0d10, roughness: 0.6 });

  const W = m.szer;
  const nadwozie = new THREE.Mesh(wyciagnij(obrysNadwozia(m), W - 0.08, 0.04), farba);
  auto.add(nadwozie);

  const kabina = new THREE.Mesh(wyciagnij(wielokat(m.kabina), W * 0.8, 0.035), szklo);
  auto.add(kabina);

  // dach: płyta lakieru na górnej krawędzi przeszklenia
  const [, d1, d2] = m.kabina;
  const dach = new THREE.Mesh(
    wyciagnij(wielokat([[d1[0] - 0.06, d1[1] - 0.04], [d2[0] + 0.03, d2[1] - 0.04], [d2[0] + 0.03, d2[1] + 0.04], [d1[0] - 0.1, d1[1] + 0.04]]), W * 0.82, 0.03),
    farba,
  );
  auto.add(dach);

  // słupek B, żeby boczne szyby nie wyglądały jak jedna tafla
  const srodekDachu = (d1[0] + d2[0]) / 2;
  const slupek = new THREE.Mesh(new THREE.BoxGeometry(0.12, d1[1] - m.kabina[0][1], W * 0.81 + 0.08), farba);
  slupek.position.set(srodekDachu + 0.1, (d1[1] + m.kabina[0][1]) / 2, 0);
  auto.add(slupek);

  // koła
  const kola = [];
  const opona = new THREE.CylinderGeometry(m.r, m.r, 0.26, 28);
  opona.rotateX(Math.PI / 2);
  const tarcza = new THREE.CylinderGeometry(m.r * 0.62, m.r * 0.62, 0.27, 20);
  tarcza.rotateX(Math.PI / 2);
  for (const kx of m.kola) {
    for (const strona of [-1, 1]) {
      const kolo = new THREE.Group();
      kolo.add(new THREE.Mesh(opona, guma));
      kolo.add(new THREE.Mesh(tarcza, felga));
      kolo.position.set(kx, m.r, strona * (W / 2 - 0.16));
      auto.add(kolo);
      kola.push(kolo);
    }
  }
  auto.userData.kola = kola;
  auto.userData.promien = m.r;

  // światła: przód białe, tył czerwone
  const przod = m.dol[0][0];
  const tyl = m.dol[m.dol.length - 1][0];
  const reflektor = new THREE.MeshStandardMaterial({ color: 0xffffff, emissive: 0xfff4e0, emissiveIntensity: 1.4 });
  const stop = new THREE.MeshStandardMaterial({ color: 0x8a0f0f, emissive: 0xd0191b, emissiveIntensity: 0.9 });
  for (const strona of [-1, 1]) {
    const r = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.1, 0.34), reflektor);
    r.position.set(przod + 0.02, m.dol[1][1] + 0.1, strona * (W / 2 - 0.33));
    auto.add(r);
    const t = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.12, 0.38), stop);
    t.position.set(tyl - 0.02, m.dol[m.dol.length - 2][1] + 0.06, strona * (W / 2 - 0.3));
    auto.add(t);
    const lusterko = new THREE.Mesh(new THREE.BoxGeometry(0.12, 0.09, 0.16), farba);
    lusterko.position.set(m.kabina[0][0] - 0.12, m.kabina[0][1] + 0.08, strona * (W / 2 + 0.03));
    auto.add(lusterko);
  }
  // atrapa chłodnicy
  const grill = new THREE.Mesh(new THREE.BoxGeometry(0.05, 0.12, W * 0.42), czern);
  grill.position.set(przod + 0.03, m.dol[1][1] - 0.02, 0);
  auto.add(grill);

  // kogut na dachu: świeci na pomarańczowo, gdy auto jest wolne, jak w taksówce
  const kogutMat = new THREE.MeshStandardMaterial({ color: KOLOR.mandarynka, emissive: KOLOR.mandarynka, emissiveIntensity: 0.9, roughness: 0.4 });
  const kogut = new THREE.Mesh(new THREE.BoxGeometry(0.3, 0.17, 0.7), kogutMat);
  kogut.position.set(srodekDachu, Math.max(d1[1], d2[1]) + 0.15, 0);
  auto.add(kogut);
  auto.userData.kogut = kogutMat;
  ustawKoguta(auto, wolne);

  // miękki cień pod autem
  const dl = przod - tyl;
  const cien = new THREE.Mesh(
    new THREE.PlaneGeometry(dl * 1.25, W * 1.7),
    new THREE.MeshBasicMaterial({ map: teksturaCienia(), transparent: true, depthWrite: false }),
  );
  cien.rotation.x = -Math.PI / 2;
  cien.position.y = 0.005;
  auto.add(cien);

  return auto;
}

function ustawKoguta(auto, wolne) {
  const mat = auto.userData.kogut;
  if (wolne) {
    mat.color.setHex(KOLOR.mandarynka);
    mat.emissive.setHex(KOLOR.mandarynka);
    mat.emissiveIntensity = 0.9;
  } else {
    mat.color.setHex(KOLOR.granat);
    mat.emissive.setHex(0x000000);
    mat.emissiveIntensity = 0;
  }
}

function zwolnij(obiekt) {
  obiekt.traverse((o) => {
    if (o.geometry) o.geometry.dispose();
    if (o.material) {
      for (const m of [].concat(o.material)) {
        if (m.map && m.map !== cienTekstura) m.map.dispose();
        m.dispose();
      }
    }
  });
}

// --- wspólna baza obu elementów -------------------------------------------------------------
class Scena3D extends HTMLElement {
  connectedCallback() {
    const cien = this.shadowRoot || this.attachShadow({ mode: "open" });
    cien.innerHTML =
      "<style>:host{display:block;position:relative;overflow:hidden}" +
      "canvas{display:block;width:100%;height:100%;outline:none}</style>";
    let renderer;
    try {
      renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, powerPreference: "high-performance" });
    } catch (e) {
      // bez WebGL pokazujemy to, co Elm wstawił do środka (płaską mapę)
      cien.innerHTML += "<slot></slot>";
      return;
    }
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    cien.appendChild(renderer.domElement);
    this.renderer = renderer;

    this.scene = new THREE.Scene();
    const pmrem = new THREE.PMREMGenerator(renderer);
    this.scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
    pmrem.dispose();
    this.camera = new THREE.PerspectiveCamera(30, 1, 0.5, 3000);
    this.zegar = new THREE.Clock();

    this.zbuduj();

    this.ro = new ResizeObserver(() => this.dopasuj());
    this.ro.observe(this);
    this.io = new IntersectionObserver(([wpis]) => {
      this.widoczny = wpis.isIntersecting;
      if (this.widoczny) this.uruchom();
    }, { rootMargin: "120px" });
    this.io.observe(this);
    this.dopasuj();
  }

  disconnectedCallback() {
    cancelAnimationFrame(this.raf);
    this.ro?.disconnect();
    this.io?.disconnect();
    this.controls?.dispose();
    if (this.renderer) {
      this.scene.traverse((o) => o !== this.scene && o.parent === this.scene && zwolnij(o));
      this.renderer.dispose();
      this.renderer.forceContextLoss();
      this.renderer.domElement.remove();
      this.renderer = null;
    }
  }

  dopasuj() {
    const w = this.clientWidth;
    const h = this.clientHeight;
    if (!w || !h || !this.renderer) return;
    this.renderer.setSize(w, h, false);
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
    this.renderer.render(this.scene, this.camera);
  }

  uruchom() {
    cancelAnimationFrame(this.raf);
    this.zegar.getDelta();
    const krok = () => {
      if (!this.widoczny || !this.renderer) return;
      this.klatka(Math.min(this.zegar.getDelta(), 0.1));
      this.renderer.render(this.scene, this.camera);
      this.raf = requestAnimationFrame(krok);
    };
    this.raf = requestAnimationFrame(krok);
  }

  json(nazwa, zapas) {
    try {
      return JSON.parse(this.getAttribute(nazwa)) ?? zapas;
    } catch (e) {
      return zapas;
    }
  }
}

// --- <unter-auto model="kombi" wolne="tak"> : jedno auto na obrotowym podeście ----------------
class UnterAuto extends Scena3D {
  static get observedAttributes() {
    return ["model", "wolne"];
  }

  attributeChangedCallback() {
    if (this.scene) this.ustawAuto();
  }

  zbuduj() {
    const s = this.scene;
    s.add(new THREE.HemisphereLight(0xffffff, 0x9aa0ad, 0.7));
    const slonce = new THREE.DirectionalLight(0xffffff, 1.8);
    slonce.position.set(5, 9, 4);
    s.add(slonce);

    this.camera.fov = 24;
    this.camera.position.set(7.4, 2.7, 8.4);
    this.controls = new OrbitControls(this.camera, this.renderer.domElement);
    Object.assign(this.controls, {
      enableZoom: false,
      enablePan: false,
      enableDamping: true,
      autoRotate: !OGRANICZ_RUCH,
      autoRotateSpeed: 1.6,
      minPolarAngle: 0.95,
      maxPolarAngle: 1.45,
    });
    this.controls.target.set(0, 0.8, 0);
    // pionowe przeciąganie palcem nadal przewija stronę
    this.renderer.domElement.style.touchAction = "pan-y";
    this.renderer.domElement.style.cursor = "grab";

    this.odjezdzajace = [];
    this.ustawAuto();
  }

  ustawAuto() {
    const kod = this.getAttribute("model") || "komfort";
    const wolne = this.getAttribute("wolne") !== "nie";
    if (this.auto && this.auto.userData.kod === kod) {
      ustawKoguta(this.auto, wolne);
      return;
    }
    const bylo = Boolean(this.auto);
    if (this.auto) {
      this.auto.userData.odjazd = 0;
      this.odjezdzajace.push(this.auto);
    }
    this.auto = zbudujAuto(kod, wolne);
    // przy zamianie nowe auto rusza z opóźnieniem, żeby nie najechać na odjeżdżające
    this.auto.userData.wjazd = OGRANICZ_RUCH ? 1 : bylo ? -0.35 : 0;
    this.auto.position.x = OGRANICZ_RUCH ? 0 : -12;
    this.scene.add(this.auto);
    if (!this.widoczny) this.klatka(0);
  }

  klatka(dt) {
    // poprzednie auto odjeżdża do przodu, nowe dojeżdża za nim i hamuje; koła się kręcą
    const a = this.auto;
    if (a.userData.wjazd < 1) {
      a.userData.wjazd = Math.min(1, a.userData.wjazd + dt / 0.9);
      const t = 1 - Math.pow(1 - Math.max(0, a.userData.wjazd), 3);
      const x = -12 * (1 - t);
      this.krecKolami(a, x - a.position.x);
      a.position.x = x;
    }
    for (const stare of this.odjezdzajace) {
      stare.userData.odjazd += dt / 0.6;
      const t = stare.userData.odjazd * stare.userData.odjazd;
      const x = 12 * t;
      this.krecKolami(stare, x - stare.position.x);
      stare.position.x = x;
    }
    this.odjezdzajace = this.odjezdzajace.filter((stare) => {
      if (stare.userData.odjazd < 1) return true;
      this.scene.remove(stare);
      zwolnij(stare);
      return false;
    });
    this.controls.update(dt);
  }

  krecKolami(auto, droga) {
    for (const kolo of auto.userData.kola) kolo.rotation.z -= droga / auto.userData.promien;
  }
}

// --- <unter-miasto> : flota na mapie Wrocławia ------------------------------------------------
// Rzut Mercatora, ten sam co w kafelkach mapy, więc auta stoją dokładnie na swoich ulicach.
const mx = (lon) => (lon + 180) / 360;
const my = (lat) => {
  const f = (lat * Math.PI) / 180;
  return (1 - Math.log(Math.tan(f) + 1 / Math.cos(f)) / Math.PI) / 2;
};
const lonZ = (x) => x * 360 - 180;
const latZ = (y) => (Math.atan(Math.sinh(Math.PI * (1 - 2 * y))) * 180) / Math.PI;

const SZEROKOSC_SWIATA = 100; // tyle jednostek ma szerokość widocznego zakresu
const SKALA_AUTA = 0.62;
const CZAS_RUCHU = 2000; // ms, tyle co odświeżanie listy aut w Elmie

// zakres jak w Main.elm: okolice Wrocławia, rozszerzane o auta i punkty, zaokrąglone do 0,05°
function granice(auta, punkty) {
  const lat = [51.0, 51.2, ...auta.map((a) => a.lat), ...punkty.map((p) => p.lat)];
  const lon = [16.85, 17.15, ...auta.map((a) => a.lon), ...punkty.map((p) => p.lon)];
  const dol = (x) => Math.floor(x / 0.05 + 1e-9) * 0.05;
  const gora = (x) => Math.ceil(x / 0.05 - 1e-9) * 0.05;
  return { latMin: dol(Math.min(...lat)), latMax: gora(Math.max(...lat)), lonMin: dol(Math.min(...lon)), lonMax: gora(Math.max(...lon)) };
}

function etykieta(tekst, tlo, kolorTekstu) {
  const c = document.createElement("canvas");
  c.width = 256;
  c.height = 112;
  const x = c.getContext("2d");
  x.font = "600 54px 'Schibsted Grotesk', system-ui, sans-serif";
  const w = Math.min(240, x.measureText(tekst).width + 44);
  x.fillStyle = tlo;
  x.beginPath();
  x.roundRect((256 - w) / 2, 14, w, 84, 8);
  x.fill();
  x.fillStyle = kolorTekstu;
  x.textAlign = "center";
  x.textBaseline = "middle";
  x.fillText(tekst, 128, 58);
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  const sprite = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex, depthTest: false, toneMapped: false }));
  sprite.renderOrder = 10;
  return sprite;
}

function pinezka(kolor) {
  const g = new THREE.Group();
  const mat = new THREE.MeshStandardMaterial({ color: kolor, roughness: 0.35, metalness: 0.1 });
  const noga = new THREE.Mesh(new THREE.CylinderGeometry(0.12, 0.12, 4, 12), mat);
  noga.position.y = 2;
  const glowa = new THREE.Mesh(new THREE.SphereGeometry(0.9, 24, 16), mat);
  glowa.position.y = 4.6;
  const podstawa = new THREE.Mesh(new THREE.RingGeometry(0.6, 1.1, 32), new THREE.MeshBasicMaterial({ color: kolor, side: THREE.DoubleSide }));
  podstawa.rotation.x = -Math.PI / 2;
  podstawa.position.y = 0.05;
  g.add(noga, glowa, podstawa);
  return g;
}

class UnterMiasto extends Scena3D {
  static get observedAttributes() {
    return ["auta", "punkty", "wybrane", "klikalna"];
  }

  attributeChangedCallback(nazwa) {
    if (!this.scene) return;
    if (nazwa === "auta" || nazwa === "punkty") this.wczytaj();
    if (nazwa === "wybrane") this.zaznacz();
    if (nazwa === "klikalna") this.renderer.domElement.style.cursor = this.klikalna() ? "crosshair" : "grab";
  }

  klikalna() {
    return this.getAttribute("klikalna") === "tak";
  }

  zbuduj() {
    const s = this.scene;
    this.aplikacja = this.getAttribute("tryb") === "aplikacja";
    s.background = new THREE.Color(KOLOR.tlo);
    s.fog = new THREE.Fog(KOLOR.tlo, 170, 420);
    s.add(new THREE.HemisphereLight(0xffffff, 0xa7a9b0, 0.9));
    const slonce = new THREE.DirectionalLight(0xffffff, 1.6);
    slonce.position.set(40, 90, 30);
    s.add(slonce);

    const ziemia = new THREE.Mesh(new THREE.PlaneGeometry(4000, 4000), new THREE.MeshBasicMaterial({ color: KOLOR.tlo }));
    ziemia.rotation.x = -Math.PI / 2;
    ziemia.position.y = -0.2;
    s.add(ziemia);

    this.kafle = new THREE.Group();
    this.flota = new THREE.Group();
    this.znaczniki = new THREE.Group();
    s.add(this.kafle, this.flota, this.znaczniki);
    this.auta = new Map();
    this.plaszczyzna = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
    this.promien = new THREE.Raycaster();

    this.obwodka = new THREE.Mesh(
      new THREE.RingGeometry(2.6, 3.3, 48),
      new THREE.MeshBasicMaterial({ color: KOLOR.mandarynka, side: THREE.DoubleSide, transparent: true, depthWrite: false }),
    );
    this.obwodka.rotation.x = -Math.PI / 2;
    this.obwodka.position.y = 0.08;
    this.obwodka.visible = false;
    s.add(this.obwodka);

    if (this.aplikacja) {
      this.controls = new OrbitControls(this.camera, this.renderer.domElement);
      Object.assign(this.controls, {
        enableDamping: true,
        screenSpacePanning: false,
        minDistance: 14,
        maxDistance: 260,
        maxPolarAngle: 1.22,
      });
      // jak w aplikacjach z mapą: lewy przycisk przesuwa, prawy obraca
      this.controls.mouseButtons = { LEFT: THREE.MOUSE.PAN, MIDDLE: THREE.MOUSE.DOLLY, RIGHT: THREE.MOUSE.ROTATE };
      this.controls.touches = { ONE: THREE.TOUCH.PAN, TWO: THREE.TOUCH.DOLLY_ROTATE };
      this.renderer.domElement.style.cursor = this.klikalna() ? "crosshair" : "grab";
    }
    this.katKamery = 0.6;
    this.podepnijKlikanie();
    this.wczytaj();
    this.zaznacz();
  }

  // --- geografia ---
  ustawGranice(g) {
    const klucz = [g.latMin, g.latMax, g.lonMin, g.lonMax].map((v) => v.toFixed(2)).join();
    if (klucz === this.kluczGranic) return;
    const pierwszy = !this.kluczGranic;
    this.kluczGranic = klucz;
    this.g = g;
    this.x0 = mx(g.lonMin);
    this.x1 = mx(g.lonMax);
    this.y0 = my(g.latMax);
    this.y1 = my(g.latMin);
    this.K = SZEROKOSC_SWIATA / (this.x1 - this.x0);
    this.xs = (this.x0 + this.x1) / 2;
    this.ys = (this.y0 + this.y1) / 2;
    this.zaladujKafle();
    if (pierwszy && this.aplikacja) this.ustawKamere();
  }

  naSwiat(lat, lon, wektor = new THREE.Vector3()) {
    return wektor.set((mx(lon) - this.xs) * this.K, 0, (my(lat) - this.ys) * this.K);
  }

  naGeo(p) {
    return { lat: latZ(p.z / this.K + this.ys), lon: lonZ(p.x / this.K + this.xs) };
  }

  zaladujKafle() {
    for (const k of [...this.kafle.children]) {
      this.kafle.remove(k);
      zwolnij(k);
    }
    let z = 15;
    while (z > 8 && (this.x1 - this.x0) * 2 ** z > 7) z--;
    // dokładna warstwa na zakres plus zgrubna warstwa pod spodem aż po horyzont
    this.warstwa(z, 0, 0);
    this.warstwa(z - 2, 2, -0.08);
  }

  warstwa(z, zapas, wysokosc) {
    const n = 2 ** z;
    const ladowacz = new THREE.TextureLoader();
    ladowacz.setCrossOrigin("anonymous");
    const bok = this.K / n;
    const tx0 = Math.floor(this.x0 * n) - zapas;
    const tx1 = Math.floor(this.x1 * n) + zapas;
    const ty0 = Math.floor(this.y0 * n) - zapas;
    const ty1 = Math.floor(this.y1 * n) + zapas;
    for (let tx = tx0; tx <= tx1; tx++) {
      for (let ty = ty0; ty <= ty1; ty++) {
        const mat = new THREE.MeshBasicMaterial({ color: KOLOR.tlo, toneMapped: false });
        const kafel = new THREE.Mesh(new THREE.PlaneGeometry(bok, bok), mat);
        kafel.rotation.x = -Math.PI / 2;
        kafel.position.set(((tx + 0.5) / n - this.xs) * this.K, wysokosc, ((ty + 0.5) / n - this.ys) * this.K);
        this.kafle.add(kafel);
        // jasnoszary podkład Esri: bez klucza API i z CORS, więc nadaje się na teksturę WebGL
        ladowacz.load(`https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Base/MapServer/tile/${z}/${ty}/${tx}`, (tex) => {
          tex.colorSpace = THREE.SRGBColorSpace;
          tex.anisotropy = 4;
          mat.map = tex;
          mat.color.setHex(0xffffff);
          mat.needsUpdate = true;
        });
      }
    }
  }

  ustawKamere() {
    const cel = new THREE.Vector3(0, 0, 0);
    this.controls.target.copy(cel);
    this.camera.position.set(0, 92, 74);
    this.controls.update();
  }

  // --- dane z Elma ---
  wczytaj() {
    const auta = this.json("auta", []);
    const punkty = this.json("punkty", []);
    this.ustawGranice(granice(auta, punkty));
    const teraz = performance.now();
    const obecne = new Set();
    for (const a of auta) {
      obecne.add(a.id);
      const wolne = a.cel === null;
      let wpis = this.auta.get(a.id);
      if (!wpis) {
        const obiekt = zbudujAuto(klasaAuta(a.wolne), wolne);
        obiekt.scale.setScalar(SKALA_AUTA);
        obiekt.userData.idAuta = a.id;
        // niewidoczny większy klocek, żeby w małe auto dało się trafić kliknięciem
        const traf = new THREE.Mesh(new THREE.BoxGeometry(6, 3, 4), new THREE.MeshBasicMaterial({ transparent: true, opacity: 0, depthWrite: false }));
        traf.position.y = 1;
        obiekt.add(traf);
        if (this.aplikacja) {
          const opis = etykieta("#" + a.id, "#1f2b4d", "#ffffff");
          opis.scale.set(4.6, 2, 1);
          opis.position.y = 4.2;
          obiekt.add(opis);
        }
        this.flota.add(obiekt);
        wpis = { obiekt, od: { lat: a.lat, lon: a.lon }, do: { lat: a.lat, lon: a.lon }, start: teraz };
        this.auta.set(a.id, wpis);
      } else {
        wpis.od = this.pozycjaTeraz(wpis, teraz);
        wpis.do = { lat: a.lat, lon: a.lon };
        wpis.start = teraz;
      }
      wpis.cel = a.cel;
      wpis.celKoncowy = a.celKoncowy || null;
      ustawKoguta(wpis.obiekt, wolne);
    }
    for (const [id, wpis] of this.auta) {
      if (obecne.has(id)) continue;
      this.flota.remove(wpis.obiekt);
      zwolnij(wpis.obiekt);
      if (wpis.trasa) {
        this.znaczniki.remove(wpis.trasa, wpis.metaGrupa, wpis.odbior);
        zwolnij(wpis.trasa);
        zwolnij(wpis.metaGrupa);
        zwolnij(wpis.odbior);
      }
      this.auta.delete(id);
    }
    this.ustawPunkty(punkty);
  }

  ustawPunkty(punkty) {
    const klucz = JSON.stringify(punkty);
    if (klucz === this.kluczPunktow) return;
    this.kluczPunktow = klucz;
    for (const p of this.pinezki || []) {
      this.znaczniki.remove(p);
      zwolnij(p);
    }
    this.pinezki = punkty.map((p) => {
      const start = p.rodzaj === "start";
      const pin = pinezka(start ? KOLOR.granat : KOLOR.mandarynka);
      const opis = etykieta(start ? "Start" : "Cel", start ? "#1f2b4d" : "#f7941d", start ? "#ffffff" : "#1f2b4d");
      opis.scale.set(5.2, 2.3, 1);
      opis.position.y = 7.4;
      pin.add(opis);
      this.naSwiat(p.lat, p.lon, pin.position);
      this.znaczniki.add(pin);
      return pin;
    });
  }

  pozycjaTeraz(wpis, teraz) {
    const t = Math.min(1, (teraz - wpis.start) / CZAS_RUCHU);
    return { lat: wpis.od.lat + (wpis.do.lat - wpis.od.lat) * t, lon: wpis.od.lon + (wpis.do.lon - wpis.od.lon) * t };
  }

  zaznacz() {
    const id = this.getAttribute("wybrane") || "";
    this.wybrane = id;
    this.doWybranego = this.aplikacja && this.auta.has(id) ? 0 : 1;
  }

  // --- klatka ---
  klatka(dt) {
    const teraz = performance.now();
    const tmp = new THREE.Vector3();
    for (const [id, wpis] of this.auta) {
      const geo = this.pozycjaTeraz(wpis, teraz);
      const o = wpis.obiekt;
      this.naSwiat(geo.lat, geo.lon, tmp);
      const dx = tmp.x - o.position.x;
      const dz = tmp.z - o.position.z;
      if (dx * dx + dz * dz > 1e-6) {
        const kurs = Math.atan2(-dz, dx);
        let roznica = kurs - o.rotation.y;
        roznica = Math.atan2(Math.sin(roznica), Math.cos(roznica));
        o.rotation.y += roznica * Math.min(1, dt * 6);
      }
      o.position.copy(tmp);
      this.rysujTrase(wpis, tmp);
      if (id === this.wybrane) {
        this.obwodka.visible = true;
        this.obwodka.position.x = tmp.x;
        this.obwodka.position.z = tmp.z;
        const puls = OGRANICZ_RUCH ? 1 : 1 + Math.sin(teraz / 260) * 0.08;
        this.obwodka.scale.setScalar(puls);
        if (this.doWybranego < 1) {
          // kamera płynnie podjeżdża nad wybrane auto
          this.doWybranego = Math.min(1, this.doWybranego + dt / 0.8);
          const krok = OGRANICZ_RUCH ? 1 : Math.min(1, dt * 4);
          const przesuniecie = tmp.clone().sub(this.controls.target).multiplyScalar(krok);
          this.controls.target.add(przesuniecie);
          this.camera.position.add(przesuniecie);
        }
      }
    }
    if (!this.auta.has(this.wybrane)) this.obwodka.visible = false;

    if (this.aplikacja) {
      this.controls.update();
    } else {
      // podgląd: kamera powoli krąży nad środkiem floty
      if (!OGRANICZ_RUCH) this.katKamery += dt * 0.05;
      const srodek = this.srodekFloty();
      const R = 64;
      const nachylenie = 0.92;
      this.camera.position.set(
        srodek.x + Math.sin(nachylenie) * Math.cos(this.katKamery) * R,
        Math.cos(nachylenie) * R,
        srodek.z + Math.sin(nachylenie) * Math.sin(this.katKamery) * R,
      );
      this.camera.lookAt(srodek);
    }
  }

  srodekFloty() {
    if (!this.srodek) this.srodek = new THREE.Vector3();
    if (this.auta.size === 0) return this.srodek.set(0, 0, 0);
    const suma = new THREE.Vector3();
    for (const { obiekt } of this.auta.values()) suma.add(obiekt.position);
    suma.divideScalar(this.auta.size);
    return this.srodek.lerp(suma, 0.02);
  }

  // Trasa zajętego auta: przerywana linia auto → cel. Gdy auto jedzie jeszcze po klienta,
  // cel to miejsce odbioru, a linia biegnie dalej do celKoncowy; odbiór ma wtedy własne kółko.
  rysujTrase(wpis, pozycja) {
    if (!wpis.cel) {
      if (wpis.trasa) {
        this.znaczniki.remove(wpis.trasa, wpis.metaGrupa, wpis.odbior);
        zwolnij(wpis.trasa);
        zwolnij(wpis.metaGrupa);
        zwolnij(wpis.odbior);
        wpis.trasa = null;
      }
      return;
    }
    const przystanek = this.naSwiat(wpis.cel[0], wpis.cel[1]);
    const meta = wpis.celKoncowy ? this.naSwiat(wpis.celKoncowy[0], wpis.celKoncowy[1]) : przystanek.clone();
    if (!wpis.trasa) {
      const geo = new THREE.BufferGeometry().setFromPoints([pozycja.clone(), przystanek, meta]);
      wpis.trasa = new THREE.Line(geo, new THREE.LineDashedMaterial({ color: KOLOR.granat, dashSize: 1.2, gapSize: 0.8 }));
      const kolko = (kolor) => {
        const m = new THREE.Mesh(new THREE.RingGeometry(0.8, 1.4, 32), new THREE.MeshBasicMaterial({ color: kolor, side: THREE.DoubleSide }));
        m.rotation.x = -Math.PI / 2;
        return m;
      };
      wpis.metaGrupa = kolko(KOLOR.granat);
      wpis.odbior = kolko(KOLOR.mandarynka);
      this.znaczniki.add(wpis.trasa, wpis.metaGrupa, wpis.odbior);
    }
    const poz = wpis.trasa.geometry.attributes.position;
    poz.setXYZ(0, pozycja.x, 0.15, pozycja.z);
    poz.setXYZ(1, przystanek.x, 0.15, przystanek.z);
    poz.setXYZ(2, meta.x, 0.15, meta.z);
    poz.needsUpdate = true;
    wpis.trasa.computeLineDistances();
    wpis.metaGrupa.position.set(meta.x, 0.1, meta.z);
    wpis.odbior.visible = Boolean(wpis.celKoncowy);
    wpis.odbior.position.set(przystanek.x, 0.12, przystanek.z);
  }

  // --- klikanie: auto albo punkt na mapie ---
  podepnijKlikanie() {
    const el = this.renderer.domElement;
    el.addEventListener("pointerdown", (e) => {
      this.wcisniete = [e.clientX, e.clientY];
    });
    el.addEventListener("pointerup", (e) => {
      if (!this.wcisniete) return;
      const przesuniecie = Math.hypot(e.clientX - this.wcisniete[0], e.clientY - this.wcisniete[1]);
      this.wcisniete = null;
      if (przesuniecie > 6 || !this.aplikacja) return;
      this.celujPromien(e);
      if (this.klikalna()) {
        const p = new THREE.Vector3();
        if (this.promien.ray.intersectPlane(this.plaszczyzna, p)) {
          this.dispatchEvent(new CustomEvent("klik-mapa", { detail: this.naGeo(p), bubbles: true }));
        }
        return;
      }
      const id = this.autoPodKursorem();
      if (id) this.dispatchEvent(new CustomEvent("wybierz-auto", { detail: { id }, bubbles: true }));
    });
    el.addEventListener("pointermove", (e) => {
      if (!this.aplikacja || this.klikalna() || e.buttons) return;
      this.celujPromien(e);
      el.style.cursor = this.autoPodKursorem() ? "pointer" : "grab";
    });
  }

  celujPromien(e) {
    const r = this.renderer.domElement.getBoundingClientRect();
    const p = new THREE.Vector2(((e.clientX - r.left) / r.width) * 2 - 1, -((e.clientY - r.top) / r.height) * 2 + 1);
    this.promien.setFromCamera(p, this.camera);
  }

  autoPodKursorem() {
    const traf = this.promien.intersectObjects(this.flota.children, true)[0];
    let o = traf?.object;
    while (o && !o.userData.idAuta) o = o.parent;
    return o?.userData.idAuta;
  }
}

customElements.define("unter-auto", UnterAuto);
customElements.define("unter-miasto", UnterMiasto);
