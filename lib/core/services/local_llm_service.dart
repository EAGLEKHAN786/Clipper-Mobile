import 'dart:io';
import 'dart:math';

import 'package:llamadart/llamadart.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/video_segment.dart';
import 'whisper_service.dart';

/// On-device LLM segment detector and grader.
///
/// Directly analyzes full timestamped Whisper transcripts with Qwen 2.5
/// to identify the most engaging and viral Shorts/Reels segments (20-60s each),
/// generating start/end bounds, viral scores, titles, and summaries.
class LocalLlmService {
  /// Qwen2.5-0.5B-Instruct Q4_K_M (~491 MB) - balanced size/quality tradeoff.
  static const String modelSource =
      'hf://Qwen/Qwen2.5-0.5B-Instruct-GGUF/qwen2.5-0.5b-instruct-q4_k_m.gguf';

  final ModelSource _source = ModelSource.parse(modelSource);
  String? _cacheDir;

  /// App-private directory that hosts the downloaded GGUF model.
  Future<String> _cacheDirectory() async {
    if (_cacheDir != null) return _cacheDir!;
    final support = await getApplicationSupportDirectory();
    _cacheDir = p.join(support.path, 'llm_models');
    return _cacheDir!;
  }

  String _modelFilePath(String cacheDir) =>
      p.join(cacheDir, _source.cacheDirectoryName, _source.fileName);

  /// Whether the local LLM model has been downloaded already.
  Future<bool> isModelDownloaded() async {
    final dir = await _cacheDirectory();
    return File(_modelFilePath(dir)).exists();
  }

  /// Size in bytes of the cached LLM model, or `null` when not downloaded.
  Future<int?> modelSizeBytes() async {
    final dir = await _cacheDirectory();
    final file = File(_modelFilePath(dir));
    if (!await file.exists()) return null;
    return file.length();
  }

  /// Deletes the cached LLM model file from storage.
  Future<void> deleteModelFile() async {
    final dir = await _cacheDirectory();
    final file = File(_modelFilePath(dir));
    if (await file.exists()) {
      await file.delete();
    }
  }

  static const String _systemPrompt = '''
Kamu adalah editor video AI profesional untuk konten viral Shorts/Reels/TikTok.
Tugasmu adalah menganalisis transkrip percakapan video dengan stempel waktu dan memilih segmen-segmen terbaik yang paling menarik/viral.

Aturan Pemilihan Segmen:
1. Durasi tiap segmen HARUS antara 20 detik hingga maksimal 60 detik (endSec - startSec antara 20 dan 60).
2. Pilih momen yang memiliki hook kuat, poin penting, rahasia/tips, emosi, atau ajakan interaksi.
3. Tentukan startSec dan endSec (dalam detik angka bulat atau desimal) sesuai stempel waktu transkrip.
4. score: angka 80-100 seberapa menarik/viral segmen ini.
5. title: judul singkat memikat dalam bahasa Indonesia (maksimal 6 kata).
6. summary: ringkasan 1 kalimat dalam bahasa Indonesia.
7. transcript: teks percakapan pada segmen tersebut.
Balas HANYA dengan JSON valid berbentuk:
{"segments": [{"startSec": 10, "endSec": 45, "score": 95, "title": "Judul Menarik", "summary": "Ringkasan segmen.", "transcript": "Teks percakapan..."}]} tanpa teks pengantar lainnya.''';

  LlamaEngine? _engine;

  bool get isModelLoaded => _engine?.isReady ?? false;

  /// Loads (and caches) the GGUF model. No-op when already loaded.
  Future<void> loadModel({Function(double progress)? onProgress}) async {
    if (isModelLoaded) return;
    _engine ??= LlamaEngine(LlamaBackend());
    await _engine!.loadModelSource(
      _source,
      modelParams: const ModelParams(
        contextSize: 2048,
        gpuLayers: 0,
        useMlock: false,
      ),
      options: ModelLoadOptions(cacheDirectory: await _cacheDirectory()),
      onProgress: (p) => onProgress?.call(p.fraction ?? 0),
    );
  }

  /// Analyzes the timestamped transcript directly and extracts viral [VideoSegment]s.
  ///
  /// Returns an empty list if the model is unavailable or inference fails.
  Future<List<VideoSegment>> detectSegments({
    required String videoTitle,
    required Duration videoDuration,
    required List<WhisperWord> words,
    Function(double progress)? onProgress,
  }) async {
    if (words.isEmpty) return const [];

    try {
      await loadModel(onProgress: onProgress);
      if (!isModelLoaded) return const [];

      final formattedTranscript = _formatTimestampedTranscript(words);
      final totalSec = max(1, videoDuration.inSeconds);

      final messages = [
        LlamaChatMessage.fromText(
          role: LlamaChatRole.system,
          text: _systemPrompt,
        ),
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: _buildUserPrompt(videoTitle, totalSec, formattedTranscript),
        ),
      ];

      final result = await _engine!.createStructuredJson<Map<String, dynamic>>(
        messages,
        output: LlamaStructuredOutput.jsonObject(decoder: (json) => json),
        params: const GenerationParams(
          temp: 0.2,
          topP: 0.6,
          topK: 40,
          seed: 42,
          maxTokens: 1024,
        ),
        enableThinking: false,
      );

      return _decodeSegments(result, totalSec);
    } catch (_) {
      return const [];
    }
  }

  /// Groups words into timestamped blocks (e.g. `[00:15 - 00:25] Teks...`)
  /// so the LLM can easily understand timing without token bloat.
  String _formatTimestampedTranscript(List<WhisperWord> words) {
    if (words.isEmpty) return '';

    final buffer = StringBuffer();
    const groupDurationSec = 8.0;

    var currentGroupStart = words.first.start.inMilliseconds / 1000.0;
    var currentGroupWords = <String>[];

    String formatTime(double sec) {
      final m = (sec ~/ 60).toString().padLeft(2, '0');
      final s = (sec.toInt() % 60).toString().padLeft(2, '0');
      return '$m:$s';
    }

    for (final w in words) {
      final startSec = w.start.inMilliseconds / 1000.0;
      if (startSec - currentGroupStart >= groupDurationSec &&
          currentGroupWords.isNotEmpty) {
        final endSec = words[words.indexOf(w) - 1].end.inMilliseconds / 1000.0;
        buffer.writeln(
          '[${formatTime(currentGroupStart)} - ${formatTime(endSec)} (${currentGroupStart.toInt()}s-${endSec.toInt()}s)] ${currentGroupWords.join(" ")}',
        );
        currentGroupStart = startSec;
        currentGroupWords = [];
      }
      currentGroupWords.add(w.word);
    }

    if (currentGroupWords.isNotEmpty) {
      final endSec = words.last.end.inMilliseconds / 1000.0;
      buffer.writeln(
        '[${formatTime(currentGroupStart)} - ${formatTime(endSec)} (${currentGroupStart.toInt()}s-${endSec.toInt()}s)] ${currentGroupWords.join(" ")}',
      );
    }

    return buffer.toString();
  }

  String _buildUserPrompt(
    String videoTitle,
    int totalSeconds,
    String formattedTranscript,
  ) {
    return '''
Judul Video: ${_clip(videoTitle, 150)}
Total Durasi Video: $totalSeconds detik

Transkrip Percakapan Bertimestamp:
$formattedTranscript

Pilih segmen-segmen terbaik (masing-masing 20 s/d 60 detik) untuk dijadikan Shorts/Reels!''';
  }

  List<VideoSegment> _decodeSegments(Map<String, dynamic> json, int totalSec) {
    final raw = json['segments'];
    if (raw is! List || raw.isEmpty) return const [];

    final segments = <VideoSegment>[];
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      if (item is! Map<String, dynamic>) continue;

      var startSec = ((item['startSec'] as num?)?.toDouble() ?? 0.0).clamp(
        0.0,
        totalSec.toDouble(),
      );
      var endSec = ((item['endSec'] as num?)?.toDouble() ?? (startSec + 30.0))
          .clamp(0.0, totalSec.toDouble());

      if (endSec <= startSec) {
        endSec = min(totalSec.toDouble(), startSec + 30.0);
      }

      // Ensure segment duration does not exceed 60s
      if (endSec - startSec > 60.0) {
        endSec = startSec + 60.0;
      }

      final score = ((item['score'] as num?)?.toDouble() ?? 88.0).clamp(
        80.0,
        99.5,
      );
      final title = item['title']?.toString().trim() ?? '';
      final summary = item['summary']?.toString().trim() ?? '';
      final transcript = item['transcript']?.toString().trim() ?? '';

      segments.add(
        VideoSegment(
          id: 'seg_${i + 1}',
          title: title.isNotEmpty ? title : '💡 Highlight Menarik #${i + 1}',
          startTime: Duration(milliseconds: (startSec * 1000).round()),
          endTime: Duration(milliseconds: (endSec * 1000).round()),
          viralScore: double.parse(score.toStringAsFixed(1)),
          summary: summary.isNotEmpty
              ? summary
              : 'Segmen pilihan AI dengan potensi engagement tinggi.',
          transcript: transcript.isNotEmpty
              ? transcript
              : 'Transkrip otomatis dari Whisper AI.',
        ),
      );
    }

    segments.sort((a, b) => a.startTime.compareTo(b.startTime));
    return segments;
  }

  /// Frees the model from memory after grading.
  Future<void> unloadModel() async {
    final engine = _engine;
    if (engine == null) return;
    try {
      await engine.dispose();
    } catch (_) {
      // Best-effort: memory pressure should never break the render flow.
    } finally {
      _engine = null;
    }
  }

  static String _clip(String value, int maxLength) {
    final v = value.replaceAll('"', '');
    return v.length <= maxLength ? v : '${v.substring(0, maxLength)}...';
  }
}
