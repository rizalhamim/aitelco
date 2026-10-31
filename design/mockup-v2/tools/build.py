"""Assemble a FigCraft (.figcraft) file from extract.js output.

usage: python3 build.py tree.json out.figcraft "Doc name" "Page name" poster.jpg thumb.png
A .figcraft file is a zip of document.json + images/<sha256> (+ thumbnail.png).
"""
import hashlib, json, math, re, sys, zipfile
from PIL import Image

tree_path, out_path, doc_name, page_name, poster_path, thumb_path = sys.argv[1:7]
frames = json.load(open(tree_path))

nodes, images = {}, {}
next_id = [1]


def nid():
    i = next_id[0]; next_id[0] += 1; return i


def add_image(path):
    data = open(path, 'rb').read()
    h = hashlib.sha256(data).hexdigest()
    if h not in images:
        w, hgt = Image.open(path).size
        images[h] = (data, w, hgt)
    return h


def parse_color(s):
    if not s:
        return None
    m = re.match(r'rgba?\(([^)]+)\)', s.strip())
    if not m:
        return None
    p = [float(x) for x in re.split(r'[ ,/]+', m.group(1).strip()) if x]
    a = p[3] if len(p) > 3 else 1.0
    return {"r": p[0] / 255, "g": p[1] / 255, "b": p[2] / 255, "a": a}


def solid(c, opacity=1.0):
    return {"type": "solid", "color": c, "opacity": opacity, "visible": True, "blend": "normal"}


def split_top(s):
    out, depth, cur = [], 0, ''
    for ch in s:
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
        if ch == ',' and depth == 0:
            out.append(cur.strip()); cur = ''
        else:
            cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out


def stops_of(parts):
    st = []
    for p in parts:
        m = re.match(r'(rgba?\([^)]*\))\s*([\d.]+%)?', p)
        if not m:
            continue
        st.append([parse_color(m.group(1)), float(m.group(2)[:-1]) / 100 if m.group(2) else None])
    if st and st[0][1] is None:
        st[0][1] = 0.0
    if st and st[-1][1] is None:
        st[-1][1] = 1.0
    i = 0
    while i < len(st):
        if st[i][1] is None:
            j = i
            while st[j][1] is None:
                j += 1
            a, b = st[i - 1][1], st[j][1]
            for k in range(i, j):
                st[k][1] = a + (b - a) * (k - i + 1) / (j - i + 1)
            i = j
        i += 1
    return [{"position": p, "color": c} for c, p in st]


def gradients(bg_image, w, h):
    if not bg_image or bg_image == 'none':
        return []
    out = []
    for layer in split_top(bg_image):
        m = re.match(r'(linear|radial)-gradient\((.*)\)$', layer, re.S)
        if not m:
            continue
        kind, body = m.group(1), split_top(m.group(2))
        w, h = max(w, 1), max(h, 1)
        if kind == 'linear':
            ang = 180.0
            if body and re.match(r'^-?[\d.]+deg$', body[0]):
                ang = float(body[0][:-3]); body = body[1:]
            elif body and body[0].startswith('to '):
                ang = {'to right': 90, 'to left': 270, 'to top': 0, 'to bottom': 180}.get(body[0], 180); body = body[1:]
            t = math.radians(ang)
            L = abs(w * math.sin(t)) + abs(h * math.cos(t))
            dx, dy = math.sin(t) * L / 2 / w, -math.cos(t) * L / 2 / h
            fr, to = [0.5 - dx, 0.5 - dy], [0.5 + dx, 0.5 + dy]
            vx, vy = to[0] - fr[0], to[1] - fr[1]
            width = [fr[0] - vy, fr[1] + vx]
        else:
            if body and not body[0].startswith('rgb'):
                body = body[1:]
            R = math.hypot(w, h) / 2
            fr, to, width = [0.5, 0.5], [0.5, 0.5 + R / h], [0.5 + R / w, 0.5]
        out.append({"type": "gradient", "kind": kind, "stops": stops_of(body), "from": fr, "to": to, "width": width,
                    "opacity": 1.0, "visible": True, "blend": "normal"})
    return list(reversed(out))  # CSS lists top layer first; FigCraft paints first fill at the bottom


def shadows(s):
    if not s or s == 'none':
        return []
    eff = []
    for part in split_top(s):
        if 'inset' in part:
            continue
        m = re.match(r'(rgba?\([^)]*\))\s+(-?[\d.]+)px\s+(-?[\d.]+)px\s+([\d.]+)px(?:\s+(-?[\d.]+)px)?', part)
        if not m:
            continue
        eff.append({"type": "dropShadow", "color": parse_color(m.group(1)), "offset": [float(m.group(2)), float(m.group(3))],
                    "radius": float(m.group(4)), "spread": float(m.group(5) or 0), "blend": "normal", "show_behind": False, "visible": True})
    return eff


WEIGHT = {100: 'Thin', 200: 'ExtraLight', 300: 'Light', 400: 'Regular', 500: 'Medium', 600: 'SemiBold', 700: 'Bold', 800: 'ExtraBold', 900: 'Black'}
FONT_MAP = {'Prompt': 'Poppins', 'Segoe UI': 'Poppins', 'system-ui': 'Poppins'}
GRADIENT_TEXT = {"r": 199 / 255, "g": 242 / 255, "b": 94 / 255, "a": 1.0}


def tstyle(st):
    size = st['size']
    lh = st['lh'] / size * 100 if st.get('lh') else 150.0
    return {"font_family": FONT_MAP.get(st['family'], st['family']), "font_style": WEIGHT.get(int(round(st['weight'] / 100) * 100), 'Regular'),
            "font_size": round(size, 2), "line_height": {"unit": "percent", "value": round(lh, 1)},
            "letter_spacing": {"unit": "percent", "value": round(st.get('ls', 0) / size * 100, 2)}, "decoration": "none",
            "case": "upper" if st.get('transform') == 'uppercase' else "original", "fills": None, "link": None}


def run_color(st):
    if st.get('clip'):
        return GRADIENT_TEXT
    return parse_color(st['color'])


def text_node(parent, name, runs, x, y, w, h, align=None):
    chars = ''.join(r['text'] for r in runs)
    base = runs[0]['style']
    for r in runs:
        if r['text'].strip():
            base = r['style']; break
    bcol = run_color(base)
    out_runs, pos = [], 0
    for r in runs:
        n = len(r['text'])
        st = r['style']
        if (st['weight'], st['size'], st['color'], st.get('clip')) != (base['weight'], base['size'], base['color'], base.get('clip')) and r['text'].strip():
            s = tstyle(st)
            c = run_color(st)
            if c != bcol:
                s['fills'] = [solid({**c, "a": 1.0}, c['a'])]
            out_runs.append({"start": pos, "end": pos + n, "style": s})
        pos += n
    i = nid()
    node = {"id": i, "name": name or chars[:40], "type": "text", "characters": chars, "style": tstyle(base), "parent": parent, "blend": "normal",
            "transform": [1.0, 0.0, 0.0, 1.0, round(x, 2), round(y, 2)], "width": round(w + 1.5, 2), "height": round(h, 2),
            "fills": [solid({**bcol, "a": 1.0}, bcol['a'])]}
    if out_runs:
        node["runs"] = out_runs
    lh_px = tstyle(base)["line_height"]["value"] / 100 * base["size"]
    if h > lh_px * 1.6 and '\n' not in chars:
        node["auto_resize"] = "height"
    if align in ('center', 'right'):
        node["align_h"] = align
    nodes[str(i)] = node
    return i


def is_plain(n):
    c = parse_color(n['bg'])
    return (not c or c['a'] == 0) and (n['bgImage'] in ('none', None)) and not n['border'].get('w') and (n.get('shadow') in ('none', None))


def build(n, parent, raster_files, poster_hash, ox=0.0, oy=0.0):
    x, y = n['x'] + ox, n['y'] + oy
    t = n.get('text')
    if t and not n['children'] and is_plain(n) and 'raster' not in n:
        tx, ty = x + t.get('x', 0), y + t.get('y', 0)
        tw, th = t.get('w', n['w']), t.get('h', n['h'])
        if 'x' not in t:  # input: vertically centre one line
            st = t['runs'][0]['style']; th = st['size'] * 1.5; ty = y + (n['h'] - th) / 2; tw = n['w'] - 2
        return text_node(parent, n['name'] if n['tag'] == 'input' else None, t['runs'], tx, ty, tw, th, t['runs'][0]['style'].get('align'))
    i = nid()
    fills = []
    c = parse_color(n['bg'])
    if c and c['a'] > 0:
        fills.append(solid({**c, "a": 1.0}, c['a']))
    fills += gradients(n['bgImage'], n['w'], n['h'])
    node = {"id": i, "name": n['name'], "type": "frame", "parent": parent, "transform": [1.0, 0.0, 0.0, 1.0, round(x, 2), round(y, 2)],
            "width": round(n['w'], 2), "height": round(n['h'], 2), "fills": fills, "children": []}
    if n.get('video'):
        node['name'] = 'Video latar (autoplay, loop, tanpa suara)'
        node['fills'] = [{"type": "image", "image": poster_hash, "scale_mode": "fill", "scale": 1.0, "rotation": 0, "crop": None,
                          "filters": {k: 0.0 for k in ("exposure", "contrast", "saturation", "temperature", "tint", "highlights", "shadows")},
                          "opacity": 1.0, "visible": True, "blend": "normal"}]
        node['annotations'] = [{"label": "VIDEO: media/login-1080-h264.mp4 (H.264, 15 dtk, 7,8 MB). <video autoplay muted loop playsinline>, object-fit: cover, poster = frame ini. "
                                         "FigCraft tidak bisa memutar video; lihat versi yang jalan di halaman review HTML. Hormati prefers-reduced-motion (tampilkan poster saja)."}]
    if n.get('raster'):
        h = add_image(raster_files[n['raster']])
        node['fills'] = [{"type": "image", "image": h, "scale_mode": "fit", "scale": 1.0, "rotation": 0, "crop": None,
                          "filters": {k: 0.0 for k in ("exposure", "contrast", "saturation", "temperature", "tint", "highlights", "shadows")},
                          "opacity": 1.0, "visible": True, "blend": "normal"}]
        node['name'] = 'Ikon' if n['w'] < 30 else ('Logo Agent Java' if n['w'] >= 30 else n['name'])
    if any(n['radius']):
        node['corners'] = {"radii": [round(min(r, n['w'] / 2, n['h'] / 2), 2) for r in n['radius']], "smoothing": 0.0}
    bw = n['border'].get('w') or 0
    bc = parse_color(n['border'].get('color'))
    if bw and bc and bc['a'] > 0 and n['border'].get('style') != 'none':
        node['strokes'] = [solid({**bc, "a": 1.0}, bc['a'])]
        node['stroke'] = {"weight": bw, "align": "inside", "sides": None, "cap_start": "none", "cap_end": "none", "join": "miter", "miter_limit": 4.0, "dashes": []}
    eff = []
    m = re.search(r'blur\(([\d.]+)px\)', n.get('backdrop') or '')
    if m:
        eff.append({"type": "backgroundBlur", "radius": float(m.group(1)), "blur_type": "uniform", "start_radius": 0.0, "start": [0.5, 0.0], "end": [0.5, 1.0], "visible": True})
    eff += shadows(n.get('shadow'))
    if eff:
        node['effects'] = eff
    if n.get('opacity', 1) < 1:
        node['opacity'] = n['opacity']
    if n.get('clip'):
        node['clip'] = True
    nodes[str(i)] = node
    if t:  # box with its own text (chips, swatches, buttons)
        tx, ty = t.get('x', 0), t.get('y', 0)
        node['children'].append(text_node(i, None, t['runs'], tx, ty, t.get('w', n['w']), t.get('h', n['h']), t['runs'][0]['style'].get('align')))
    for ch in n['children']:
        node['children'].append(build(ch, i, raster_files, poster_hash))
    return i


page_id = nid()
poster_hash = add_image(poster_path)
page = {"id": page_id, "name": page_name, "type": "page", "background": {"r": 0.8627451, "g": 0.9019608, "b": 0.89411765, "a": 1.0},
        "flows": [], "prototype": {"device": "None", "background": {"r": 0.11764706, "g": 0.11764706, "b": 0.11764706, "a": 1.0}, "rotation": "portrait"},
        "guides": [], "width": 0.0, "height": 0.0, "children": []}
nodes[str(page_id)] = page
FRAME_NAMES = {'#webFrame': 'Web · Login', '#droidFrame': 'Android · Login', '#brandFrame': 'Brand · Logo dan warna'}
cursor = 0.0
for f in frames:
    raster_files = {r['id']: r['file'] for r in f['rasters']}
    root = f['tree']
    root['name'] = FRAME_NAMES.get(f['sel'], f['sel'])
    root['x'], root['y'] = cursor, 0.0
    fid = build(root, page_id, raster_files, poster_hash)
    nodes[str(fid)]['clip'] = True
    if f['sel'] == '#droidFrame':
        nodes[str(fid)]['annotations'] = [{"label": "Bingkai HP 10 px (stroke) hanya untuk presentasi. Area layar 370 × 824."}]
    page['children'].append(fid)
    cursor += root['w'] + 120

doc = {"format": "figcraft", "version": 1,
       "imageIndex": [{"hash": h, "width": w, "height": hh} for h, (_, w, hh) in sorted(images.items())],
       "name": doc_name, "pages": [page_id], "nodes": nodes, "next_id": next_id[0], "styles": [],
       "variables": {"collections": [], "variables": []}, "current_page": page_id, "document_colors": [], "comments": []}

with zipfile.ZipFile(out_path, 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('document.json', json.dumps(doc, ensure_ascii=False))
    for h, (data, _, _) in sorted(images.items()):
        z.writestr('images/' + h, data)
    z.write(thumb_path, 'thumbnail.png')
print('nodes', len(nodes), 'images', len(images), 'frames', len(page['children']))
