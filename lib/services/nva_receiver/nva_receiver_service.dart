import 'dart:async';
import 'dart:ui' show Color;

import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:PiliPlus/services/nva/nva_command.dart';
import 'package:PiliPlus/services/nva/nva_handshake.dart';
import 'package:PiliPlus/services/nva/nva_http.dart';
import 'package:PiliPlus/services/nva/nva_server.dart';
import 'package:PiliPlus/services/nva/nva_session.dart';
import 'package:PiliPlus/services/nva/nva_ssdp.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/video_utils.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:get/get.dart';

/// NVA 接收端服务 (GetxService)
///
/// 统一管理 SSDP, HTTP, TCP 生命周期,
/// 并将 NVA 命令桥接到 PlPlayerController。
class NvaReceiverService extends GetxService {
  late final NvaTcpServer _tcp;
  late final NvaHttpServer _http;
  late final NvaSsdp _ssdp;

  final RxBool isRunning = false.obs;
  final RxString deviceName = 'PiliPlus TV'.obs;
  final RxInt connectedClients = 0.obs;

  // 当前播放的视频信息 (用于恢复连接时上报)
  String _currentAid = '';
  String _currentCid = '';
  String _currentEpid = '';
  int _currentQn = 0;

  Timer? _progressTimer;

  @override
  void onInit() {
    super.onInit();
    final savedName = GStorage.setting.get('dlna_name');
    if (savedName != null && savedName is String && savedName.isNotEmpty) {
      deviceName.value = savedName;
    }
    _tcp = NvaTcpServer();
    _http = NvaHttpServer(
      friendlyName: deviceName.value,
      serverUuid: _getOrCreateServerUuid(),
    );
    _ssdp = NvaSsdp(
      httpPort: 0,
      friendlyName: deviceName.value,
    );

    _registerCommands();
  }

  String _getOrCreateServerUuid() {
    const key = 'nva_server_uuid';
    final saved = GStorage.setting.get(key);
    if (saved is String && saved.isNotEmpty) return saved;
    final uuid = NvaUuid.generateServerUuid();
    GStorage.setting.put(key, uuid);
    return uuid;
  }

  // ---- 启动/停止 ----

  Future<void> start() async {
    if (isRunning.value) return;
    try {
      final port = await _http.start();
      _ssdp = NvaSsdp(
        httpPort: port,
        serverUuid: _http.serverUuid,
        friendlyName: deviceName.value,
      );
      await _ssdp.start();
      await _tcp.start();
      _tcp.onSessionConnected = (_) =>
          connectedClients.value = _tcp.sessionCount;
      _tcp.onSessionDisconnected = (_) =>
          connectedClients.value = _tcp.sessionCount;
      isRunning.value = true;
      if (kDebugMode) debugPrint('NVA Receiver started');
    } catch (e) {
      if (kDebugMode) debugPrint('NVA Receiver start failed: $e');
      await stop();
    }
  }

  Future<void> stop() async {
    try {
      await _tcp.stop();
    } catch (_) {}
    try {
      await _ssdp.stop();
    } catch (_) {}
    try {
      await _http.stop();
    } catch (_) {}
    _progressTimer?.cancel();
    isRunning.value = false;
    connectedClients.value = 0;
    if (kDebugMode) debugPrint('NVA Receiver stopped');
  }

  // ---- 更新设备名称 ----

  void updateDeviceName(String name) {
    deviceName.value = name;
    GStorage.setting.put('dlna_name', name);
    // 需要重启才生效
  }

  // ---- 命令注册 ----

  void _registerCommands() {
    _tcp.on(NvaClientCmd.getVolume, _handleGetVolume);
    _tcp.on(NvaClientCmd.setVolume, _handleSetVolume);
    _tcp.on(NvaClientCmd.pause, _handlePause);
    _tcp.on(NvaClientCmd.resume, _handleResume);
    _tcp.on(NvaClientCmd.stop, _handleStop);
    _tcp.on(NvaClientCmd.seek, _handleSeek);
    _tcp.on(NvaClientCmd.play, _handlePlay);
    _tcp.on(NvaClientCmd.playUrl, _handlePlayUrl);
    _tcp.on(NvaClientCmd.switchSpeed, _handleSwitchSpeed);
    _tcp.on(NvaClientCmd.switchQn, _handleSwitchQn);
    _tcp.on(NvaClientCmd.switchDanmaku, _handleSwitchDanmaku);
    _tcp.on(NvaClientCmd.sendDanmaku, _handleSendDanmaku);
    // GetTVInfo 暂不实现
  }

  // ---- 命令处理器 ----

  void _handleGetVolume(
    NvaSession session,
    Map<String, dynamic>? json,
    int reqSeqId,
  ) {
    final vol = ((PlPlayerController.getVolumeIfExists() ?? 0.5) * 100).round();
    session.sendResponse(reqSeqId, jsonBody: '{"volume":$vol}');
  }

  void _handleSetVolume(
    NvaSession session,
    Map<String, dynamic>? json,
    int reqSeqId,
  ) {
    if (json == null) return;
    final vol = (json['volume'] as num?)?.toDouble() ?? 0;
    PlPlayerController.setVolumeIfExists(vol / 100, showIndicator: false);
    session.sendResponse(reqSeqId);
  }

  void _handlePause(
    NvaSession session,
    Map<String, dynamic>? json,
    int reqSeqId,
  ) {
    PlPlayerController.pauseIfExists();
    session.sendResponse(reqSeqId);
  }

  void _handleResume(
    NvaSession session,
    Map<String, dynamic>? json,
    int reqSeqId,
  ) {
    PlPlayerController.playIfExists();
    session.sendResponse(reqSeqId);
  }

  void _handleStop(
    NvaSession session,
    Map<String, dynamic>? json,
    int reqSeqId,
  ) {
    PlPlayerController.pauseIfExists();
    _progressTimer?.cancel();
    session.sendResponse(reqSeqId);
  }

  void _handleSeek(
    NvaSession session,
    Map<String, dynamic>? json,
    int reqSeqId,
  ) {
    if (json == null) return;
    final seekTs = json['seekTs'] as int? ?? 0;
    PlPlayerController.seekToIfExists(
      Duration(seconds: seekTs),
      isSeek: false,
    );
    session.sendResponse(reqSeqId);
  }

  Future<void> _handlePlay(
    NvaSession session,
    Map<String, dynamic>? json,
    int reqSeqId,
  ) async {
    if (json == null) {
      session.sendResponse(reqSeqId);
      return;
    }

    final aid = '${json['aid'] ?? ''}';
    final cid = '${json['cid'] ?? ''}';
    final epid = '${json['epid'] ?? ''}';

    _currentAid = aid;
    _currentCid = cid;
    _currentEpid = epid;

    final desireQn = json['desire_qn'] as int? ?? 112;
    _currentQn = desireQn;

    // 回复空 Response
    session.sendResponse(reqSeqId);

    // 获取播放地址并播放
    await _loadAndPlay(cid, epid.isNotEmpty ? epid : aid);
  }

  Future<void> _handlePlayUrl(
    NvaSession session,
    Map<String, dynamic>? json,
    int reqSeqId,
  ) async {
    if (json == null) {
      session.sendResponse(reqSeqId);
      return;
    }

    session.sendResponse(reqSeqId);

    // 尝试解析 nva_ext 参数获取视频信息
    final uri = Uri.tryParse(json['url'] as String? ?? '');
    final nvaExt = uri?.queryParameters['nva_ext'];
    if (nvaExt != null) {
      // TODO: 解析 nva_ext 中的 content 参数
    }
  }

  void _handleSwitchSpeed(
    NvaSession session,
    Map<String, dynamic>? json,
    int reqSeqId,
  ) {
    if (json == null) return;
    final speed = double.tryParse('${json['speed']}') ?? 1.0;
    PlPlayerController.instance?.setPlaybackSpeed(speed);
    session.sendResponse(reqSeqId);
  }

  Future<void> _handleSwitchQn(
    NvaSession session,
    Map<String, dynamic>? json,
    int reqSeqId,
  ) async {
    if (json == null) return;
    final qn = int.tryParse('${json['qn']}') ?? 0;
    _currentQn = qn;
    session.sendResponse(reqSeqId);

    // 重新获取播放地址
    if (_currentCid.isNotEmpty) {
      final oid = _currentEpid.isNotEmpty ? _currentEpid : _currentAid;
      await _loadAndPlay(_currentCid, oid);
    }
  }

  void _handleSwitchDanmaku(
    NvaSession session,
    Map<String, dynamic>? json,
    int reqSeqId,
  ) {
    if (json == null) return;
    final open = json['open'] == 'true' || json['open'] == true;
    GStorage.setting.put(SettingBoxKey.enableShowDanmaku, open);
    // 广播弹幕开关状态到所有客户端
    _tcp.broadcast(
      NvaServerCmd.onDanmakuSwitch,
      jsonBody: OnDanmakuSwitchParams(open: open).toJsonString(),
    );
    session.sendResponse(reqSeqId);
  }

  void _handleSendDanmaku(
    NvaSession session,
    Map<String, dynamic>? json,
    int reqSeqId,
  ) {
    if (json == null) return;
    final params = SendDanmakuParams.fromJson(json);

    // 映射 NVA 弹幕类型到 canvas_danmaku 类型
    DanmakuItemType itemType;
    switch (params.type) {
      case 5:
        itemType = DanmakuItemType.top;
      case 4:
        itemType = DanmakuItemType.bottom;
      default:
        itemType = DanmakuItemType.scroll;
    }

    // 颜色转换: NVA 十进制 RGB → Flutter Color
    final color = Color(params.color | 0xFF000000);

    final controller = PlPlayerController.instance;
    if (controller?.danmakuController != null) {
      controller!.danmakuController!.addDanmaku(
        DanmakuContentItem(
          params.content,
          color: color,
          type: itemType,
          extra: _makeExtra(params.size),
        ),
      );
    }

    session.sendResponse(reqSeqId);
  }

  static dynamic _makeExtra(int size) => null; // 简化: 不需要自定义 extra

  // ---- 播放器桥接 ----

  Future<void> _loadAndPlay(String cidStr, String oidStr) async {
    final cid = int.tryParse(cidStr) ?? 0;
    final oid = int.tryParse(oidStr) ?? 0;
    // epid=oid 时 type=2 (PGC), 否则 type=1 (UGC)
    final playurlType = _currentEpid.isNotEmpty ? 2 : 1;

    final res = await VideoHttp.tvPlayUrl(
      cid: cid,
      objectId: oid,
      playurlType: playurlType,
      qn: _currentQn,
    );

    if (res case Success(:final response)) {
      final first = response.durl?.firstOrNull;
      if (first == null || first.playUrls.isEmpty) {
        if (kDebugMode) debugPrint('NVA: no play URLs');
        return;
      }

      VideoUtils.getCdnUrl(first.playUrls);
      // TODO: 使用现有播放系统加载并播放 URL
      // 目前先通过启动进度上报定时器
      _startProgressReporting();
    }
  }

  void _startProgressReporting() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _reportProgress();
    });
  }

  void _reportProgress() {
    final controller = PlPlayerController.instance;
    if (controller == null) return;

    final duration = controller.duration.value.inSeconds;
    final position = controller.position.inSeconds;

    _tcp.broadcast(
      NvaServerCmd.onProgress,
      jsonBody: OnProgressParams(
        duration: duration,
        position: position,
      ).toJsonString(),
    );

    // 播放状态
    final status = controller.playerStatus.value;
    int playState = NvaPlayState.loading;
    switch (status) {
      case PlayerStatus.playing:
        playState = NvaPlayState.playing;
      case PlayerStatus.paused:
        playState = NvaPlayState.paused;
      case PlayerStatus.completed:
        playState = NvaPlayState.ended;
    }

    _tcp.broadcast(
      NvaServerCmd.onPlayState,
      jsonBody: OnPlayStateParams(playState: playState).toJsonString(),
    );
  }

  @override
  void onClose() {
    stop();
    super.onClose();
  }
}
