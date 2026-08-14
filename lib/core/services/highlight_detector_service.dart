import 'dart:math';

import '../models/video_segment.dart';
import '../models/video_source.dart';
import 'whisper_service.dart';

/// Service providing fallback and time-partition segmentation for video sources
/// when the local LLM is unavailable or when video transcripts are empty.
class HighlightDetectorService {
  static const Duration maxClipDuration = Duration(seconds: 60);
  static const int minClipSeconds = 20;

  static int _maxSegmentsFor(int totalSeconds) {
    return (totalSeconds / 240).ceil().clamp(3, 15);
  }

  /// Partitions the video into proportional Shorts segments (20-60s) and
  /// populates the transcript text from Whisper word timestamps.
  Future<List<VideoSegment>> detectHighlights(
    VideoSource source, {
    List<WhisperWord> transcribedWords = const [],
  }) async {
    return partitionSegments(
      source: source,
      transcribedWords: transcribedWords,
    );
  }

  /// Deterministically partitions a video into optimal Shorts segments.
  List<VideoSegment> partitionSegments({
    required VideoSource source,
    List<WhisperWord> transcribedWords = const [],
  }) {
    final totalSeconds = max(1, source.duration.inSeconds);
    if (totalSeconds < minClipSeconds) {
      final transcript = transcribedWords.map((w) => w.word).join(' ').trim();
      return [
        VideoSegment(
          id: 'seg_1',
          title: 'Full Clip Highlight',
          startTime: Duration.zero,
          endTime: source.duration,
          viralScore: 92.5,
          summary:
              'Klip pendek berdurasi penuh dengan potensi engagement tinggi.',
          transcript: transcript.isNotEmpty
              ? transcript
              : 'Transkrip otomatis dari Whisper AI.',
        ),
      ];
    }

    final segments = <VideoSegment>[];
    final chunk = min(
      maxClipDuration.inSeconds,
      max(minClipSeconds, totalSeconds ~/ 3),
    );
    final count = _maxSegmentsFor(totalSeconds);

    var start = 0;
    var index = 0;
    while (start + minClipSeconds <= totalSeconds && index < count) {
      final end = min(totalSeconds, start + chunk);
      final segStart = Duration(seconds: start);
      final segEnd = Duration(seconds: end);

      // Extract words that fall into this segment window
      final segmentWords = transcribedWords.where((w) {
        final wStart = w.start.inMilliseconds / 1000.0;
        return wStart >= start && wStart < end;
      }).map((w) => w.word).toList();

      final transcriptText = segmentWords.join(' ').trim();
      final label = _fallbackLabel(index);

      segments.add(
        VideoSegment(
          id: 'seg_${index + 1}',
          title: '⚡ Segmen Percakapan $label',
          startTime: segStart,
          endTime: segEnd,
          viralScore: double.parse(
            (92.5 - index * 2.0).clamp(75.0, 99.0).toStringAsFixed(1),
          ),
          summary: 'Segmen percakapan yang berpotensi engagement tinggi.',
          transcript: transcriptText.isNotEmpty
              ? transcriptText
              : 'Transkrip otomatis dari Whisper AI.',
        ),
      );

      start = end;
      index++;
    }

    return segments;
  }

  static String _fallbackLabel(int index) {
    const ordinals = ['Pertama', 'Kedua', 'Ketiga', 'Keempat', 'Kelima'];
    if (index < ordinals.length) return ordinals[index];
    return '${index + 1}';
  }
}
