import 'dart:math';

import 'package:uuid/uuid.dart';

/// NVA 握手: 客户端 → 服务端请求
class NvaHandshakeRequest {
  final String method; // SETUP 或 RESTORE
  final String session;
  final int nvaVersion;
  final String uuid;
  final String userAgent;
  final String host;

  const NvaHandshakeRequest({
    required this.method,
    required this.session,
    required this.nvaVersion,
    required this.uuid,
    required this.userAgent,
    required this.host,
  });

  /// 解析原始 HTTP 风格握手文本
  factory NvaHandshakeRequest.parse(String raw) {
    final lines = raw.split('\r\n');
    if (lines.isEmpty) throw FormatException('Empty handshake');

    // 首行: METHOD /projection NVA/1.0
    final firstParts = lines[0].split(' ');
    if (firstParts.length < 3) throw FormatException('Invalid request line');
    final method = firstParts[0];
    // final path = firstParts[1]; // /projection

    String session = '';
    int nvaVersion = 1;
    String uuid = '';
    String userAgent = '';
    String host = '';

    for (final line in lines.skip(1)) {
      final colonIdx = line.indexOf(':');
      if (colonIdx < 0) continue;
      final key = line.substring(0, colonIdx).trim();
      final value = line.substring(colonIdx + 1).trim();
      switch (key) {
        case 'Session':
          session = value;
        case 'NvaVersion':
          nvaVersion = int.tryParse(value) ?? 1;
        case 'UUID':
          uuid = value;
        case 'User-Agent':
          userAgent = value;
        case 'Host':
          host = value;
      }
    }

    return NvaHandshakeRequest(
      method: method,
      session: session,
      nvaVersion: nvaVersion,
      uuid: uuid,
      userAgent: userAgent,
      host: host,
    );
  }

  /// 构建客户端握手请求文本
  String build({
    required String host,
    required String session,
    required String clientUuid,
    bool isRestore = false,
  }) {
    final method = isRestore ? 'RESTORE' : 'SETUP';
    return '$method /projection NVA/1.0\r\n'
        'Session: $session\r\n'
        'NvaVersion: 1\r\n'
        'Connection: Keep-Alive\r\n'
        'UUID: $clientUuid\r\n'
        'User-Agent: Linux/3.0.0 UPnP/1.0 Platinum/1.0.5.13\r\n'
        'Host: $host\r\n\r\n';
  }

  bool get isSetup => method == 'SETUP';
  bool get isRestore => method == 'RESTORE';

  @override
  String toString() => 'NvaHandshakeRequest($method session=$session uuid=$uuid)';
}

/// NVA 握手: 服务端 → 客户端响应
class NvaHandshakeResponse {
  final int statusCode;
  final String statusText;
  final int nvaVersion;
  final String session;
  final String serverUuid;
  final String date;
  final String server;

  const NvaHandshakeResponse({
    this.statusCode = 200,
    this.statusText = 'OK',
    this.nvaVersion = 1,
    required this.session,
    required this.serverUuid,
    required this.date,
    required this.server,
  });

  /// 构建服务端握手响应文本
  String build() {
    return 'NVA/1.0 $statusCode $statusText\r\n'
        'NvaVersion: $nvaVersion\r\n'
        'Session: $session\r\n'
        'Connection: Keep-Alive\r\n'
        'UUID: $serverUuid\r\n'
        'Date: $date\r\n'
        'Content-Length: 0\r\n'
        'Server: $server\r\n\r\n';
  }

  factory NvaHandshakeResponse.ok({
    required String session,
    required String serverUuid,
    required String date,
  }) {
    return NvaHandshakeResponse(
      session: session,
      serverUuid: serverUuid,
      date: date,
      server: 'Linux/3.0.0, UPnP/1.0, Platinum/1.0.5.13',
    );
  }

  @override
  String toString() => 'NvaHandshakeResponse($statusCode $statusText session=$session)';
}

/// NVA UUID 生成工具
abstract final class NvaUuid {
  static final _uuid = const Uuid();
  static final _random = Random();

  /// TV 端 UUID: XY + 35字节 [0-9A-Z]
  static String generateServerUuid() {
    return _generateUuid(prefix: 'XY');
  }

  /// 客户端 UUID: Y + 35字节 [0-9A-Z]
  static String generateClientUuid() {
    return _generateUuid(prefix: 'Y');
  }

  static String _generateUuid({required String prefix}) {
    const chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final sb = StringBuffer(prefix);
    for (int i = 0; i < 35; i++) {
      sb.write(chars[_random.nextInt(chars.length)]);
    }
    return sb.toString();
  }

  /// 生成 session UUID
  static String generateSession() {
    return _uuid.v4();
  }
}
