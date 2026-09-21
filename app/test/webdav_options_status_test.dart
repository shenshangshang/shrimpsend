import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_client/webdav_client.dart' as dav;

void main() {
  test('OPTIONS 204 permits byte uploads and byte/stream downloads', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final payload = Uint8List.fromList([0, 1, 42, 128, 255]);
    var uploaded = <int>[];
    server.listen((request) async {
      switch (request.method) {
        case 'OPTIONS':
          request.response.statusCode = 204;
          break;
        case 'PUT':
          uploaded = await request.fold<List<int>>(
            [],
            (all, part) => all..addAll(part),
          );
          request.response.statusCode = 201;
          break;
        case 'GET':
          request.response.contentLength = payload.length;
          request.response.add(payload);
          break;
        default:
          request.response.statusCode = 405;
      }
      await request.response.close();
    });
    final client = dav.newClient('http://127.0.0.1:${server.port}/dav/');
    final directory = await Directory.systemTemp.createTemp(
      'webdav-options-test-',
    );
    try {
      await client.write('/test.bin', payload);
      expect(uploaded, payload);
      expect(await client.read('/test.bin'), payload);
      final destination = '${directory.path}/received.bin';
      await client.read2File('/test.bin', destination);
      expect(await File(destination).readAsBytes(), payload);
    } finally {
      client.c.close(force: true);
      await server.close(force: true);
      await directory.delete(recursive: true);
    }
  });

  for (final status in [200, 204, 403, 503]) {
    test('WebDAV connection probe handles HTTP $status', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <String>[];
      server.listen((request) async {
        requests.add(request.method);
        request.response.statusCode = status;
        await request.response.close();
      });
      final transport = dav.WdDio();
      final client = dav.Client(
        uri: 'http://127.0.0.1:${server.port}/dav/',
        c: transport,
        auth: const dav.Auth(user: '', pwd: ''),
      );
      try {
        if (status < 300) {
          await client.ping();
        } else {
          await expectLater(
            client.ping(),
            throwsA(
              isA<DioException>().having(
                (error) => error.response?.statusCode,
                'status',
                status,
              ),
            ),
          );
        }
        expect(requests, ['OPTIONS']);
      } finally {
        transport.close(force: true);
        await server.close(force: true);
      }
    });
  }
}
