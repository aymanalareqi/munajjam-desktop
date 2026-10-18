import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/alignment_models.dart';

class AlignmentJobStatus {
  final String status;
  final int progress;
  final String message;
  final List<AyahSegment>? data;
  final List<BreathGroup>? breathGroups;

  AlignmentJobStatus({
    required this.status,
    required this.progress,
    required this.message,
    this.data,
    this.breathGroups,
  });

  bool get isProcessing => status == 'processing';
  bool get isSuccess => status == 'success' || status == 'completed';
  bool get isError => status == 'error' || status == 'failed';
}

class AlignerApiService {
  final String baseUrl;
  final http.Client? client;
  final Duration statusTimeout;

  AlignerApiService({
    this.baseUrl = 'http://127.0.0.1:8000',
    this.client,
    this.statusTimeout = const Duration(seconds: 15),
  });

  /// Poll sequentially so a slow response cannot overwrite a newer result or
  /// apply the same successful alignment more than once.
  Stream<AlignmentJobStatus> watchJob(
    String jobId, {
    Duration pollInterval = const Duration(milliseconds: 700),
  }) async* {
    while (true) {
      final status = await checkJobStatus(jobId);
      yield status;
      if (status.isSuccess || status.isError) return;
      await Future<void>.delayed(pollInterval);
    }
  }

  Future<String> startAlignmentJob({
    required int surahId,
    required File audioFile,
    String method = 'hybrid',
    String riwaya = 'hafsh',
    String? referenceText,
    double chunkDuration = 2.0,
    int minSilenceMs = 200,
    int minSpeechMs = 750,
    int padMs = 30,
    String repetitionAttach = 'next',
  }) async {
    final uri = Uri.parse('$baseUrl/align/job/$surahId');
    final request = http.MultipartRequest('POST', uri);

    request.fields['method'] = method;
    request.fields['riwaya'] = riwaya;
    request.fields['chunk_duration'] = chunkDuration.toString();
    request.fields['min_silence_ms'] = minSilenceMs.toString();
    request.fields['min_speech_ms'] = minSpeechMs.toString();
    request.fields['pad_ms'] = padMs.toString();
    request.fields['repetition_attach'] = repetitionAttach;
    if (referenceText != null && referenceText.isNotEmpty) {
      request.fields['reference_text'] = referenceText;
    }

    final multipartFile = await http.MultipartFile.fromPath(
      'file',
      audioFile.path,
    );
    request.files.add(multipartFile);

    final response = await (() async {
      final streamedResponse = await (client?.send(request) ?? request.send());
      return http.Response.fromStream(streamedResponse);
    })().timeout(const Duration(minutes: 5));

    if (response.statusCode != 200) {
      throw Exception('فشل في بدء مهمة التزمين: ${response.body}');
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes));
    return data['job_id'] as String;
  }

  Future<AlignmentJobStatus> checkJobStatus(String jobId) async {
    final uri = Uri.parse('$baseUrl/align/status/$jobId');
    final headers = {'Accept': 'application/json'};
    final response =
        await (client?.get(uri, headers: headers) ??
                http.get(uri, headers: headers))
            .timeout(statusTimeout);

    if (response.statusCode != 200) {
      throw Exception('فشل في استعلام حالة المهمة: ${response.statusCode}');
    }

    final json = jsonDecode(utf8.decode(response.bodyBytes));
    final status = json['status'] as String? ?? 'processing';
    if (!{
      'processing',
      'success',
      'completed',
      'error',
      'failed',
    }.contains(status)) {
      throw FormatException('حالة مهمة غير معروفة: $status');
    }
    final progress = (json['progress'] as num?)?.toInt() ?? 0;
    final message =
        json['message'] as String? ?? json['error'] as String? ?? '';

    List<AyahSegment>? ayahs;
    if (json['data'] != null) {
      final list = json['data'] as List;
      ayahs = list.map((item) => AyahSegment.fromJson(item)).toList();
    }

    List<BreathGroup>? breaths;
    if (json['breath_groups'] != null) {
      final list = json['breath_groups'] as List;
      breaths = list.map((item) => BreathGroup.fromJson(item)).toList();
    }

    return AlignmentJobStatus(
      status: status,
      progress: progress,
      message: message,
      data: ayahs,
      breathGroups: breaths,
    );
  }
}
