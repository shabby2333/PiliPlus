import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:PiliPlus/pages/dlna/cast/cast_device.dart';
import 'package:PiliPlus/services/nva/nva_codec.dart';
import 'package:PiliPlus/services/nva/nva_command.dart';
import 'package:PiliPlus/services/nva/nva_handshake.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

/// NVA 投屏设备 (发送端)
///
/// 作为 TCP 客户端连接到 TV 的 NVA 服务器,
/// 实现播放控制、进度同步、清晰度切换等功能。
class NvaCastDevice extends CastDevice {
  @override
  final String uuid;

  @override
  final String deviceName;

  @override
  final String host;

  final int port;
  final String clientUuid;

  Socket? _socket;
  bool _handshakeDone = false;
  int _seqId = 0;
  bool _closed = false;

  final _eventController = StreamController<CastDeviceEvent>.broadcast();
  final List<int> _buffer = [];

  @override
  bool get isNvaDevice => true;

  @override
  bool get isConnected => _socket != null && _handshakeDone && !_closed;

  @override
  Stream<CastDeviceEvent> get events => _eventController.stream;

  NvaCastDevice({
    required this.uuid,
    required this.deviceName,
    required this.host,
    this.port = 9958,
    String? clientUuid,
  }) : clientUuid = clientUuid ?? NvaUuid.generateClientUuid();

  @override
  Future<void> connect() async {
    if (isConnected) return;
    _seqId = 0;
    _closed = false;

    _socket = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
    _socket!.done.then((_) {
      if (!_closed) {
        _handshakeDone = false;
        _emit(CastEventType.disconnected);
      }
    });

    // 发送握手
    final session = NvaUuid.generateSession();
    final req = NvaHandshakeRequest(
      method: 'SETUP',
      session: session,
      nvaVersion: 1,
      uuid: clientUuid,
      userAgent: 'Linux/3.0.0 UPnP/1.0 Platinum/1.0.5.13',
      host: '$host:$port',
    );
    _socket!.write(
        req.build(host: '$host:$port', session: session, clientUuid: clientUuid));

    // 读取握手响应
    final handshakeData = await _readHandshake();
    if (handshakeData == null) {
      _close('Handshake failed');
      return;
    }

    _handshakeDone = true;
    _emit(CastEventType.connected);

    // 开始监听帧
    _socket!.listen(
      _onData,
      onDone: () {
        if (!_closed) _emit(CastEventType.disconnected);
        _handshakeDone = false;
      },
      onError: (e) {
        _emit(CastEventType.error);
      },
      cancelOnError: true,
    );
  }

  Future<String?> _readHandshake() async {
    final completer = Completer<String?>();
    final buffer = StringBuffer();
    StreamSubscription<Uint8List>? sub;

    sub = _socket!.listen(
      (data) {
        buffer.write(utf8.decode(data, allowMalformed: true));
        final str = buffer.toString();
        final end = str.indexOf('\r\n\r\n');
        if (end >= 0) {
          sub?.cancel();
          final handshake = str.substring(0, end + 4);
          // 保存剩余数据
          final bytes = utf8.encode(handshake);
          final remaining = data.sublist(
              data.length - (buffer.length - bytes.length));
          if (remaining.isNotEmpty) _buffer.addAll(remaining);
          completer.complete(handshake);
        } else if (buffer.length > 4096) {
          sub?.cancel();
          completer.complete(null);
        }
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete(null);
      },
      onError: (_) {
        if (!completer.isCompleted) completer.complete(null);
      },
      cancelOnError: true,
    );

    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        sub?.cancel();
        return null;
      },
    );
  }

  void _onData(Uint8List data) {
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
        _buffer.removeRange(0, 6);
        continue;
      }

      if (_buffer.length < 7) return;
      int offset = 7;

      for (int i = 0; i < paramCount; i++) {
        final isShort = frameType == NvaFrameType.command && i < 2;
        final headSize = isShort ? 1 : 4;
        if (_buffer.length < offset + headSize) return;

        int paramLen;
        if (isShort) {
          paramLen = _buffer[offset];
        } else {
          paramLen = ByteData.sublistView(
                  Uint8List.fromList(_buffer.sublist(offset, offset + 4)))
              .getUint32(0, Endian.big);
        }
        offset += headSize + paramLen;
        if (_buffer.length < offset) return;
      }

      final data = Uint8List.fromList(_buffer.sublist(0, offset));
      _buffer.removeRange(0, offset);
      final frame = NvaFrame.decode(data);

      if (frame.isCommand) {
        _handleServerCommand(frame);
      }
    }
  }

  void _handleServerCommand(NvaFrame frame) {
    final cmd = frame.commandName;
    final data = frame.jsonMap;

    switch (cmd) {
      case NvaServerCmd.onProgress:
        if (data != null) {
          _emit(CastEventType.progressChanged, data: data);
        }
      case NvaServerCmd.onPlayState:
        if (data != null) {
          _emit(CastEventType.playStateChanged, data: data);
        }
      case NvaServerCmd.speedChanged:
        if (data != null) {
          _emit(CastEventType.speedChanged, data: data);
        }
      case NvaServerCmd.onQnSwitch:
        if (data != null) {
          _emit(CastEventType.qnChanged, data: data);
        }
      case NvaServerCmd.onEpisodeSwitch:
        if (data != null) {
          _emit(CastEventType.episodeChanged, data: data);
        }
      case NvaServerCmd.onDanmakuSwitch:
        if (data != null) {
          _emit(CastEventType.danmakuChanged, data: data);
        }
    }
  }

  // ---- 发送控制命令 ----

  void _send(String commandName, {String? jsonBody}) {
    if (!isConnected) return;
    _seqId++;
    final frame = NvaFrame.command(
      seqId: _seqId,
      commandName: commandName,
      jsonBody: jsonBody,
    );
    try {
      _socket?.add(frame.encode());
    } catch (e) {
      if (kDebugMode) debugPrint('NVA send error: $e');
    }
  }

  @override
  Future<void> play({
    required String url,
    required String title,
    Map<String, dynamic>? metadata,
  }) async {
    if (metadata != null) {
      // 使用 NVA Play 命令 (携带视频元数据)
      final params = PlayParams.fromJson(metadata);
      _send(NvaClientCmd.play, jsonBody: params.toJsonString());
    } else {
      // 使用 PlayUrl (iOS HD 客户端风格)
      final params = PlayUrlParams(url: url, title: title);
      _send(NvaClientCmd.playUrl, jsonBody: params.toJsonString());
    }
  }

  @override
  Future<void> pause() async {
    _send(NvaClientCmd.pause);
  }

  @override
  Future<void> resume() async {
    _send(NvaClientCmd.resume);
  }

  @override
  Future<void> stop() async {
    _send(NvaClientCmd.stop);
  }

  @override
  Future<void> seek(int seconds) async {
    _send(NvaClientCmd.seek,
        jsonBody: SeekParams(seekTs: seconds).toJsonString());
  }

  @override
  Future<void> setVolume(int volume) async {
    _send(NvaClientCmd.setVolume,
        jsonBody: SetVolumeParams(volume: volume).toJsonString());
  }

  @override
  Future<int?> getVolume() async {
    // NVA GetVolume 需要异步等待响应, 简化处理返回null
    return null;
  }

  @override
  Future<void> setSpeed(double speed) async {
    _send(NvaClientCmd.switchSpeed,
        jsonBody: SwitchSpeedParams(speed: speed).toJsonString());
  }

  @override
  Future<void> switchQuality(int qn) async {
    _send(NvaClientCmd.switchQn,
        jsonBody: SwitchQnParams(qn: qn).toJsonString());
  }

  @override
  Future<void> toggleDanmaku(bool open) async {
    _send(NvaClientCmd.switchDanmaku,
        jsonBody: SwitchDanmakuParams(open: open).toJsonString());
  }

  @override
  Future<void> disconnect() async {
    _close('User disconnect');
  }

  void _close(String reason) {
    if (_closed) return;
    _closed = true;
    _handshakeDone = false;
    try {
      _socket?.destroy();
    } catch (_) {}
    _socket = null;
    _emit(CastEventType.disconnected);
  }

  void _emit(CastEventType type, {Map<String, dynamic>? data}) {
    _eventController.add(CastDeviceEvent(type: type, data: data));
  }
}
