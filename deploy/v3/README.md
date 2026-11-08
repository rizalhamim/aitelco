# Deploy Agent Java v3

Enam fitur baru: Brief Pagi, Diagnosa, Klasemen, Ruang Saya, Tindak Lanjut, Simulasi Target.

Satu perintah, tempel di Git Bash di PC lalu Enter:

```bash
ssh agent-02 'cd /home/ubuntu/telco-ai && git fetch -q github claude/project-thread-kjx27g && git show FETCH_HEAD:deploy/v3/run.sh' > ~/aj-deploy.sh && bash ~/aj-deploy.sh all
```

Urutannya:
1. Server agent-02: backup database, ambil kode (berhenti kalau server menjalankan commit yang tidak ada di branch ini), cek `targets.json`, uji (pytest dan benchmark KB; kalau gagal server tidak di-restart), build web, restart, cek 8 endpoint dan 8 halaman v3, smoke chat.
2. PC: build APK 1.51.0 (70) di clone terpisah `D:\Project\Project.Bizplan-Java.com\aitelco-release`, lalu kirim ke server.
3. Server: cek kunci tanda tangan APK, terbitkan, APK 1.50.0 tetap bisa diunduh di Riwayat versi.

Log tiap jalan ada di `~/aj-deploy-logs/`.

Batalkan deploy (minta ketik YA):

```bash
bash ~/aj-deploy.sh rollback
```

Satu langkah saja: `bash ~/aj-deploy.sh deploy`, `apk`, atau `release`.

Catatan:
- APK ini menambah plugin TTS, kamera, notifikasi lokal dan WorkManager. Build di PC adalah cek Gradle pertama untuk plugin itu.
- Target bulanan untuk Simulasi dan Klasemen dibaca dari `backend/data/targets.json` di server. Tanpa isi bulan berjalan, halaman tetap jalan dengan pesan "target belum diisi".
- Foto bukti Tindak Lanjut disimpan di `backend/data/uploads/tasks/` di server.
