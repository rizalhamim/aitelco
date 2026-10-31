# Agent Java · Redesign v2 (dalam review)

Mockup v2 untuk rebrand ke **Agent Java** dan rework Flutter. Rizal mereview per halaman, mulai dari Login. Halaman yang belum disetujui **belum boleh** diimplementasikan. Plan lengkap ada di Claude Doc "Agent Java Redesign v2: Plan".

Mockup v1 yang disetujui sebelumnya tetap di `design/mockup/` sebagai referensi.

## Isi

| Path | Isi |
|---|---|
| `01-login/Agent Java - Redesign v2 - 01 Login.figcraft` | File FigCraft: frame Web · Login (1440 × 900), Android · Login (390 × 844), Brand · Logo dan warna |
| `01-login/png/` | Ekspor PNG @2x tiap frame |
| `01-login/review/agent-java-login.html` | Halaman review interaktif; video latar benar-benar diputar (`media/login.mp4`, H.264 720p) |
| `01-login/review/template.html` | Sumber halaman review (placeholder `{{POSTER}}`, `{{ELANG}}`, `{{CHAT}}` diisi saat build) |
| `brand/` | Logo opsi A (Elang Java, rekomendasi) dan B (Chat Insight), SVG + PNG 1024 |
| `tools/` | Konverter HTML ke FigCraft (lihat bawah) |

## Video login

Video yang live sekarang (`frontend/public/media/login-bg.mp4`) berformat **HEVC** 28,6 MB, sehingga tidak diputar di Firefox dan di banyak Chrome tanpa dekoder hardware. v2 memakai H.264:

```bash
ffmpeg -i login-bg.mp4 -an -vf scale=1920:-2 -c:v libx264 -profile:v high -pix_fmt yuv420p -crf 24 -preset slow -movflags +faststart login-bg-1080-h264.mp4   # 7,8 MB
```

FigCraft tidak bisa memutar video, jadi frame "Video latar" di `.figcraft` berisi poster dengan anotasi spesifikasi video.

## Format .figcraft dan konverter

`.figcraft` adalah zip berisi `document.json` (pohon node: page, frame, text, dll.) dan `images/<sha256>`. Mockup v2 ditulis sebagai HTML lalu dikonversi:

```bash
node tools/extract.js page.html tree.json '#webFrame' '#droidFrame' '#brandFrame'   # Playwright: ukur layout, rasterkan ikon SVG
python3 tools/build.py tree.json "out.figcraft" "Agent Java - Redesign v2" "01 · Login" poster.jpg thumb.png
python3 tools/preview.py out.figcraft preview.html                                   # render balik untuk cek posisi
```

Catatan: font isi Prompt dipetakan ke Poppins di file FigCraft karena Prompt belum terpasang di PC desain. Teks bergradasi (kata "Second") disimpan sebagai lime solid.

## Palet v2

Teal tetap inti. Aksen baru: **Lagoon** `#22B8C9`, **Lime** `#C7F25E`, **Coral** `#FF7A59` (teks di latar terang memakai tingkat 700: `#0E6F7C`, `#5E8A12`, `#B5401F`). Token akan masuk `design/tokens.json` setelah disetujui.
