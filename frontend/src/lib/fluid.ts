/* Fluid background engine for the login page.
 *
 * Two stacked layers driven by ONE shared 3D simplex field:
 *   1. blob layer  - low-res metaball-ish gradients, CSS-blurred, the "liquid mesh"
 *   2. flow layer  - particles advected by curl-ish noise, trails via destination-out
 *
 * Time advances monotonically (never wrapped), so the motion is quasi-periodic and
 * never loops back on itself the way a keyframe animation does. */

const GRAD3 = new Int8Array([
  1, 1, 0, -1, 1, 0, 1, -1, 0, -1, -1, 0,
  1, 0, 1, -1, 0, 1, 1, 0, -1, -1, 0, -1,
  0, 1, 1, 0, -1, 1, 0, 1, -1, 0, -1, -1,
]);

const F3 = 1 / 3;
const G3 = 1 / 6;

function makeNoise(seed: number) {
  const p = new Uint8Array(256);
  for (let i = 0; i < 256; i++) p[i] = i;

  let s = seed >>> 0;
  const rnd = () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = Math.imul(s ^ (s >>> 15), 1 | s);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  for (let i = 255; i > 0; i--) {
    const j = Math.floor(rnd() * (i + 1));
    const tmp = p[i];
    p[i] = p[j];
    p[j] = tmp;
  }

  const perm = new Uint8Array(512);
  const permMod12 = new Uint8Array(512);
  for (let i = 0; i < 512; i++) {
    perm[i] = p[i & 255];
    permMod12[i] = perm[i] % 12;
  }

  return function noise3(x: number, y: number, z: number): number {
    const sk = (x + y + z) * F3;
    let i = Math.floor(x + sk);
    let j = Math.floor(y + sk);
    let k = Math.floor(z + sk);
    const t = (i + j + k) * G3;
    const x0 = x - (i - t);
    const y0 = y - (j - t);
    const z0 = z - (k - t);

    let i1: number, j1: number, k1: number, i2: number, j2: number, k2: number;
    if (x0 >= y0) {
      if (y0 >= z0) { i1 = 1; j1 = 0; k1 = 0; i2 = 1; j2 = 1; k2 = 0; }
      else if (x0 >= z0) { i1 = 1; j1 = 0; k1 = 0; i2 = 1; j2 = 0; k2 = 1; }
      else { i1 = 0; j1 = 0; k1 = 1; i2 = 1; j2 = 0; k2 = 1; }
    } else {
      if (y0 < z0) { i1 = 0; j1 = 0; k1 = 1; i2 = 0; j2 = 1; k2 = 1; }
      else if (x0 < z0) { i1 = 0; j1 = 1; k1 = 0; i2 = 0; j2 = 1; k2 = 1; }
      else { i1 = 0; j1 = 1; k1 = 0; i2 = 1; j2 = 1; k2 = 0; }
    }

    const x1 = x0 - i1 + G3, y1 = y0 - j1 + G3, z1 = z0 - k1 + G3;
    const x2 = x0 - i2 + 2 * G3, y2 = y0 - j2 + 2 * G3, z2 = z0 - k2 + 2 * G3;
    const x3 = x0 - 1 + 3 * G3, y3 = y0 - 1 + 3 * G3, z3 = z0 - 1 + 3 * G3;

    i &= 255; j &= 255; k &= 255;
    let n = 0;

    let t0 = 0.6 - x0 * x0 - y0 * y0 - z0 * z0;
    if (t0 > 0) {
      const g = permMod12[i + perm[j + perm[k]]] * 3;
      t0 *= t0;
      n += t0 * t0 * (GRAD3[g] * x0 + GRAD3[g + 1] * y0 + GRAD3[g + 2] * z0);
    }
    let t1 = 0.6 - x1 * x1 - y1 * y1 - z1 * z1;
    if (t1 > 0) {
      const g = permMod12[i + i1 + perm[j + j1 + perm[k + k1]]] * 3;
      t1 *= t1;
      n += t1 * t1 * (GRAD3[g] * x1 + GRAD3[g + 1] * y1 + GRAD3[g + 2] * z1);
    }
    let t2 = 0.6 - x2 * x2 - y2 * y2 - z2 * z2;
    if (t2 > 0) {
      const g = permMod12[i + i2 + perm[j + j2 + perm[k + k2]]] * 3;
      t2 *= t2;
      n += t2 * t2 * (GRAD3[g] * x2 + GRAD3[g + 1] * y2 + GRAD3[g + 2] * z2);
    }
    let t3 = 0.6 - x3 * x3 - y3 * y3 - z3 * z3;
    if (t3 > 0) {
      const g = permMod12[i + 1 + perm[j + 1 + perm[k + 1]]] * 3;
      t3 *= t3;
      n += t3 * t3 * (GRAD3[g] * x3 + GRAD3[g + 1] * y3 + GRAD3[g + 2] * z3);
    }
    return 32 * n;
  };
}

const BLOB_COLORS = [
  [21, 166, 151],
  [14, 133, 121],
  [51, 188, 173],
  [10, 106, 95],
  [91, 206, 195],
  [21, 166, 151],
];

interface Blob {
  seed: number;
  rgb: number[];
  radius: number;
  alpha: number;
  drift: number;
  dx: number;
  dy: number;
}

interface Particle {
  x: number;
  y: number;
  px: number;
  py: number;
  vx: number;
  vy: number;
  life: number;
  maxLife: number;
}

export interface FluidOptions {
  /** low-res canvas that carries the liquid mesh (blurred via CSS) */
  blobCanvas: HTMLCanvasElement;
  /** full-res canvas for the flow particles, null to disable the layer */
  flowCanvas?: HTMLCanvasElement | null;
  /** element whose pointer moves push the fluid around */
  pointerTarget?: HTMLElement | null;
  blobs?: number;
  particles?: number;
  /** multiplies every velocity in the system */
  speed?: number;
  blobAlpha?: number;
  flowAlpha?: number;
  seed?: number;
}

/** Starts the simulation. Returns a stop function that fully tears it down. */
export function startFluid(opts: FluidOptions): () => void {
  const {
    blobCanvas,
    flowCanvas = null,
    pointerTarget = null,
    blobs: blobCount = 6,
    particles: particleCount = 1400,
    speed = 1,
    blobAlpha = 0.55,
    flowAlpha = 0.18,
    seed = 1337,
  } = opts;

  const blobCtx = blobCanvas.getContext("2d");
  if (!blobCtx) return () => {};
  const flowCtx = flowCanvas ? flowCanvas.getContext("2d") : null;

  const noise3 = makeNoise(seed);
  const host = blobCanvas.parentElement;

  const reduced =
    typeof window !== "undefined" &&
    window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* ── sizing ───────────────────────────────────────────── */

  const BLOB_SCALE = 0.16; // liquid layer renders tiny then gets upscaled + blurred
  let cssW = 0;
  let cssH = 0;
  let flowDpr = 1;

  function resize() {
    const rect = host?.getBoundingClientRect();
    // A zero-size host means the panel is display:none (the right canvas below
    // the mobile breakpoint) or not laid out yet. Go dormant instead of drawing
    // against stale dimensions.
    if (!rect || rect.width < 2 || rect.height < 2) {
      cssW = 0;
      cssH = 0;
      return;
    }
    cssW = rect.width;
    cssH = rect.height;

    blobCanvas.width = Math.max(1, Math.round(cssW * BLOB_SCALE));
    blobCanvas.height = Math.max(1, Math.round(cssH * BLOB_SCALE));

    if (flowCanvas && flowCtx) {
      flowDpr = Math.min(window.devicePixelRatio || 1, 2);
      flowCanvas.width = Math.max(1, Math.round(cssW * flowDpr));
      flowCanvas.height = Math.max(1, Math.round(cssH * flowDpr));
      flowCtx.setTransform(flowDpr, 0, 0, flowDpr, 0, 0);
      flowCtx.clearRect(0, 0, cssW, cssH);
    }
  }
  resize();

  /* ── state ────────────────────────────────────────────── */

  const blobList: Blob[] = [];
  for (let i = 0; i < blobCount; i++) {
    blobList.push({
      seed: i * 17.31 + 4.7,
      rgb: BLOB_COLORS[i % BLOB_COLORS.length],
      radius: 0.17 + (i % 3) * 0.075,
      alpha: blobAlpha * (0.65 + ((i * 37) % 10) / 22),
      drift: 0.055 + (i % 4) * 0.014,
      dx: 0,
      dy: 0,
    });
  }

  const particleList: Particle[] = [];
  function spawn(p: Particle) {
    p.x = Math.random() * cssW;
    p.y = Math.random() * cssH;
    p.px = p.x;
    p.py = p.y;
    p.vx = 0;
    p.vy = 0;
    p.maxLife = 140 + Math.random() * 320;
    p.life = p.maxLife;
  }
  if (flowCtx) {
    for (let i = 0; i < particleCount; i++) {
      const p: Particle = { x: 0, y: 0, px: 0, py: 0, vx: 0, vy: 0, life: 0, maxLife: 1 };
      spawn(p);
      p.life = Math.random() * p.maxLife;
      particleList.push(p);
    }
  }

  /* ── pointer ──────────────────────────────────────────── */

  let pointerX = -9999;
  let pointerY = -9999;
  let pointerPower = 0;

  function onPointer(e: PointerEvent) {
    const rect = host?.getBoundingClientRect();
    if (!rect) return;
    pointerX = e.clientX - rect.left;
    pointerY = e.clientY - rect.top;
    pointerPower = 1;
  }
  function onPointerLeave() {
    pointerPower = 0;
  }
  if (pointerTarget) {
    pointerTarget.addEventListener("pointermove", onPointer, { passive: true });
    pointerTarget.addEventListener("pointerleave", onPointerLeave, { passive: true });
  }

  /* ── render ───────────────────────────────────────────── */

  let t = 0;

  function drawBlobs() {
    if (!blobCtx || !cssW || !cssH) return;
    const w = blobCanvas.width;
    const h = blobCanvas.height;
    blobCtx.clearRect(0, 0, w, h);
    blobCtx.globalCompositeOperation = "source-over";

    const pxN = (pointerX / (cssW || 1)) * w;
    const pyN = (pointerY / (cssH || 1)) * h;
    const reach = Math.min(w, h) * 0.7;

    for (const b of blobList) {
      const nx = noise3(b.seed, 0, t * b.drift);
      const ny = noise3(0, b.seed, t * b.drift);
      const nr = noise3(b.seed, b.seed, t * b.drift * 1.7);

      let cx = (0.5 + nx * 0.46) * w;
      let cy = (0.5 + ny * 0.46) * h;

      // pointer pushes the liquid away, then it eases back
      if (pointerPower > 0.01) {
        const dx = cx - pxN;
        const dy = cy - pyN;
        const d = Math.hypot(dx, dy) || 1;
        if (d < reach) {
          const push = (1 - d / reach) * reach * 0.22 * pointerPower;
          b.dx += ((dx / d) * push - b.dx) * 0.06;
          b.dy += ((dy / d) * push - b.dy) * 0.06;
        }
      }
      b.dx *= 0.965;
      b.dy *= 0.965;
      cx += b.dx;
      cy += b.dy;

      const r = Math.min(w, h) * b.radius * (1 + nr * 0.28);
      const [cr, cg, cb] = b.rgb;
      const grad = blobCtx.createRadialGradient(cx, cy, 0, cx, cy, r);
      grad.addColorStop(0, `rgba(${cr},${cg},${cb},${b.alpha})`);
      grad.addColorStop(0.4, `rgba(${cr},${cg},${cb},${b.alpha * 0.5})`);
      grad.addColorStop(0.75, `rgba(${cr},${cg},${cb},${b.alpha * 0.12})`);
      grad.addColorStop(1, `rgba(${cr},${cg},${cb},0)`);
      blobCtx.fillStyle = grad;
      blobCtx.beginPath();
      blobCtx.arc(cx, cy, r, 0, Math.PI * 2);
      blobCtx.fill();
    }
  }

  function drawFlow() {
    if (!flowCtx || !cssW || !cssH) return;

    // erase trails without painting a background, so the blob layer stays visible
    flowCtx.globalCompositeOperation = "destination-out";
    flowCtx.fillStyle = "rgba(0,0,0,0.085)";
    flowCtx.fillRect(0, 0, cssW, cssH);
    flowCtx.globalCompositeOperation = "source-over";

    const fieldScale = 0.0011;
    const reach = Math.min(cssW, cssH) * 0.35;

    flowCtx.lineCap = "round";
    flowCtx.beginPath();

    for (const p of particleList) {
      const a = noise3(p.x * fieldScale, p.y * fieldScale, t * 0.06) * Math.PI * 2;
      p.vx += Math.cos(a) * 0.22 * speed;
      p.vy += Math.sin(a) * 0.22 * speed;

      if (pointerPower > 0.01) {
        const dx = p.x - pointerX;
        const dy = p.y - pointerY;
        const d = Math.hypot(dx, dy) || 1;
        if (d < reach) {
          // tangential, not radial: a radial push draws visible starburst rays
          const push = (1 - d / reach) * 0.32 * pointerPower;
          p.vx += (-dy / d) * push + (dx / d) * push * 0.35;
          p.vy += (dx / d) * push + (dy / d) * push * 0.35;
        }
      }

      p.vx *= 0.93;
      p.vy *= 0.93;
      p.px = p.x;
      p.py = p.y;
      p.x += p.vx;
      p.y += p.vy;
      p.life--;

      if (
        p.life <= 0 ||
        p.x < -40 || p.x > cssW + 40 ||
        p.y < -40 || p.y > cssH + 40
      ) {
        spawn(p);
        continue;
      }

      flowCtx.moveTo(p.px, p.py);
      flowCtx.lineTo(p.x, p.y);
    }

    flowCtx.strokeStyle = `rgba(14,133,121,${flowAlpha})`;
    flowCtx.lineWidth = 0.9;
    flowCtx.stroke();
  }

  function frame() {
    t += 0.9 * speed;
    pointerPower *= 0.985;
    drawBlobs();
    drawFlow();
    animId = requestAnimationFrame(frame);
  }

  /* ── lifecycle ────────────────────────────────────────── */

  let animId = 0;
  let visible = true;
  let onScreen = true;

  function play() {
    if (reduced || animId || !visible || !onScreen) return;
    animId = requestAnimationFrame(frame);
  }
  function pause() {
    if (!animId) return;
    cancelAnimationFrame(animId);
    animId = 0;
  }

  function onVisibility() {
    visible = !document.hidden;
    if (visible) play();
    else pause();
  }
  document.addEventListener("visibilitychange", onVisibility);

  let io: IntersectionObserver | null = null;
  if (host && typeof IntersectionObserver !== "undefined") {
    io = new IntersectionObserver((entries) => {
      onScreen = entries.some((en) => en.isIntersecting);
      if (onScreen) play();
      else pause();
    });
    io.observe(host);
  }

  function onResize() {
    const wasDormant = cssW === 0;
    resize();
    // particles spawned while the host had no size are all piled at the origin
    if (wasDormant && cssW > 0) for (const p of particleList) spawn(p);
    // resizing wipes the canvas, so reduced-motion needs its static frame back
    if (reduced) drawBlobs();
  }

  let ro: ResizeObserver | null = null;
  if (host && typeof ResizeObserver !== "undefined") {
    ro = new ResizeObserver(onResize);
    ro.observe(host);
  } else {
    window.addEventListener("resize", onResize);
  }

  if (reduced) {
    // one static composed frame, no loop
    t = 12;
    drawBlobs();
  } else {
    play();
  }

  return () => {
    pause();
    // wipe both layers so a rebuild does not start on top of stale trails
    if (cssW > 0) {
      blobCtx.clearRect(0, 0, blobCanvas.width, blobCanvas.height);
      flowCtx?.clearRect(0, 0, cssW, cssH);
    }
    document.removeEventListener("visibilitychange", onVisibility);
    io?.disconnect();
    ro?.disconnect();
    if (!ro) window.removeEventListener("resize", onResize);
    if (pointerTarget) {
      pointerTarget.removeEventListener("pointermove", onPointer);
      pointerTarget.removeEventListener("pointerleave", onPointerLeave);
    }
    particleList.length = 0;
    blobList.length = 0;
  };
}
