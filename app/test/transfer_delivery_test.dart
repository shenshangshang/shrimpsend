import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app/lan/transfer_worker.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory destination;
  late HttpTransferServer server;
  late String url;
  late StreamController<String> arrivals;

  setUp(() async {
    destination = await Directory.systemTemp.createTemp('shrimpsend_delivery_');
    arrivals = StreamController<String>.broadcast();
    final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();
    server = HttpTransferServer(onFileReceived: (path, name, from,
        {messageId, senderLocalId, lastModifiedMs}) => arrivals.add(path));
    url = (await server.start('127.0.0.1', port, 2, destination.path,
        deviceId: 'test-receiver', deviceName: '中文电脑 🦐'))!;
  });

  tearDown(() async {
    await server.stop();
    await arrivals.close();
    await destination.delete(recursive: true);
  });

  test('device info encodes non-Latin names and malformed filenames do not stop the receiver', () async {
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    var request = await client.getUrl(Uri.parse('$url/device-info'));
    var response = await request.close().timeout(const Duration(seconds: 5));
    expect(response.statusCode, 200);
    expect(await response.transform(utf8.decoder).join(), contains('中文电脑 🦐'));
    request = await client.postUrl(Uri.parse('$url/transfer'));
    request.headers.set('X-File-Name', '%invalid');
    response = await request.close().timeout(const Duration(seconds: 5));
    expect(response.statusCode, 400);
    await response.drain<void>();
    request = await client.getUrl(Uri.parse('$url/probe'));
    response = await request.close().timeout(const Duration(seconds: 5));
    expect(response.statusCode, 200);
    await response.drain<void>();
  });

  test('HTTP push writes directly, preserves same-name files and zero bytes', () async {
    final original = File(p.join(destination.path, '测试.txt'));
    await original.writeAsString('keep me');
    for (final payload in [Uint8List.fromList([1, 2, 3]), Uint8List(0)]) {
      final arrival = arrivals.stream.first;
      await sendFileHttpSingle(url: url, fileName: '测试.txt',
          fileSize: payload.length, bytes: payload,
          localId: 'test-${payload.length}', toDeviceId: 'test-receiver');
      final path = await arrival.timeout(const Duration(seconds: 5));
      expect(p.dirname(path), destination.path);
      expect(await File(path).readAsBytes(), payload);
    }
    expect(await original.readAsString(), 'keep me');
  });

  test('HTTP push resumes disk partial, including a fully written partial', () async {
    final bytes = Uint8List.fromList(List.generate(4 * 1024 * 1024, (i) => i % 251));
    for (final offset in [1234567, bytes.length]) {
      final localId = 'resume-$offset';
      final id = makeFileId('resume.bin', bytes.length, localId: localId);
      await File(p.join(destination.path, '.lan_partial_$id'))
          .writeAsBytes(bytes.sublist(0, offset));
      final arrival = arrivals.stream.first;
      int? initialProgress;
      await sendFileHttpSingle(url: url, fileName: 'resume.bin',
          fileSize: bytes.length, bytes: bytes, localId: localId,
          onProgress: (sent, total) => initialProgress ??= sent);
      final path = await arrival.timeout(const Duration(seconds: 5));
      expect(initialProgress, offset);
      expect(sha256.convert(await File(path).readAsBytes()), sha256.convert(bytes));
    }
  });

  test('one-way HTTP pull resumes via Range into the selected folder', () async {
    final bytes = Uint8List.fromList(List.generate(1024 * 1024, (i) => i % 239));
    server.registerPullFile('test-offer', 'pull.bin', bytes.length, bytes: bytes);
    final partial = File(p.join(destination.path, 'pull.bin'));
    await partial.writeAsBytes(bytes.sublist(0, 345678));
    final result = await pullFileHttp(downloadUrl: '$url/download?offerId=test-offer',
        savePath: destination.path, existingFilePath: partial.path,
        senderLocalId: 'pull-test');
    expect(result.filePath, partial.path);
    expect(sha256.convert(await partial.readAsBytes()), sha256.convert(bytes));
  });

  test('truncated pull fails and preserves the partial for retry', () async {
    final source = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => source.close(force: true));
    source.listen((request) {
      request.response.headers.set('X-File-Name', 'truncated.bin');
      request.response.headers.set('X-File-Size', '1000');
      request.response.add(List.filled(100, 42));
      request.response.close();
    });
    String? partial;
    await expectLater(pullFileHttp(
        downloadUrl: 'http://127.0.0.1:${source.port}/download',
        savePath: destination.path, onFilePathReady: (path) => partial = path),
        throwsA(isA<HttpException>()));
    expect(await File(partial!).length(), 100);
  });
}
