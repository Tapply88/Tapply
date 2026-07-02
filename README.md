# Tapply — POS Kasir untuk Bisnis F&B

Scaffold Flutter app: kasir, membership + poin, laporan penjualan, siap diintegrasi Midtrans (QRIS/GoPay).

## Cara pakai dengan GitHub Codespaces (gak ribet, gak perlu install apa-apa di laptop)

1. Bikin repo baru di GitHub (kosong aja), misal `tapply`.
2. Upload/push semua file di folder ini ke repo itu:
   ```bash
   git init
   git add .
   git commit -m "init tapply"
   git branch -M main
   git remote add origin https://github.com/USERNAME/tapply.git
   git push -u origin main
   ```
3. Di halaman repo GitHub, klik tombol hijau **Code** → tab **Codespaces** → **Create codespace on main**.
4. Tunggu ~2-3 menit, Codespace bakal otomatis install Flutter SDK (lewat `.devcontainer/devcontainer.json`) dan jalanin `flutter pub get`.
5. Setelah kebuka, jalankan di terminal Codespace:
   ```bash
   flutter run -d web-server --web-port 8080
   ```
   Codespaces bakal kasih notifikasi "port forwarded" — klik buat buka app-nya di browser.

   Kalau mau coba di Android, agak susah lewat Codespaces (butuh emulator/device). Untuk demo cepat & development, web-server paling praktis di cloud.

## Setup Midtrans (backend proxy)

Server Key **jangan pernah** ditaruh langsung di app Flutter — makanya ada folder `/server` sebagai backend kecil yang megang Server Key dengan aman.

1. Daftar akun Midtrans (sandbox dulu, gratis): https://dashboard.midtrans.com/register
2. Ambil Server Key & Client Key dari dashboard sandbox.
3. Di folder `server/`:
   ```bash
   cp .env.example .env
   # isi .env dengan Server Key & Client Key kamu
   npm install
   npm start
   ```
4. Deploy backend ini ke layanan gratis/murah seperti Railway, Render, atau Fly.io biar bisa diakses dari app (bisa juga jalan bareng di Codespace buat testing, tinggal forward port 3000).
5. Update `backendBaseUrl` di `lib/services/midtrans_service.dart` sesuai URL backend kamu.
6. Set webhook notification URL di dashboard Midtrans ke `https://your-backend/midtrans-webhook`.

## Struktur project

```
lib/
  models/        # Product, Member, TransactionRecord
  services/      # db_service (Hive local storage), midtrans_service
  screens/       # cashier, membership, report
server/          # backend proxy Node.js buat Midtrans
```

## Yang masih perlu di-generate

Model Hive (`product.g.dart`, `member.g.dart`, `transaction.g.dart`) belum ada — generate otomatis dengan:
```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```
(Jalanin ini di Codespace setelah `flutter pub get` sukses.)

## Roadmap saran

- [ ] Wire tombol "QRIS / Midtrans" di kasir ke `MidtransService.createTransaction` + tampilkan QR/redirect via webview
- [ ] Export laporan ke Excel/PDF
- [ ] Multi-outlet (BSD & Gading Serpong) dengan filter cabang
- [ ] Role login kasir vs owner
