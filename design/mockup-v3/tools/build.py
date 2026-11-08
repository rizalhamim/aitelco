# Build Agent Java v3 mockups from feature fragments.
#   python3 tools/build.py            -> render/<slug>.html (pixel pages) + review/agent-java-v3.html
#   node tools/shoot.js               -> png/<slug>/{Web,Android} - <title>@2x.png
# Fragment format (features/NN-slug.html):
#   <!--title: ...--> <!--lead: ...--> <!--webH: 1100--> <!--droidH: 844-->
#   <style>...</style>
#   <template id="web">...</template> <template id="droid">...</template> <template id="notes">...</template>
# Macros inside web/droid: {{SIDE:key}} {{TOP:title|subtitle}} {{STATUS}} {{DBAR:title|subtitle}} {{BNAV:key}} {{LOGO}}
import base64, glob, html, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
B = os.path.join(ROOT, '_base')
read = lambda p: open(p, encoding='utf-8').read()

DRAW = '<script>' + read(os.path.join(B, 'draw.js')) + '</script>'
FRAME_CSS = read(os.path.join(B, 'frame.css'))
SPRITE = read(os.path.join(B, 'sprite.svg'))
LOGO = 'data:image/png;base64,' + base64.b64encode(open(os.path.join(B, 'logo160.png'), 'rb').read()).decode()

NAV = [  # key, label, tile bg, tile ink, icon, badge ; ('h', title) = group header
    ('h', 'Pantau'),
    ('brief', 'Brief Pagi', '#FFEDE7', '#B5401F', 'i-sun', 'new'),
    ('dash', 'Dashboard', '#E1ECFA', '#2C6CB0', 'i-grid', ''),
    ('ruang', 'Ruang Saya', '#F4FCE3', '#5E8A12', 'i-layers', 'new'),
    ('klas', 'Klasemen', '#FDF3E2', '#B7791F', 'i-bars', 'new'),
    ('h', 'Analisis'),
    ('agent', 'Tanya Agent', '#C0EDE8', '#0A6A5F', 'i-chat', ''),
    ('perf', 'Performance', '#E6F7F5', '#0E8579', 'i-pulse', ''),
    ('target', 'Simulasi Target', '#ECE5FA', '#6A4CB5', 'i-up', 'new'),
    ('map', 'Peta Agent', '#E3F7FA', '#0E6F7C', 'i-map', ''),
    ('h', 'Bertindak'),
    ('alert', 'Watchlist dan Alert', '#FDECEC', '#C42B2B', 'i-bell', 'cnt:3'),
    ('aksi', 'Tindak Lanjut', '#FBE2E8', '#C23A5B', 'i-check', 'cnt:5'),
    ('report', 'Laporan', '#FCEDD3', '#B7791F', 'i-file', ''),
]


def side(active):
    items = []
    for row in NAV:
        if row[0] == 'h':
            items.append(f'<div class="navh">{row[1]}</div>')
            continue
        k, label, bg, ink, ic, badge = row
        b = ''
        if badge == 'new':
            b = '<span class="new">Baru</span>'
        elif badge.startswith('cnt:'):
            b = f'<span class="cnt">{badge[4:]}</span>'
        items.append(f'<a{" class=\"on\"" if k == active else ""}><span class="nt" style="background:{bg};color:{ink}"><svg><use href="#{ic}"/></svg></span>{label}{b}</a>')
    return f'''<aside class="side" data-name="Sidebar">
<div class="brand"><span class="tile" style="width:44px;height:44px;border-radius:13px"><img src="{LOGO}" alt="Logo Agent Java"></span><div><b>Agent <em>Java</em></b><small>Circle Java</small></div></div>
<div class="newchat"><svg class="ic"><use href="#i-plus"/></svg>Percakapan baru</div>
<div class="search"><svg><use href="#i-search"/></svg>Cari cepat<span class="kbd">Ctrl K</span></div>
<nav class="nav">{''.join(items)}</nav>
<div class="spacer"></div>
<div class="me"><span class="avatar">R</span><div><b>Rizal</b><small>Admin · Circle Java</small></div><svg><use href="#i-chev"/></svg></div>
</aside>'''


def top(arg):
    t, s = (arg.split('|') + [''])[:2]
    return f'''<header class="top" data-name="Top bar"><div><h2>{t}</h2><p>{s}</p></div><div class="grow"></div>
<span class="chip teal"><svg><use href="#i-pin"/></svg>Semua region</span><span class="chip"><svg><use href="#i-cal"/></svg>Nov 2026</span>
<span class="btn-ic" aria-label="Alert"><svg class="ic"><use href="#i-bell"/></svg><span class="badge">3</span></span><span class="avatar" aria-label="Profil">R</span></header>'''


STATUS = '<div class="status"><span>9:41</span><span class="cam"></span><span>5G ▮▮▮ 86%</span></div>'


def dbar(arg):
    t, s = (arg.split('|') + [''])[:2]
    return f'''<div class="dbar" data-name="App bar"><span class="tile"><img src="{LOGO}" alt="Logo Agent Java"></span>
<div><b>{t}</b><small><i></i>{s}</small></div><span class="grow"></span>
<span class="btn-ic" aria-label="Alert"><svg class="ic"><use href="#i-bell"/></svg><span class="badge">3</span></span><span class="avatar" aria-label="Profil">R</span></div>'''


BN = [('agent', 'Agent', 'i-spark'), ('dash', 'Dashboard', 'i-grid'), ('perf', 'Performa', 'i-pulse'), ('map', 'Peta', 'i-map'), ('report', 'Laporan', 'i-file')]


def bnav(active):
    return '<nav class="bnav" data-name="Bottom nav">' + ''.join(
        f'<a{" class=\"on\"" if k == active else ""}><i><svg><use href="#{ic}"/></svg></i>{label}</a>' for k, label, ic in BN) + '</nav><div class="homebar"></div>'


def macros(s):
    s = re.sub(r'\{\{SIDE:(\w+)\}\}', lambda m: side(m.group(1)), s)
    s = re.sub(r'\{\{TOP:([^}]*)\}\}', lambda m: top(m.group(1)), s)
    s = re.sub(r'\{\{DBAR:([^}]*)\}\}', lambda m: dbar(m.group(1)), s)
    s = re.sub(r'\{\{BNAV:(\w*)\}\}', lambda m: bnav(m.group(1)), s)
    return s.replace('{{STATUS}}', STATUS).replace('{{LOGO}}', LOGO)


EXTRA_CSS = '''
.frame, .frame * { box-sizing: border-box }
.seg button, .chip, .search .kbd, .nav a { white-space: nowrap }
.search .kbd { margin-left: auto; font: 600 10.5px/1 var(--f-display); padding: 4px 6px; border-radius: 6px; background: #ECF3F1; color: #5A6B68 }
.side { gap: 10px } .nav a { height: 38px } .nav .navh { padding: 12px 6px 6px }
.eb { font: 600 11px/1 var(--f-display); letter-spacing: .1em; text-transform: uppercase; color: #0A6A5F }
.illus { font: 600 10.5px/1 var(--f-display); letter-spacing: .06em; text-transform: uppercase; color: #B7791F; background: #FDF3E2; padding: 5px 8px; border-radius: 99px }
'''


def parse(path):
    t = read(path)
    meta = dict(re.findall(r'<!--(\w+):\s*(.*?)-->', t))
    style = ''.join(re.findall(r'<style>(.*?)</style>', t, re.S))
    tpl = dict(re.findall(r'<template id="(\w+)">(.*?)</template>', t, re.S))
    slug = os.path.basename(path)[:-5]
    return dict(slug=slug, title=meta['title'], lead=meta.get('lead', ''), webH=int(meta.get('webH', 1080)), droidH=int(meta.get('droidH', 844)),
                style=style, web=macros(tpl['web']), droid=macros(tpl['droid']), notes=tpl.get('notes', ''))


def scope(css, slug):
    # prefix every selector of a feature stylesheet with its feature scope, so features never collide in the review page
    out = []
    for m in re.finditer(r'([^{}]+)\{([^{}]*)\}', css):
        sels = ','.join(f'.f-{slug} {s.strip()}' for s in m.group(1).split(',') if s.strip())
        out.append(f'{sels}{{{m.group(2)}}}')
    return '\n'.join(out)


def strip_comments(css):
    return re.sub(r'/\*.*?\*/', '', css, flags=re.S)


feats = [parse(p) for p in sorted(glob.glob(os.path.join(ROOT, 'features', '*.html')))]
os.makedirs(os.path.join(ROOT, 'render'), exist_ok=True)
os.makedirs(os.path.join(ROOT, 'review'), exist_ok=True)
FONT_LOCAL = read(os.path.join(B, 'fonts', 'local.css')).replace('url(fonts/', 'url(../_base/fonts/')
VARS = ':root{--f-display:"Poppins","Segoe UI",system-ui,sans-serif;--f-body:"Prompt","Segoe UI",system-ui,sans-serif}'

for f in feats:
    css = strip_comments(FRAME_CSS) + EXTRA_CSS + scope(strip_comments(f['style']), f['slug'])
    page = f'''<!doctype html><html lang="id"><head><meta charset="utf-8"><title>{html.escape(f['title'])}</title>
<style>{FONT_LOCAL}{VARS} body{{margin:0;background:#fff}} .wrap{{display:flex;gap:40px;padding:0;align-items:flex-start}} {css}</style></head>
<body>{SPRITE}<div class="wrap f-{f['slug']}">
<div class="frame webF" id="webFrame" style="height:{f['webH']}px">{f['web']}</div>
<div class="frame droidF" id="droidFrame" style="height:{f['droidH']}px">{f['droid']}</div></div>{DRAW}</body></html>'''
    open(os.path.join(ROOT, 'render', f['slug'] + '.html'), 'w', encoding='utf-8').write(page)

# combined review page
tabs = ''.join(f'<button role="tab" data-p="{f["slug"]}" aria-selected="{"true" if i == 0 else "false"}">{i + 1}. {html.escape(f["title"])}</button>' for i, f in enumerate(feats))
panels = []
allcss = []
for i, f in enumerate(feats):
    allcss.append(scope(strip_comments(f['style']), f['slug']))
    panels.append(f'''<section class="panel{' on' if i == 0 else ''} f-{f['slug']}" id="p-{f['slug']}">
<div class="phead"><div><div class="num">Fitur {i + 1}</div><h2>{f['title']}</h2><p>{f['lead']}</p></div></div>
<div class="grid">
<div class="stage"><div class="stage-label"><span>Web · 1440 × {f['webH']}</span></div><div class="fit" data-w="1440" data-h="{f['webH']}"><div class="frame webF" style="height:{f['webH']}px">{f['web']}</div></div></div>
<div class="stage dstage"><div class="stage-label"><span>Android · 390 × {f['droidH']}</span></div><div class="fit" data-w="390" data-h="{f['droidH']}" data-max="1"><div class="frame droidF" style="height:{f['droidH']}px">{f['droid']}</div></div></div>
</div>
<aside class="notes"><h3>Yang ditunjukkan mockup ini</h3><ul>{f['notes']}</ul></aside>
</section>''')

review = read(os.path.join(ROOT, 'tools', 'review_shell.html'))
review = (review.replace('/*FRAMECSS*/', strip_comments(FRAME_CSS) + EXTRA_CSS + '\n'.join(allcss))
          .replace('<!--SPRITE-->', SPRITE).replace('<!--TABS-->', tabs).replace('<!--PANELS-->', '\n'.join(panels)) + DRAW)
open(os.path.join(ROOT, 'review', 'agent-java-v3.html'), 'w', encoding='utf-8').write(review)
print('built', len(feats), 'features')
