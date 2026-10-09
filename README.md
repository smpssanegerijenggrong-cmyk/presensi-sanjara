# Presensi Sanjara

Sistem absensi wajah siswa realtime dalam satu `index.html`: HTML5, Tailwind CDN, JavaScript ES Modules, face-api.js, dan Supabase. Deteksi dan pencocokan wajah berjalan di browser; Supabase menyimpan siswa/presensi dan mengirim pembaruan realtime. Tidak diperlukan server aplikasi tambahan.

## Persiapan Supabase

1. Buat proyek Supabase. Buka **SQL Editor**, salin seluruh isi [`supabase.sql`](supabase.sql), lalu jalankan. Skrip membuat `students`, `attendances`, `school_staff`, validasi descriptor 128 angka, indeks, kebijakan RLS, dan publikasi Realtime. Jalankan pada proyek baru atau periksa kebijakan lama agar tidak ada kebijakan lain yang membuka akses data.
2. Buka **Authentication → Providers → Email** atau **Authentication → Settings**, lalu nonaktifkan pendaftaran akun publik (**Allow new users to sign up**). Aktifkan metode login Email/Password. Nama menu dapat berbeda menurut versi Dashboard.
3. Di **Authentication → Users**, gunakan **Add user** untuk membuat akun guru dengan email dan kata sandi. Konfirmasikan email melalui Dashboard bila diperlukan. Salin **User UID** akun itu dan jalankan di SQL Editor:

   ```sql
   insert into public.school_staff (user_id)
   values ('GANTI-DENGAN-UUID-AKUN-GURU')
   on conflict (user_id) do nothing;
   ```

4. Dari **Project Settings → API** / **Connect**, salin **Project URL** dan kunci **anon/public** atau **publishable**. Masukkan melalui tab **Konfigurasi** pada aplikasi. Jangan gunakan `service_role`, `sb_secret_…`, kata sandi database, atau token admin di browser.
5. Login sebagai guru dari tab konfigurasi. Kunci publik tersimpan di LocalStorage perangkat; kata sandi tidak disimpan oleh aplikasi. Supabase menyimpan sesi login untuk menjaga koneksi. Gunakan **Keluar** ketika selesai di komputer bersama.

RLS membatasi data pada akun yang terdaftar di `school_staff`. Pengunjung anonim dan akun yang belum diizinkan tidak dapat membaca data siswa atau mencatat presensi. Browser guru hanya diberi izin membaca dan menambah data; administrasi/retensi dilakukan di Dashboard atau SQL Editor.

## Menjalankan aplikasi

Tombol **Keluar** membersihkan kamera, data siswa, dan sesi browser segera, termasuk saat jaringan gagal. URL dan kunci publik tetap tersimpan agar guru dapat masuk kembali. **Hapus konfigurasi** juga menghapus pengaturan koneksi. Pembersihan hanya menyentuh sesi Sanjara; sesi dari respons login/refresh yang terlambat tidak disimpan kembali.

Berkas `index.html` dapat dibuka langsung bila browser mengizinkan CDN, penyimpanan lokal, dan kamera untuk berkas lokal. Untuk penggunaan sekolah yang paling andal, unggah ke hosting statis ber-**HTTPS** atau gunakan server berkas lokal. Server ini hanya menyajikan berkas, bukan backend aplikasi:

```bash
cd /workspace/presensi-sanjara
python3 -m http.server 8080 --bind 0.0.0.0
```

Buka `http://localhost:8080` dari mesin yang menjalankan server. Gunakan browser modern seperti Chrome/Edge dan berikan izin kamera. Bila browser membatasi webcam saat berkas dibuka langsung, gunakan HTTPS atau `localhost`. Pada lingkungan cloud, server statis dipakai untuk validasi internal; akses `file://` belum diverifikasi karena kebijakan browser yang dikelola.

Internet dibutuhkan untuk `cdn.jsdelivr.net` serta domain proyek `*.supabase.co` (HTTPS dan WebSocket). Tailwind dimuat dari `https://cdn.jsdelivr.net/npm/@tailwindcss/browser@4.1.18`; face-api.js, ikon, klien Supabase, dan model juga berasal dari jsDelivr. Model pertama kali diunduh oleh browser, sekitar **7 MB**; koneksi yang lambat dapat menunda status **Model siap**. Jangan mematikan verifikasi TLS untuk mengatasi unduhan gagal.

Tombol **Coba tampilan demo** menampilkan siswa contoh dan simulasi presensi tanpa konfigurasi Supabase. Data demo hanya berada dalam memori browser, tidak tersimpan setelah halaman dimuat ulang, dan tidak dikirim ke Supabase. Keluar dari mode demo untuk mendaftarkan siswa atau memakai kamera presensi.

## Alur guru

1. Simpan konfigurasi, login, dan tunggu koneksi Supabase. Model dimuat otomatis saat foto dianalisis atau kamera dimulai; Anda juga dapat menekan **Muat model pengenalan** pada tab Konfigurasi.
2. Pada **Pendaftaran siswa**, isi NISN tepat 10 digit, nama, dan kelas. Unggah foto atau ambil dari kamera. Gunakan foto terang dengan tepat satu wajah menghadap kamera. Aplikasi mengekstrak descriptor 128 angka dan menyimpan thumbnail terkompresi sebagai data URL di `photo_url`; bucket Storage tidak diperlukan.
3. Pada **Presensi kelas**, pilih kelas dan webcam, lalu mulai kamera. Wajah yang cocok menambahkan satu presensi per siswa per hari. UI berubah segera setelah penyimpanan berhasil, dan perangkat guru lain menerima pembaruan melalui Supabase Realtime.
4. Hentikan kamera ketika selesai. Jika tab tidak aktif, koneksi terputus, atau sesi habis, kembali ke aplikasi dan pastikan status koneksi pulih sebelum melanjutkan.

Tanggal dan jam sekolah menggunakan **Asia/Jakarta (WIB)**. Trigger database mengisi waktu server dan kelas siswa, sehingga jam komputer guru tidak menentukan waktu presensi. Constraint `UNIQUE(student_id, date)` mencegah duplikasi, termasuk dari dua perangkat bersamaan. Belum hadir dihitung dari siswa kelas terpilih yang belum mempunyai presensi hari itu.

## Pemeriksaan setelah konfigurasi

- Login sebagai guru yang diizinkan, daftarkan satu siswa, lalu pastikan data muncul setelah halaman dimuat ulang.
- Coba foto tanpa wajah atau dengan beberapa wajah; pendaftaran harus ditolak. NISN yang sama juga harus ditolak.
- Buka dua browser/perangkat dengan akun guru, pilih kelas sama, lalu lakukan presensi. Kedua daftar harus berubah; deteksi berulang harus tetap menghasilkan satu baris per hari.
- Logout lalu pastikan data tidak tersedia. Akun yang tidak tercantum di `school_staff` juga harus ditolak.
- Uji pencahayaan, kamera, dan siswa nyata di lokasi sekolah sebelum dipakai rutin. Pengujian tanpa proyek Supabase dan kamera nyata tidak membuktikan akurasi pengenalan atau kelancaran Realtime di jaringan sekolah.

Jika Supabase tidak terhubung, periksa Project URL/kunci publik, sesi login, `school_staff`, dan hasil migrasi. Jika **Realtime** terputus, periksa koneksi WebSocket jaringan sekolah serta tabel `attendances` dan `students` dalam publikasi `supabase_realtime`. Jika model gagal, periksa akses CDN. Jika kamera gagal, periksa HTTPS/localhost, izin browser, dan aplikasi lain yang memakai kamera.

## Pengelolaan data sekolah

Descriptor wajah dan foto adalah data biometrik siswa. Sekolah perlu menentukan dasar izin/persetujuan wali, tujuan penggunaan, guru yang diizinkan, dan masa simpan; batasi akses perangkat serta proyek Supabase. Raw frame kamera diproses di browser. Yang disimpan adalah thumbnail pendaftaran, descriptor, identitas siswa, dan presensi.

Pengenalan ini tidak memiliki pemeriksaan keaslian wajah (*liveness*) dan dapat terkecoh foto/video. Gunakan pengawasan guru serta pencatatan alternatif saat pencocokan salah atau siswa tidak dapat dikenali. Ambang pencocokan bukan jaminan identitas.

Untuk mencabut akses, hapus UUID guru dari `school_staff` melalui SQL Editor dan pastikan sesi/perangkat terkait logout. Untuk retensi, ekspor laporan yang diperlukan lalu hapus data sesuai kebijakan sekolah. Penghapusan `students` juga menghapus presensi siswa melalui `ON DELETE CASCADE`. Skrip migrasi tidak menghapus data dan tidak menerapkan retensi otomatis.

## Catatan lingkungan cloud

Checkout yang ada sudah berada dalam lingkungan tugas terisolasi. Gunakan checkout itu; jangan membuat Git worktree baru kecuali pengguna secara eksplisit memintanya. Tidak ada instalasi npm atau proses build yang diperlukan. CDN tetap dibutuhkan saat runtime, dan kredensial proyek Supabase diisi oleh sekolah melalui konfigurasi aplikasi, bukan ditulis ke sumber atau commit.
