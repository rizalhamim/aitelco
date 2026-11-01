# Deploy Redesign v2 (Agent Java)

Satu perintah, tempel di Git Bash di PC lalu Enter:

```bash
ssh agent-02 'cd /home/ubuntu/telco-ai && git fetch -q github claude/project-thread-mnz2kt && git show FETCH_HEAD:deploy/redesign-v2/run.sh' > ~/aj-deploy.sh && bash ~/aj-deploy.sh all
```

Urutannya:
1. Server agent-02: backup database, ambil kode, dump Parquet, cache peta, uji (pytest dan benchmark KB; kalau gagal server tidak di-restart), build web, restart, smoke chat.
2. PC: build APK 1.50.0 (69) di clone terpisah `D:\Project\Project.Bizplan-Java.com\aitelco-release`, lalu kirim ke server.
3. Server: cek kunci tanda tangan APK, terbitkan, APK 1.49.1 tetap bisa diunduh.

Log tiap jalan ada di `~/aj-deploy-logs/`.

Batalkan deploy (minta ketik YA):

```bash
bash ~/aj-deploy.sh rollback
```

Satu langkah saja: `bash ~/aj-deploy.sh deploy`, `apk`, atau `release`.
