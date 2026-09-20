import 'dart:io';

import 'package:app/lan/transfer_worker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HttpTransferServer.start fails fast on invalid bind address', () async {
    final server = HttpTransferServer(
      onFileReceived: (
        _,
        __,
        ___, {
        messageId,
        senderLocalId,
        lastModifiedMs,
      }) {},
    );
    addTearDown(server.stop);

    // Invalid IPv4 makes HttpServer.bind fail in the worker. Before the fix,
    // the parent waited forever on readyCompleter because the worker returned
    // silently without notifying. Now it must surface an error quickly.
    await expectLater(
      server
          .start(
            '256.256.256.256',
            9080,
            1,
            Directory.systemTemp.path,
          )
          .timeout(const Duration(seconds: 8)),
      throwsA(anything),
    );
  });

  test('HttpTransferServer.start succeeds on loopback free port', () async {
    final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();

    final server = HttpTransferServer(
      onFileReceived: (
        _,
        __,
        ___, {
        messageId,
        senderLocalId,
        lastModifiedMs,
      }) {},
    );
    addTearDown(server.stop);

    final url = await server
        .start(
          InternetAddress.loopbackIPv4.address,
          port,
          1,
          Directory.systemTemp.path,
        )
        .timeout(const Duration(seconds: 10));

    expect(url, isNotNull);
    expect(url, contains(':$port'));
  });

  test('LAN HTTP CORS includes Private-Network for reverse-pull preflight', () async {
    final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();

    final server = HttpTransferServer(
      onFileReceived: (
        _,
        __,
        ___, {
        messageId,
        senderLocalId,
        lastModifiedMs,
      }) {},
    );
    addTearDown(server.stop);

    final url = await server.start(
      InternetAddress.loopbackIPv4.address,
      port,
      1,
      Directory.systemTemp.path,
    );
    expect(url, isNotNull);

    final client = HttpClient();
    addTearDown(client.close);
    final request = await client.openUrl(
      'OPTIONS',
      Uri.parse('$url/download?offerId=test'),
    );
    request.headers.set('Origin', 'http://localhost:3000');
    request.headers.set('Access-Control-Request-Method', 'GET');
    request.headers.set('Access-Control-Request-Private-Network', 'true');
    final response = await request.close();
    await response.drain<void>();

    expect(response.statusCode, HttpStatus.noContent);
    expect(response.headers.value('access-control-allow-origin'), '*');
    expect(
      response.headers.value('access-control-allow-private-network'),
      'true',
    );
  });
}
