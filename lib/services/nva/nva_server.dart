import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/services/nva/nva_handshake.dart';
import 'package:PiliPlus/services/nva/nva_session.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

/// NVA TCP 服务器
///
/// 绑定 0.0.0.0:9958, 管理多个 NvaSession。
/// 注册命令处理器后, 自动将收到的 Command 分发给对应处理器。
class NvaTcpServer {
  ServerSocket? _server;
  final _sessions = <String, NvaSession>{};
  bool _running = false;

  final String serverUuid;
  final _commandHandlers =
      <String, void Function(NvaSession session, Map<String, dynamic>? json, int reqSeqId)>{};

  void Function(NvaSession session)? onSessionConnected;
  void Function(NvaSession session)? onSessionDisconnected;

  NvaTcpServer({String? serverUuid})
      : serverUuid = serverUuid ?? NvaUuid.generateServerUuid();

  bool get isRunning => _running;
  Iterable<NvaSession> get sessions => _sessions.values;
  int get sessionCount => _sessions.length;

  /// 注册命令处理器
  void on(String commandName,
      void Function(NvaSession session, Map<String, dynamic>? json, int reqSeqId)
          handler) {
    _commandHandlers[commandName] = handler;
  }

  /// 启动服务器
  Future<void> start({String host = '0.0.0.0', int port = 9958}) async {
    if (_running) return;
    _server = await ServerSocket.bind(host, port);
    _running = true;
    if (kDebugMode) debugPrint('NVA TCP server started on $host:$port');
    _server!.listen(_accept);
  }

  /// 停止服务器
  Future<void> stop() async {
    _running = false;
    for (final s in List.of(_sessions.values)) {
      s.close();
    }
    _sessions.clear();
    await _server?.close();
    _server = null;
    if (kDebugMode) debugPrint('NVA TCP server stopped');
  }

  /// 向所有连接的客户端广播 Command
  void broadcast(String commandName, {String? jsonBody}) {
    for (final s in _sessions.values) {
      if (!s.isClosed) s.sendCommand(commandName, jsonBody: jsonBody);
    }
  }

  void _accept(Socket socket) {
    final remote = '${socket.remoteAddress.address}:${socket.remotePort}';
    if (kDebugMode) debugPrint('NVA TCP accept: $remote');

    final session = NvaSession.accept(
      socket,
      serverUuid: serverUuid,
      onCommand: _dispatch,
    );

    session.ready.then((_) {
      _sessions[session.clientUuid] = session;
      onSessionConnected?.call(session);
      // 监听关闭
      session.frames.listen(null, onDone: () {
        _sessions.remove(session.clientUuid);
        onSessionDisconnected?.call(session);
      });
    }).catchError((_) {
      // 握手失败
    });
  }

  void _dispatch(NvaSession session, dynamic frame) {
    final cmd = frame.commandName;
    final json = frame.jsonMap;
    final seq = frame.seqId;

    final handler = _commandHandlers[cmd];
    if (handler != null) {
      handler(session, json, seq);
    } else {
      if (kDebugMode) debugPrint('NVA unhandled command: $cmd');
      session.sendResponse(seq);
    }
  }
}
