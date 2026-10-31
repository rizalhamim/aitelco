# Render a .figcraft back to HTML (absolute boxes) to sanity-check the export.
import json, sys, zipfile, base64
z = zipfile.ZipFile(sys.argv[1]); d = json.loads(z.read('document.json')); N = d['nodes']
def col(c, o=1): return f"rgba({c['r']*255:.0f},{c['g']*255:.0f},{c['b']*255:.0f},{c['a']*o:.3f})"
def paint(f, w, h):
    if f['type'] == 'solid': return f"linear-gradient({col(f['color'], f['opacity'])},{col(f['color'], f['opacity'])})"
    if f['type'] == 'image':
        data = base64.b64encode(z.read('images/' + f['image'])).decode()
        return f"url(data:image/png;base64,{data}) center/{'cover' if f['scale_mode']=='fill' else 'contain'} no-repeat"
    st = ','.join(f"{col(s['color'])} {s['position']*100:.1f}%" for s in f['stops'])
    if f['kind'] == 'radial': return f"radial-gradient(circle, {st})"
    import math
    dx = (f['to'][0]-f['from'][0])*w; dy = (f['to'][1]-f['from'][1])*h
    return f"linear-gradient({math.degrees(math.atan2(dx, -dy)):.1f}deg, {st})"
def node(i):
    n = N[str(i)]; t = n.get('transform', [1,0,0,1,0,0])
    s = f"position:absolute;left:{t[4]}px;top:{t[5]}px;width:{n['width']}px;height:{n['height']}px;"
    if n['type'] == 'text':
        st = n['style']; c = n['fills'][0]
        w = {'Regular':400,'Medium':500,'SemiBold':600,'Bold':700,'ExtraBold':800}[st['font_style']]
        s += f"font-family:{st['font_family']};font-weight:{w};font-size:{st['font_size']}px;line-height:{st['line_height']['value']}%;letter-spacing:{st['letter_spacing']['value']/100}em;color:{col(c['color'], c['opacity'])};white-space:pre;text-align:{n.get('align_h','left')}"
        chars = n['characters']; out = ''; pos = 0
        for r in n.get('runs', []):
            out += chars[pos:r['start']]
            rs = r['style']; rc = (rs.get('fills') or [None])[0]
            out += f"<span style=\"font-weight:{ {'Regular':400,'Medium':500,'SemiBold':600,'Bold':700,'ExtraBold':800}[rs['font_style']] };{'color:'+col(rc['color'],rc['opacity']) if rc else ''}\">{chars[r['start']:r['end']]}</span>"
            pos = r['end']
        out += chars[pos:]
        return f'<div style="{s}">{out}</div>'
    bg = ','.join(paint(f, n['width'], n['height']) for f in reversed(n.get('fills') or []))
    if bg: s += f"background:{bg};"
    if n.get('corners'): s += "border-radius:" + ' '.join(f"{r}px" for r in n['corners']['radii']) + ';'
    if n.get('strokes'): s += f"box-shadow:inset 0 0 0 {n['stroke']['weight']}px {col(n['strokes'][0]['color'], n['strokes'][0]['opacity'])};"
    if n.get('clip'): s += 'overflow:hidden;'
    if n.get('opacity') is not None: s += f"opacity:{n['opacity']};"
    sh = [e for e in n.get('effects', []) if e['type'] == 'dropShadow']
    fx = ''.join(f"filter:drop-shadow({e['offset'][0]}px {e['offset'][1]}px {e['radius']/2}px {col(e['color'])});" for e in sh[:1])
    return f'<div style="{s}{fx}">' + ''.join(node(c) for c in n.get('children', [])) + '</div>'
pg = N[str(d['pages'][0])]
html = '<html><head><link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Poppins:wght@400;500;600;700;800&display=swap"></head><body style="margin:0;background:#dce6e4"><div style="position:relative">' + ''.join(node(c) for c in pg['children']) + '</div></body></html>'
open(sys.argv[2], 'w').write(html)
