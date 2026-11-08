(function () {
  const NS = 'http://www.w3.org/2000/svg';
  const el = (n, a, p) => { const e = document.createElementNS(NS, n); for (const k in a) e.setAttribute(k, a[k]); p && p.appendChild(e); return e; };
  const txt = (p, x, y, s, o) => { const t = el('text', Object.assign({ x, y, 'font-family': 'Poppins, sans-serif', 'font-size': 11, fill: '#5A6B68' }, o || {}), p); t.textContent = s; return t; };
  const id = n => n.toLocaleString('id-ID', { maximumFractionDigits: 1, minimumFractionDigits: 1 });

  // sparkline: data-spark="1,2,3" data-color data-area
  document.querySelectorAll('svg.spark').forEach((s, n) => {
    const v = s.dataset.spark.split(',').map(Number), W = +s.getAttribute('width'), H = +s.getAttribute('height');
    const mn = Math.min(...v), mx = Math.max(...v), X = i => 2 + (W - 6) * i / (v.length - 1), Y = a => 3 + (H - 8) * (1 - (a - mn) / (mx - mn || 1));
    const d = v.map((a, i) => (i ? 'L' : 'M') + X(i).toFixed(1) + ' ' + Y(a).toFixed(1)).join(' ');
    if (s.dataset.area) {
      const g = el('linearGradient', { id: 'spk' + n + Math.random().toString(36).slice(2, 6), x1: 0, y1: 0, x2: 0, y2: 1 }, el('defs', {}, s));
      el('stop', { offset: 0, 'stop-color': s.dataset.color, 'stop-opacity': .2 }, g); el('stop', { offset: 1, 'stop-color': s.dataset.color, 'stop-opacity': 0 }, g);
      el('path', { d: d + ` L${X(v.length - 1)} ${H} L${X(0)} ${H} Z`, fill: `url(#${g.id})` }, s);
    }
    el('path', { d, fill: 'none', stroke: s.dataset.color, 'stroke-width': 2, 'stroke-linecap': 'round', 'stroke-linejoin': 'round' }, s);
    el('circle', { cx: X(v.length - 1), cy: Y(v[v.length - 1]), r: 3, fill: s.dataset.color }, s);
  });

  // audio waveform: <div class="wave" data-wave="48">
  document.querySelectorAll('[data-wave]').forEach(w => {
    const n = +w.dataset.wave; let h = '';
    for (let i = 0; i < n; i++) { const a = 8 + Math.round(26 * Math.abs(Math.sin(i * 1.7) * Math.cos(i * .45))); h += `<i class="${i < n * .38 ? 'p' : ''}" style="height:${a}px"></i>`; }
    w.innerHTML = h;
  });

  // waterfall: data-wf='[{"l":"Okt","v":412.6,"t":"total"},{"l":"Garut","v":-9.8}, ...,{"l":"Nov","t":"end"}]' data-min data-max data-unit
  document.querySelectorAll('svg[data-wf]').forEach(svg => {
    const rows = JSON.parse(svg.dataset.wf), W = +svg.getAttribute('width'), H = +svg.getAttribute('height');
    const lo = +svg.dataset.min, hi = +svg.dataset.max, pl = 8, pr = 8, pt = 26, pb = 46, iw = W - pl - pr, ih = H - pt - pb;
    const Y = v => pt + ih * (1 - (v - lo) / (hi - lo)), bw = iw / rows.length;
    // axis break note: the scale starts at data-min, shown with a zig-zag on totals
    let run = 0;
    rows.forEach((r, i) => {
      const x = pl + bw * i + bw * .16, w = bw * .68; let a, b, c, lab;
      if (r.t === 'total') { run = r.v; a = lo; b = r.v; c = '#0F3A35'; lab = id(r.v); }
      else if (r.t === 'end') { a = lo; b = run; c = '#0E8579'; lab = id(run); }
      else { a = run; b = run + r.v; run = b; c = r.v < 0 ? '#C42B2B' : '#2FA84F'; lab = (r.v > 0 ? '+' : '−') + id(Math.abs(r.v)); }
      const y1 = Y(Math.max(a, b)), y2 = Y(Math.min(a, b));
      el('rect', { x, y: y1, width: w, height: Math.max(2, y2 - y1), rx: 4, fill: c, opacity: r.dim ? .45 : 1 }, svg);
      if (r.t === 'total' || r.t === 'end') { el('path', { d: `M${x} ${Y(lo) - 10} l${w / 4} -5 l${w / 4} 5 l${w / 4} -5 l${w / 4} 5`, stroke: '#fff', 'stroke-width': 2, fill: 'none' }, svg); }
      if (i < rows.length - 1 && rows[i + 1].t !== 'end') el('line', { x1: x + w, x2: x + bw, y1: Y(run), y2: Y(run), stroke: '#9FB1AD', 'stroke-dasharray': '3 3' }, svg);
      txt(svg, x + w / 2, y1 - 7, lab, { 'text-anchor': 'middle', 'font-size': 11.5, 'font-weight': 600, fill: r.t ? '#0F1F1D' : c });
      const parts = r.l.split('|');
      parts.forEach((p, k) => txt(svg, x + w / 2, H - pb + 18 + k * 13, p, { 'text-anchor': 'middle', 'font-size': k ? 10 : 11, fill: k ? '#8A9A97' : '#3D4C49', 'font-weight': r.t ? 600 : 500 }));
    });
    el('line', { x1: pl, x2: W - pr, y1: Y(lo), y2: Y(lo), stroke: '#B9C6C3' }, svg);
  });

  // forecast fan (cumulative): data-fan='{"days":30,"today":4,"act":[...],"mid":[...],"lo":[...],"hi":[...],"target":1900,"max":2100}'
  document.querySelectorAll('svg[data-fan]').forEach((svg, n) => {
    const f = JSON.parse(svg.dataset.fan), W = +svg.getAttribute('width'), H = +svg.getAttribute('height');
    const pl = 52, pr = f.pr || 70, pt = 14, pb = 30, iw = W - pl - pr, ih = H - pt - pb;
    const mn = f.min || 0, X = d => pl + iw * (d - 1) / (f.days - 1), Y = v => pt + ih * (1 - (v - mn) / (f.max - mn));
    f.ticks.forEach(t => { el('line', { x1: pl, x2: W - pr, y1: Y(t), y2: Y(t), stroke: t ? '#ECF3F1' : '#B9C6C3' }, svg); txt(svg, pl - 8, Y(t) + 4, (t > 0 && f.signed ? '+' : '') + t.toLocaleString('id-ID').replace('-', '−'), { 'text-anchor': 'end' }); });
    [1, 8, 15, 22, 30].forEach(d => txt(svg, X(d), H - 8, d + ' Nov', { 'text-anchor': 'middle' }));
    const s0 = f.today, band = f.mid.map((_, i) => [s0 + i, f.lo[i], f.hi[i]]);
    el('path', { d: band.map(([d, l], i) => (i ? 'L' : 'M') + X(d) + ' ' + Y(l)).join(' ') + ' ' + band.slice().reverse().map(([d, , h]) => 'L' + X(d) + ' ' + Y(h)).join(' ') + 'Z', fill: f.color || '#0E8579', opacity: .14 }, svg);
    if (f.alt) el('path', { d: f.alt.map((v, i) => (i ? 'L' : 'M') + X(s0 + i) + ' ' + Y(v)).join(' '), fill: 'none', stroke: '#6A4CB5', 'stroke-width': 2.5, 'stroke-dasharray': '7 5' }, svg);
    el('path', { d: f.mid.map((v, i) => (i ? 'L' : 'M') + X(s0 + i) + ' ' + Y(v)).join(' '), fill: 'none', stroke: f.color || '#0E8579', 'stroke-width': 2, 'stroke-dasharray': '5 5' }, svg);
    el('path', { d: f.act.map((v, i) => (i ? 'L' : 'M') + X(i + 1) + ' ' + Y(v)).join(' '), fill: 'none', stroke: f.color || '#0E8579', 'stroke-width': 3, 'stroke-linecap': 'round' }, svg);
    el('circle', { cx: X(s0), cy: Y(f.act[s0 - 1]), r: 5, fill: '#fff', stroke: f.color || '#0E8579', 'stroke-width': 2.5 }, svg);
    el('line', { x1: X(s0), x2: X(s0), y1: pt, y2: pt + ih, stroke: '#0F1F1D', 'stroke-dasharray': '2 3', opacity: .5 }, svg);
    txt(svg, X(s0) + 6, pt + 10, 'Hari ini', { 'font-size': 10.5, 'font-weight': 600, fill: '#0F1F1D' });
    el('line', { x1: pl, x2: W - pr, y1: Y(f.target), y2: Y(f.target), stroke: '#C42B2B', 'stroke-width': 1.5 }, svg);
    txt(svg, W - pr + 6, Y(f.target) + 4, f.targetLabel || 'Target', { 'font-size': 11, 'font-weight': 700, fill: '#C42B2B' });
    const last = f.mid.length - 1;
    txt(svg, W - pr + 6, Y(f.mid[last]) + 4 + (f.midDy || 0), f.midLabel || '', { 'font-size': 11, 'font-weight': 700, fill: f.color || '#0E8579' });
    if (f.alt) txt(svg, W - pr + 6, Y(f.alt[f.alt.length - 1]) - 4, f.altLabel || '', { 'font-size': 11, 'font-weight': 700, fill: '#6A4CB5' });
  });
})();
