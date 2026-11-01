# Agent Java · Redesign v2 (dalam review)

Mockup v2 untuk rebrand ke **Agent Java** dan rework Flutter. Rizal mereview per halaman, mulai dari Login. Status: 01 Login sampai 06 Laporan disetujui (1 Nov 2026), 07 Watchlist dan Alert menunggu review. Halaman yang belum disetujui **belum boleh** diimplementasikan. Plan lengkap ada di Claude Doc "Agent Java Redesign v2: Plan".

Mockup v1 yang disetujui sebelumnya tetap di `design/mockup/` sebagai referensi.

**Logo (keputusan Rizal, 1 Nov 2026):** logo elang lama (`design/mockup/assets/brand/icon_circle_java.png`) tetap logo resmi di login, web, dan di dalam app. Yang berubah hanya ikon app Android di layar HP (tulisan "Agent Java") dan nama app menjadi Agent Java. Tidak ada logo bergambar baru.

## Isi

| Path | Isi |
|---|---|
| `01-login/Agent Java - Redesign v2 - 01 Login.figcraft` | File FigCraft: frame Web · Login (1440 × 900), Android · Login (390 × 844), Brand · Logo dan warna (1200 × 860) |
| `01-login/png/` | Ekspor PNG @2x tiap frame |
| `01-login/review/agent-java-login.html` | Halaman review interaktif; video latar benar-benar diputar (`media/login.mp4`, H.264 720p) |
| `01-login/review/template.html` | Sumber halaman review (placeholder `{{POSTER}}` dan `{{OLDLOGO}}` diisi saat build) |
| `01-login/app-icon/` | Ikon app Android baru berupa tulisan "Agent Java": PNG 1024 (bulat dan kotak) + layer adaptive icon 432 (foreground, background) |
| `02-tanya-agent/` | Halaman 02 Tanya Agent: `.figcraft` (Web 1440 × 1080, Android 390 × 844), PNG @2x, halaman review interaktif (tab Grafik/Tabel/Peta) |
| `03-dashboard/` | Halaman 03 Dashboard: `.figcraft` (Web 1440 × 1420, Android 390 × 1720 layar digulir), PNG @2x, halaman review interaktif (tooltip, legenda, Batang/Garis) |
| `04-performance/` | Halaman 04 Performance: `.figcraft` (Web 1440 × 1590, Android 390 × 1990 layar digulir), PNG @2x, halaman review interaktif (drill-down, tren 12 bulan Revenue/Payload/Pelanggan, detail site di baris tabel) |
| `05-peta-agent/` | Halaman 05 Peta Agent: `.figcraft` (Web 1440 × 900, Android 390 × 844), PNG @2x, halaman review interaktif (hover kecamatan, klik site, layer on/off). Revisi 1 Nov: peta bisa diwarnai Performance, Site productivity, atau Profile wilayah, dan klik kecamatan membuka kartu ringkasan ketiganya. Batas 42 kecamatan Kab. Garut diambil dari `mobile/assets/geo/kecamatan.geojson.gz`; nilai dan titik site ilustrasi |
| `06-laporan/` | Halaman 06 Laporan: `.figcraft` (Web 1440 × 1040, Android 390 × 1300 layar digulir), PNG @2x, halaman review interaktif (filter, pilih laporan, daftar isi, jadwal kirim). Performance Outlook memuat bagian Performance, Site productivity, dan Profile wilayah |
| `07-watchlist-alert/` | Halaman 07 Watchlist dan Alert: `.figcraft` (Web 1440 × 1156, Android 390 × 1320 layar digulir), PNG @2x, halaman review interaktif (filter status dan kelompok, tab Riwayat alert). Pantauan dikelompokkan Performance, Site productivity, dan Profile wilayah; pantauan baru bisa dibuat dari kalimat |
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

Penamaan wilayah mengikuti data dan tidak diterjemahkan: Circle Java, West Java, Central Java, East Java.

Catatan: font isi Prompt dipetakan ke Poppins di file FigCraft karena Prompt belum terpasang di PC desain. Teks bergradasi (kata "Second") disimpan sebagai lime solid.

## Palet v2

Teal tetap inti. Aksen baru: **Lagoon** `#22B8C9`, **Lime** `#C7F25E`, **Coral** `#FF7A59` (teks di latar terang memakai tingkat 700: `#0E6F7C`, `#5E8A12`, `#B5401F`). Token akan masuk `design/tokens.json` setelah disetujui.
