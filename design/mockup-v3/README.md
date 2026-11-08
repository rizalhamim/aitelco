# Agent Java v3 · mockup fitur baru (menunggu review)

Konsep 6 fitur baru untuk web dan Android, dibuat 5 Nov 2026 mengikuti gaya Redesign v2 (`design/mockup-v2/`). Plan lengkap ada di Claude Doc "Agent Java v3: Plan Fitur Baru dan Mockup". Semua angka di mockup adalah data ilustrasi.

| # | Fitur | Isi |
|---|---|---|
| 01 | Diagnosa "Kenapa?" | Waterfall kontribusi per kabupaten (jumlah = total, "Lainnya" tampil), efek volume/rate/mix, pohon telusur sampai site, hipotesis berlabel dengan bukti dan keyakinan |
| 02 | Brief Pagi | Brief pribadi 06.00: kalimat agent, 3 kartu terpenting, posisi target (bullet bar dengan rentang estimasi), agenda, audio 60 detik; Android tampilan story |
| 03 | Klasemen | Peringkat region/kabupaten/kecamatan, MTD vs LMTD hari yang sama, pertumbuhan persen plus rupiah, tanda basis kecil, wilayah pantauan |
| 04 | Ruang Saya | Papan pin dari jawaban agent (pin menyimpan pertanyaan, bukan angka), papan tim, catatan, drag and drop, kirim terjadwal |
| 05 | Tindak Lanjut | Tugas dari alert/insight dengan PIC, tenggat, checklist, foto bukti; ditutup saat KPI terbukti membaik (14 hari sebelum vs sesudah) |
| 06 | Simulasi Target | Realisasi, estimasi dengan rentang, target, gap, run-rate perlu; grafik selisih terhadap jalur target; tuas skenario yang didukung dump |

## Isi folder

| Path | Isi |
|---|---|
| `features/NN-*.html` | Sumber tiap fitur: `<style>` + `<template id="web|droid|notes">`, makro `{{SIDE:key}}`, `{{TOP:..}}`, `{{DBAR:..}}`, `{{BNAV:key}}` |
| `_base/` | CSS frame bersama (diambil dari template v2), sprite ikon v2, logo elang resmi (160 px), font Poppins/Prompt lokal, `draw.js` (sparkline, waveform, waterfall, grafik estimasi) |
| `tools/build.py` | Menulis `render/<slug>.html` (halaman piksel) dan `review/agent-java-v3.html` (halaman review bertab) |
| `tools/shoot.js` | Screenshot @2x ke `png/<slug>/` |
| `figcraft/` | File FigCraft per fitur, dibuat dengan `../mockup-v2/tools/extract.js` + `build.py` |

```bash
python3 design/mockup-v3/tools/build.py
node design/mockup-v3/tools/shoot.js          # atau: node tools/shoot.js 03-klasemen
```

Nama wilayah: Circle Java, West Java, Central Java, East Java (tidak diterjemahkan). Tanpa em-dash.
