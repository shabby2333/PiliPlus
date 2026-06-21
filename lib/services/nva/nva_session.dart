import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:PiliPlus/services/nva/nva_codec.dart';
import 'package:PiliPlus/services/nva/nva_handshake.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

/// 单客户端 NVA 会话
///
/// 管理一条 TCP 连接的完整生命周期:
/// - 握手 (SETUP/RESTORE) → 内部自动完成
/// - 接收 Command 帧并分发给 [onCommand] 回调
/// - 定时发送 Ping (每1秒)
/// - 发送 Response / ServerCommand
class NvaSession {
  final Socket _socket;
  late final String sessionId;
  late final String serverUuid;
  late final String clientUuid;
  bool _handshakeComplete = false;
  bool _closed = false;

  final Completer<NvaSession> _readyCompleter = Completer<NvaSession>();
  final void Function(NvaSession session, NvaFrame frame)? onCommand;

  int _seqId = 0;
  int _pingSeqId = 1;
  Timer? _pingTimer;

  final _frameController = StreamController<NvaFrame>.broadcast();
  Stream<NvaFrame> get frames => _frameController.stream;
  Future<NvaSession> get ready => _readyCompleter.future;

  /// 接受新连接 — 自动完成握手
  factory NvaSession.accept(
    Socket socket, {
    required String serverUuid,
    void Function(NvaSession session, NvaFrame frame)? onCommand,
  }) {
    final session = NvaSession._(socket,
        serverUuid: serverUuid, onCommand: onCommand);
    session._beginHandshake();
    return session;
  }

  NvaSession._(
    this._socket, {
    required String serverUuid,
    this.onCommand,
  }) : serverUuid = serverUuid;

  bool get isClosed => _closed;

  int get nextSeqId => ++_seqId;

  // ---- 握手 ----

  void _beginHandshake() {
    final buffer = <int>[];
    Timer? timeout = Timer(const Duration(seconds: 10), () {
      if (!_closed) {
        if (kDebugMode) debugPrint('NVA handshake timeout');
        close();
      }
    });

    _socket.listen(
      (data) {
        buffer.addAll(data);
        final str = utf8.decode(buffer, allowMalformed: true);
        final endIdx = str.indexOf('\r\n\r\n');
        if (endIdx < 0) {
          if (buffer.length > 4096) {
            timeout.cancel();
            close();
          }
          return;
        }
        timeout.cancel();

        final handshakeBytes = utf8.encode(str.substring(0, endIdx + 4));
        final remaining = buffer.sublist(handshakeBytes.length);

        try {
          final req = NvaHandshakeRequest.parse(
              utf8.decode(handshakeBytes));
          sessionId = req.session.isEmpty
              ? NvaUuid.generateSession()
              : req.session;
          clientUuid = req.uuid;

          final date = _httpDate();
          final resp = NvaHandshakeResponse.ok(
            session: sessionId,
            serverUuid: serverUuid,
            date: date,
          );
          _socket.write(resp.build());

          _handshakeComplete = true;
          if (kDebugMode) {
            debugPrint('NVA handshake OK: $clientUuid');
          }

          // 切换到帧解析模式
          _socket.listen(
            _onSocketData,
            onDone: () {
              if (kDebugMode) {
                debugPrint('NVA session closed by peer: $clientUuid');
              }
              close();
            },
            onError: (e) {
              if (kDebugMode) {
                debugPrint('NVA session error: $e');
              }
              close();
            },
            cancelOnError: true,
          );

          if (remaining.isNotEmpty) {
            _buffer = remaining;
            _parseFrames();
          }

          _startPing();
          _readyCompleter.complete(this);
        } catch (e) {
          if (kDebugMode) {
            debugPrint('NVA handshake parse error: $e');
          }
          close();
        }
      },
      onDone: () {
        timeout.cancel();
        if (!_handshakeComplete) close();
      },
      onError: (e) {
        timeout.cancel();
        if (kDebugMode) debugPrint('NVA handshake stream error: $e');
        close();
      },
      cancelOnError: true,
    );
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 1), (_) => _sendPing());
  }

  // ---- 帧解析 ----

  List<int> _buffer = [];

  void _onSocketData(Uint8List data) {
    _buffer.addAll(data);
    _parseFrames();
  }

  void _parseFrames() {
    while (_buffer.isNotEmpty && !_closed) {
      if (_buffer.length < 6) return;

      final frameType = _buffer[0];
      final paramCount = _buffer[1];

      if (frameType == NvaFrameType.ping) {
        if (_buffer.length < 6) return;
        final data = Uint8List.fromList(_buffer.sublist(0, 6));
        _buffer.removeRange(0, 6);
        _frameController.add(NvaFrame.decode(data));
        continue;
      }

      if (_buffer.length < 7) return;
      int offset = 7;
      bool needMore = false;

      for (int i = 0; i < paramCount; i++) {
        final isShort = frameType == NvaFrameType.command && i < 2;
        final headSize = isShort ? 1 : 4;
        if (_buffer.length < offset + headSize) {
          needMore = true;
          break;
        }

        int paramLen;
        if (isShort) {
          paramLen = _buffer[offset];
        } else {
          paramLen = ByteData.sublistView(
                  Uint8List.fromList(_buffer.sublist(offset, offset + 4)))
              .getUint32(0, Endian.big);
        }
        offset += headSize + paramLen;
        if (_buffer.length < offset) {
          needMore = true;
          break;
        }
      }

      if (needMore) return;

      final data = Uint8List.fromList(_buffer.sublist(0, offset));
      _buffer.removeRange(0, offset);
      final frame = NvaFrame.decode(data);

      if (frame.isCommand && onCommand != null) {
        onCommand!(this, frame);
      }
      _frameController.add(frame);
    }
  }

  // ---- 发送 ----

  void sendCommand(String commandName, {String? jsonBody}) {
    _sendFrame(NvaFrame.command(
      seqId: nextSeqId,
      commandName: commandName,
      jsonBody: jsonBody,
    ));
  }

  void sendResponse(int seqId, {String? jsonBody}) {
    _sendFrame(NvaFrame.response(seqId: seqId, jsonBody: jsonBody));
  }

  void _sendPing() {
    _sendFrame(NvaFrame.ping(seqId: _pingSeqId++));
  }

  void _sendFrame(NvaFrame frame) {
    if (_closed) return;
    try {
      _socket.add(frame.encode());
    } catch (e) {
      if (kDebugMode) debugPrint('NVA send error: $e');
      close();
    }
  }

  // ---- 生命周期 ----

  void close() {
    if (_closed) return;
    _closed = true;
    _pingTimer?.cancel();
    _pingTimer = null;
    try {
      _socket.destroy();
    } catch (_) {}
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.completeError('Session closed');
    }
    _frameController.close();
  }

  String _httpDate() {
    final now = DateTime.now().toUtc();
    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const mo = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${wd[now.weekday - 1]}, ${now.day.toString().padLeft(2, '0')} '
        '${mo[now.month - 1]} ${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')} GMT';
  }

  @override
  String toString() =>
      'NvaSession(client=$clientUuid session=$sessionId closed=$_closed)';
}
