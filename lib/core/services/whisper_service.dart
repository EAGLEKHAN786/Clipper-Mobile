import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';

enum WhisperModel {
  tiny(
    key: 'tiny',
    fileName: 'ggml-tiny.bin',
    modelUri:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin',
    isBundled: true,
    assetPath: 'assets/models/ggml-tiny.bin',
  ),
  base(
    key: 'base',
    fileName: 'ggml-base.bin',
    modelUri:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin',
    isBundled: false,
    assetPath: null,
  );

  final String key;
  final String fileName;
  final String modelUri;
  final bool isBundled;
  final String? assetPath;

  const WhisperModel({
    required this.key,
    required this.fileName,
    required this.modelUri,
    required this.isBundled,
    this.assetPath,
  });
}

class WhisperWord {
  final String word;
  final Duration start;
  final Duration end;

  WhisperWord({required this.word, required this.start, required this.end});
}

class WhisperService {
  WhisperModel model = WhisperModel.tiny;

  /// Maps a persisted model key ('tiny'|'base') to a [WhisperModel].
  static WhisperModel resolveModel(String key) =>
      key == 'base' ? WhisperModel.base : WhisperModel.tiny;

  /// App support directory that caches the extracted/downloaded Whisper models.
  Future<String> getModelPath([WhisperModel? targetModel]) async {
    final m = targetModel ?? model;
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'whisper_models'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return p.join(dir.path, m.fileName);
  }

  /// Whether the local Whisper model is available (bundled or cached on disk).
  Future<bool> hasLocalModel([WhisperModel? targetModel]) async {
    final m = targetModel ?? model;
    if (m.isBundled) return true;
    final path = await getModelPath(m);
    return File(path).exists();
  }

  /// Size in bytes of the cached Whisper model, or `null` when not downloaded.
  Future<int?> localModelSizeBytes([WhisperModel? targetModel]) async {
    final m = targetModel ?? model;
    final path = await getModelPath(m);
    final file = File(path);
    if (!await file.exists()) {
      if (m.isBundled) return 77595608; // ~74 MB bundled asset
      return null;
    }
    return file.length();
  }

  /// Removes the cached Whisper model from device storage.
  Future<void> deleteLocalModel([WhisperModel? targetModel]) async {
    final path = await getModelPath(targetModel);
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  /// Returns the local ggml model file, extracting from assets (if bundled)
  /// or downloading it (with progress) on first use.
  Future<File> getLocalModelFile({
    void Function(double progress)? onProgress,
  }) async {
    final path = await getModelPath();
    final file = File(path);
    if (await file.exists()) return file;

    await file.parent.create(recursive: true);

    if (model.isBundled && model.assetPath != null) {
      onProgress?.call(0.1);
      final byteData = await rootBundle.load(model.assetPath!);
      onProgress?.call(0.5);
      final buffer = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      await file.writeAsBytes(buffer, flush: true);
      onProgress?.call(1.0);
      return file;
    }

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(model.modelUri));
      final streamed = await client.send(request);
      final total = streamed.contentLength ?? 0;
      final builder = BytesBuilder(copy: false);
      await for (final chunk in streamed.stream) {
        builder.add(chunk);
        if (total > 0) onProgress?.call(builder.length / total);
      }
      await file.writeAsBytes(builder.takeBytes(), flush: true);
    } finally {
      client.close();
    }
    return file;
  }

  /// Extracts 16kHz mono WAV audio from video using local FFmpegKit.
  Future<File> extractAudioForWhisper(
    String videoPath, {
    void Function(double progress)? onProgress,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final audioFile = File(
      '${tempDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.wav',
    );

    try {
      onProgress?.call(0.05);
      await FFmpegKit.executeWithArguments([
        '-i',
        videoPath,
        '-ar',
        '16000',
        '-ac',
        '1',
        '-c:a',
        'pcm_s16le',
        '-y',
        audioFile.path,
      ]);
      onProgress?.call(1.0);
    } catch (_) {}

    return audioFile;
  }

  /// Safely deletes the temporary extracted WAV file and any secondary converted WAV.
  Future<void> cleanupTempAudioFile(File audioFile) async {
    try {
      if (await audioFile.exists()) {
        await audioFile.delete();
      }
      final secondaryWav = File('${audioFile.path}.wav');
      if (await secondaryWav.exists()) {
        await secondaryWav.delete();
      }
    } catch (_) {}
  }

  /// Transcribes [audioFile] with on-device Whisper (whisper.cpp via
  /// whisper_cpp_flutter_plus). Returns word-level timestamps which are used
  /// both for burned subtitles and for highlight analysis.
  Future<List<WhisperWord>> transcribeLocalAudio(
    File audioFile, {
    String lang = 'auto',
    bool speedUp = true,
    void Function(double progress)? onProgress,
  }) async {
    final modelFile = await getLocalModelFile(onProgress: onProgress);
    final pcm16k = await WhisperAudio.readWav(audioFile);

    final engine = await WhisperEngine.load(modelFile.path);
    final threads = Platform.numberOfProcessors.clamp(2, 6);

    StreamSubscription<int>? progressSub;
    try {
      final task = engine.transcribe(
        pcm16k,
        options: TranscribeOptions(
          language: lang,
          threads: threads,
          tokenTimestamps: true,
          splitOnWord: true,
          suppressNonSpeechTokens: true,
        ),
      );

      if (onProgress != null) {
        progressSub = task.progress.listen((percent) {
          onProgress(percent / 100.0);
        });
      }

      final result = await task.result;

      final words = <WhisperWord>[];

      for (final segment in result.segments) {
        if (segment.tokens.isNotEmpty) {
          for (final token in segment.tokens) {
            final t = token.text.trim();
            if (t.isEmpty) continue;
            // Ignore special tokens (e.g. [_BEG_], [_TT_...])
            if (t.startsWith('[_') && t.endsWith(']')) continue;
            words.add(
              WhisperWord(
                word: t,
                start: token.start,
                end: token.end > token.start
                    ? token.end
                    : token.start + const Duration(milliseconds: 250),
              ),
            );
          }
        } else {
          final segText = segment.text.trim();
          if (segText.isNotEmpty) {
            words.add(
              WhisperWord(
                word: segText,
                start: segment.start,
                end: segment.end,
              ),
            );
          }
        }
      }

      // Fallback: no word tokens decoded, expose the full text.
      if (words.isEmpty && result.text.trim().isNotEmpty) {
        words.add(
          WhisperWord(
            word: result.text.trim(),
            start: Duration.zero,
            end: const Duration(seconds: 10),
          ),
        );
      }

      return words;
    } finally {
      await progressSub?.cancel();
      engine.dispose();
    }
  }
}
