# 🎬 Clipper Mobile - AI Smart Video Repurposing

<p align="center">
  <b>Aplikasi Android pemotong video pintar bertenaga On-Device AI untuk mengubah video panjang menjadi klip Shorts/Reels/TikTok format 9:16 secara otomatis dan 100% offline.</b>
</p>

---

## ✨ Fitur Utama

### 🎙️ 1. On-Device Whisper AI Transcription
- Ekstraksi audio 16kHz mono berkecepatan tinggi.
- Transkripsi suara menjadi teks kata-per-kata (*word-level timestamps*) secara lokal di perangkat.
- Pilihan model Whisper:
  - **Tiny (~75 MB)**: Sangat cepat (5–15 detik per menit video), hemat memori.
  - **Base (~142 MB)**: Akurasi tinggi untuk percakapan kompleks.
- Akselerasi multi-core CPU (2–6 core) dengan flag `speedUp` decoding.

### 🧠 2. Direct LLM Highlight Detection (Qwen 2.5)
- Model **Qwen 2.5 (0.5B-Instruct Q4_K_M)** on-device yang menganalisis seluruh transkrip bertimestamp.
- Menentukan batasan klip viral secara cerdas (durasi 20–60 detik per segmen).
- Menghasilkan:
  - **Viral Score (80–100)**: Prediksi daya tarik konten di media sosial.
  - **Judul Menarik**: Judul singkat memikat (maksimal 6 kata dalam Bahasa Indonesia).
  - **Ringkasan**: Rangkuman isi percakapan segmen.
- Mode fallback deterministik jika model LLM belum diunduh pengguna.

### 👤 3. Smart Face-Tracking & Live Auto-Reframe (9:16)
- Pelacakan posisi wajah pembicara aktif menggunakan **Google ML Kit Face Detection**.
- Lip-motion analysis yang mengunci kamera ke wajah orang yang sedang berbicara (bukan sekadar wajah terbesar).
- Auto-panning dinamis pada filter FFmpeg tanpa lag.

### 🎨 4. Auto Burn-in Subtitles & Gaya Tipografi
- Pembuatan subtitle otomatis tersinkronisasi presisi dari stempel waktu Whisper.
- Berbagai preset gaya subtitle viral (Cyberpunk Neon, Clean Minimal, Bold Gold, dll.).
- Opsi huruf kapital (UPPERCASE) dan pemilihan posisi subtitle (top, center, bottom).

### 📱 5. Workspace Editor & Gallery Hasil Klip
- **Workspace Editor**: Fine-tune batas waktu mulai (*start time*), preview live tracking frame, dan pengaturan cepat.
- **Pustaka & Status**: Pelacakan status video (Belum Diklip / Sudah Diklip).
- **Hasil AI (Gallery)**: Preview pemutar video hasil ekspor, salin path berkas, dan bagikan langsung ke TikTok, Reels, dan Shorts.
- **Insight Tab**: Feed artikel wawasan bisnis & teknologi langsung dari Crediblemark.

### 🔒 6. 100% Privacy-First & Offline
- Seluruh pemrosesan video, transkripsi audio, inferensi LLM, dan deteksi wajah berjalan **100% di perangkat Anda**.
- Tidak ada data video atau audio yang dikirim ke server luar/cloud.

---

## 🛠️ Tech Stack & Arsitektur

| Komponen | Teknologi |
| :--- | :--- |
| **Framework** | [Flutter](https://flutter.dev/) (Channel Stable, Dart 3.x) |
| **State Management** | [Flutter Riverpod](https://riverpod.dev/) 2.6+ |
| **Speech-to-Text** | `whisper_ggml` (whisper.cpp C++ Engine) |
| **On-Device LLM** | `llamadart` (llama.cpp GGUF Q4_K_M) |
| **Computer Vision** | `google_mlkit_face_detection` |
| **Media Processing** | `ffmpeg_kit_flutter_new` (Full-GPL with libass) |
| **Video Player** | `video_player` & `chewie` |

---

## 🚀 Memulai (Getting Started)

### Prasyarat Sistem
1. **Flutter SDK**: Versi $\ge$ 3.24.0 (disarankan 3.44+)
2. **Java / JDK**: OpenJDK 21
3. **Android SDK / NDK**: `minSdk 24` (Android 7.0+), `compileSdk 36`, NDK `29.0.13113456`

### Instalasi & Menjalankan Aplikasi

1. **Clone repositori**:
   ```bash
   git clone https://github.com/rasyiqi-code/Clipper-Moblie.git
   cd Clipper-Moblie
   ```

2. **Pasang dependensi**:
   ```bash
   flutter pub get
   ```

3. **Jalankan analisis kode & unit test**:
   ```bash
   flutter analyze
   flutter test
   ```

4. **Jalankan aplikasi di perangkat Android**:
   ```bash
   flutter run
   ```

---

## 📦 Membangun Release APK / AAB

Untuk membuat file instalasi Android mandiri:

```bash
# Build Universal Release APK
flutter build apk --release

# Build Split-per-ABI APK (Ukuran lebih kecil: arm64-v8a, armeabi-v7a)
flutter build apk --split-per-abi --release

# Build Google Play App Bundle (AAB)
flutter build appbundle --release
```

Output APK akan berada di: `build/app/outputs/flutter-apk/app-release.apk`.

---

## ⚙️ Otomasi CI/CD (GitHub Actions)

Repositori ini telah dilengkapi dengan workflow GitHub Actions otomatis di `.github/workflows/release.yml`.

Setiap kali tag rilis di-push (misal `git tag v1.1.0 && git push origin v1.1.0`), GitHub Actions akan secara otomatis:
1. Menjalankan `flutter analyze` dan `flutter test`.
2. Melakukan build release APK & App Bundle.
3. Mempublikasikan **GitHub Release** beserta file APK siap unduh.

---

## 📄 Lisensi

Proyek ini dikembangkan oleh **Rasyiqi** sebagai bagian dari ekosistem Clipper.
