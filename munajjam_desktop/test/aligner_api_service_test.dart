import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:munajjam_desktop/services/aligner_api_service.dart';

http.Response jobResponse(String status, {int progress = 10, String? error}) {
  return http.Response(
    jsonEncode({'status': status, 'progress': progress, 'error': error}),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

void main() {
  test('a failed backend job stops polling and exposes its error', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return calls == 1
          ? jobResponse('processing')
          : jobResponse('failed', error: 'inference failed');
    });
    final service = AlignerApiService(client: client);
    final statuses = await service
        .watchJob('job_1', pollInterval: Duration.zero)
        .toList();

    expect(statuses.map((s) => s.status), ['processing', 'failed']);
    expect(statuses.last.isError, isTrue);
    expect(statuses.last.message, 'inference failed');
    expect(calls, 2);
  });

  for (final state in ['success', 'completed']) {
    test('$state is delivered once and stops polling', () async {
      var calls = 0;
      final service = AlignerApiService(
        client: MockClient((_) async {
          calls++;
          return jobResponse(state, progress: 100);
        }),
      );
      final statuses = await service.watchJob('job_1').toList();
      expect(statuses.single.isSuccess, isTrue);
      expect(calls, 1);
    });
  }

  test('slow status requests never overlap', () async {
    var calls = 0;
    var inFlight = 0;
    var maxInFlight = 0;
    final service = AlignerApiService(
      client: MockClient((_) async {
        inFlight++;
        if (inFlight > maxInFlight) maxInFlight = inFlight;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        calls++;
        inFlight--;
        return jobResponse(calls == 3 ? 'success' : 'processing');
      }),
    );
    final statuses = await service
        .watchJob('job_1', pollInterval: const Duration(milliseconds: 1))
        .toList();
    expect(statuses.length, 3);
    expect(maxInFlight, 1);
  });

  test('an unresponsive status request produces a timeout', () async {
    final service = AlignerApiService(
      client: MockClient((_) => Completer<http.Response>().future),
      statusTimeout: const Duration(milliseconds: 20),
    );
    await expectLater(
      service.watchJob('job_1').toList(),
      throwsA(isA<TimeoutException>()),
    );
  });

  test(
    'an unknown status produces an error instead of polling forever',
    () async {
      final service = AlignerApiService(
        client: MockClient((_) async => jobResponse('unexpected')),
      );
      await expectLater(
        service.watchJob('job_1').toList(),
        throwsA(isA<FormatException>()),
      );
    },
  );
}
