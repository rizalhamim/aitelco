# Bizplan Java Agent · Redesign v1 (disetujui)

Mockup final yang sudah disetujui Rizal (29 Okt 2026). Dibuat di FigCraft (aplikasi desktop lokal), lalu diekspor ke sini sebagai acuan implementasi. **Kode web dan Android harus cocok dengan frame di sini**, baik ukuran, spasi, radius, warna, tipografi, ikon, maupun state (tooltip, drill-down, empty, skeleton).

Semua angka di mockup adalah **data ilustrasi**.

## Isi folder

| Path | Isi |
|---|---|
| `Bizplan Java Agent - Redesign v1.figcraft` | File sumber FigCraft (3 halaman: Konsep & Mockup, Design System, Redesign v1) |
| `export/` | PNG tiap frame (web 1x, Android 2x). `_Ringkasan semua frame.png` = semua frame dalam satu gambar |
| `export/2x/` | PNG web @2x (hanya yang < 5 MB) |
| `spec/<frame>.json` | Pohon node lengkap per frame: auto layout (arah, gap, padding, align, sizing), ukuran dan posisi, radius, fill (termasuk gradien dan image), stroke, efek (shadow/blur), teks (isi, font, ukuran, weight, line height, letter spacing), `boundVariables` (token yang dipakai), instance komponen dan properti, interaksi prototipe |
| `spec/tokens.json` | Variabel FigCraft (koleksi **Warna** mode Terang/Gelap + **Dimensi**) dalam JSON dan CSS custom properties, text styles, effect styles, daftar komponen |
| `assets/brand/` | Logo resmi: `icon_circle_java.png`, `Logo IOH-Color.png`, `Logogram IOH.png` (tidak ada logo baru) |
| `assets/codex/` | Ilustrasi dan ikon yang **dibuat Codex** (gpt-6.1-sol, reasoning xhigh), revisi 2 |
| `assets/codex-v1/` | Aset Codex revisi 1 (sebagian masih dipakai: pola login, orb lama, ilustrasi laporan) |
| `assets/stills/` | Potongan still dari video login (`login-bg-poster.jpg` = poster penuh 1920×1080) |
| `assets/screens/` | Potongan layar yang dipakai di mockup perangkat (halaman Unduh APK, Konsep) |

Video login: `frontend/public/media/login-bg.mp4` (salinan utuh, 28,6 MB, 1080p) + `frontend/public/media/login-bg-poster.jpg`.

## Frame

| Frame | Jenis | Ekspor | 2x | Spec |
|---|---|---|---|---|
| Android - Dashboard | Android 390 | [png](export/Android%20-%20Dashboard.png) | — | [json](spec/Android%20-%20Dashboard.json) |
| Android - Dashboard (Gelap) | Android 390 | [png](export/Android%20-%20Dashboard%20(Gelap).png) | — | [json](spec/Android%20-%20Dashboard%20(Gelap).json) |
| Android - Laporan | Android 390 | [png](export/Android%20-%20Laporan.png) | — | [json](spec/Android%20-%20Laporan.json) |
| Android - Login | Android 390 | [png](export/Android%20-%20Login.png) | — | [json](spec/Android%20-%20Login.json) |
| Android - Peta | Android 390 | [png](export/Android%20-%20Peta.png) | — | [json](spec/Android%20-%20Peta.json) |
| Android - Splash | Android 390 | [png](export/Android%20-%20Splash.png) | — | [json](spec/Android%20-%20Splash.json) |
| Android - Statistik (admin) | Android 390 | [png](export/Android%20-%20Statistik%20(admin).png) | — | [json](spec/Android%20-%20Statistik%20(admin).json) |
| Android - Tanya Agent | Android 390 | [png](export/Android%20-%20Tanya%20Agent.png) | — | [json](spec/Android%20-%20Tanya%20Agent.json) |
| Android - Unduh APK | Android 390 | [png](export/Android%20-%20Unduh%20APK.png) | — | [json](spec/Android%20-%20Unduh%20APK.json) |
| Android - Watchlist dan Alert | Android 390 | [png](export/Android%20-%20Watchlist%20dan%20Alert.png) | — | [json](spec/Android%20-%20Watchlist%20dan%20Alert.json) |
| Konsep dan Mockup | Presentasi 1920 | [png](export/Konsep%20dan%20Mockup.png) | — | [json](spec/Konsep%20dan%20Mockup.json) |
| Web - Dashboard Monitoring | Web 1440 | [png](export/Web%20-%20Dashboard%20Monitoring.png) | [2x](export/2x/Web%20-%20Dashboard%20Monitoring@2x.png) | [json](spec/Web%20-%20Dashboard%20Monitoring.json) |
| Web - Dashboard Monitoring (Gelap) | Web 1440 | [png](export/Web%20-%20Dashboard%20Monitoring%20(Gelap).png) | [2x](export/2x/Web%20-%20Dashboard%20Monitoring%20(Gelap)@2x.png) | [json](spec/Web%20-%20Dashboard%20Monitoring%20(Gelap).json) |
| Web - Laporan | Web 1440 | [png](export/Web%20-%20Laporan.png) | [2x](export/2x/Web%20-%20Laporan@2x.png) | [json](spec/Web%20-%20Laporan.json) |
| Web - Login | Web 1440 | [png](export/Web%20-%20Login.png) | [2x](export/2x/Web%20-%20Login@2x.png) | [json](spec/Web%20-%20Login.json) |
| Web - Peta dan Site | Web 1440 | [png](export/Web%20-%20Peta%20dan%20Site.png) | [2x](export/2x/Web%20-%20Peta%20dan%20Site@2x.png) | [json](spec/Web%20-%20Peta%20dan%20Site.json) |
| Web - Statistik (admin) | Web 1440 | [png](export/Web%20-%20Statistik%20(admin).png) | [2x](export/2x/Web%20-%20Statistik%20(admin)@2x.png) | [json](spec/Web%20-%20Statistik%20(admin).json) |
| Web - Statistik - Detail pengguna | Web 1440 | [png](export/Web%20-%20Statistik%20-%20Detail%20pengguna.png) | [2x](export/2x/Web%20-%20Statistik%20-%20Detail%20pengguna@2x.png) | [json](spec/Web%20-%20Statistik%20-%20Detail%20pengguna.json) |
| Web - Tampilan | Web 1440 | [png](export/Web%20-%20Tampilan.png) | [2x](export/2x/Web%20-%20Tampilan@2x.png) | [json](spec/Web%20-%20Tampilan.json) |
| Web - Tanya Agent | Web 1440 | [png](export/Web%20-%20Tanya%20Agent.png) | [2x](export/2x/Web%20-%20Tanya%20Agent@2x.png) | [json](spec/Web%20-%20Tanya%20Agent.json) |
| Web - Unduh APK | Web 1440 | [png](export/Web%20-%20Unduh%20APK.png) | [2x](export/2x/Web%20-%20Unduh%20APK@2x.png) | [json](spec/Web%20-%20Unduh%20APK.json) |
| Web - Watchlist dan Alert | Web 1440 | [png](export/Web%20-%20Watchlist%20dan%20Alert.png) | [2x](export/2x/Web%20-%20Watchlist%20dan%20Alert@2x.png) | [json](spec/Web%20-%20Watchlist%20dan%20Alert.json) |

## Token utama (ringkas; lengkapnya di `spec/tokens.json`)

- Warna utama teal: 50 `#E6F7F5` · 100 `#C0EDE8` · 200 `#8FDFD7` · 300 `#5BCEC3` · 400 `#33BCAD` · 500 `#15A697` · **600 `#0E8579` (tombol/primary)** · 700 `#0A6A5F` (teks aksen) · 800 `#074D45` · 900 `#04332E` (hero/banner gelap).
- Netral: ink `#0F1F1D`, text/secondary `#3D4C49`, text/mute `#5A6B68`, rule `#E1E9E7`, bg `#F5F9F8`, surface `#FFFFFF`, surface/muted `#ECF3F1`. Status: danger `#C42B2B`/tint `#FDECEC`, warning `#F5A623`/tint `#FDF3E2`/text `#B7791F`, success `#1F7A3A`.
- Aksen domain untuk tile ikon: blue, violet, amber, rose, green (`*/50` latar, `*/600|700` ikon). Mode **Gelap** punya nilai sendiri untuk setiap token.
- Tipografi: **Poppins** untuk judul, KPI, label; **Prompt** untuk body (di mockup body masih Poppins karena Prompt tidak terpasang di PC desain; implementasi pakai Prompt). Skala: Display 30/800, Hero 44/800, H1 24/700, H2 18/700, Title 16/600, Body 16 & 14/400, Label 13/500–600, Caption 12, Overline 11/600 +8% uppercase, KPI 28 & 22/700 tabular.
- Radius 8/12/16/20 (kartu)/999 (pill) · spasi 4–32 · bayangan lembut `0 4 14 rgba(15,31,29,.06)` · target sentuh ≥ 44 px.
- Motif: hero bergradasi teal ke teal-900 dengan aksen amber + motif batik kawung (`assets/codex/kawung_pattern.svg`, opacity 0.12–0.18).

## Aset yang dibuat Codex

Revisi 2 (`assets/codex/`): ai_orb_particles.svg, duo_alert.svg, duo_chat.svg, duo_download.svg, duo_ftth.svg, duo_fwa.svg, duo_map.svg, duo_marketshare.svg, duo_network.svg, duo_report.svg, duo_revenue.svg, duo_sales.svg, duo_shield.svg, duo_site.svg, empty_state_alert.svg, empty_state_search.svg, install_step1.svg, install_step2.svg, install_step3.svg, iso_city.svg, iso_dashboard.svg, iso_tower.svg, java_glow_dots.svg, kawung_pattern.svg.

Revisi 1 (`assets/codex-v1/`): ai_spark_badge.svg, dataviz_waves.svg, empty_reports.svg, hero_ai_orb.svg, login_overlay_pattern.svg, map_glow.svg.

Prompt yang dipakai ada di `PROMPT.md` di masing-masing folder. Ikon garis UI memakai gaya Lucide (ISC), digambar ulang sebagai komponen.

## Catatan implementasi

1. **Login** (web dan Android): video latar `login-bg.mp4` dengan `autoplay muted loop playsinline`, `object-fit: cover`, poster = `login-bg-poster.jpg`, overlay teal-900 sesuai frame. Saat `prefers-reduced-motion`, tampilkan poster saja. Isi halaman hanya logo, "Winning Every Second", "Bizplan Java Agent", dan kartu login (Username, Password, Lupa password, Masuk). **Tidak ada link unduh di halaman login.**
2. **Unduh APK hanya setelah login**: menu sidebar "Unduh APK", kartu promo "Aplikasi Android" di sidebar, dan halaman `Web - Unduh APK` (versi mobile: `Android - Unduh APK`). QR di mockup mengarah ke URL contoh `https://bizplan-java.ioh/apk`; ganti dengan URL APK asli (yang perlu login).
3. **Chart di jawaban agent harus berupa visual interaktif yang benar**, bukan teks atau tabel saja: line/area (dengan pembanding periode putus-putus), grouped bar, stacked area, donut/ring, heatmap, sparkline. Semua punya tooltip saat hover/tap, crosshair, toggle legend, scrubber periode, dan drill-down region → kabupaten → site dengan breadcrumb. Lihat `Web - Tanya Agent`, `Web - Dashboard Monitoring`, `Web - Statistik (admin)`, dan versi Android-nya.
4. **Mode gelap** = token yang sama dengan mode Gelap (lihat `Web - Dashboard Monitoring (Gelap)`, `Android - Dashboard (Gelap)`, halaman Tampilan).
5. **Statistik (admin)**: login terakhir, jumlah login, login gagal, dan aktivitas query/export sudah ada di backend (`users`, `login_audit`, `usage_log`). Unduhan APK, versi app terpasang, dan model perangkat **belum dicatat**; perlu tracking baru.
6. Peta memakai batas kabupaten Jawa (116 kab/kota) dengan skala warna Revenue MoM seperti di `Web - Peta dan Site`.
