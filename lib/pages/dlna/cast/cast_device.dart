import 'dart:async';

/// 投屏设备抽象接口
///
/// 统一 DLNA 和 NVA 两种协议的投屏操作。
/// 发送端通过此接口控制投屏目标设备。
abstract class CastDevice {
  /// 设备唯一标识 (UUID)
  String get uuid;

  /// 设备显示名称
  String get deviceName;

  /// 设备地址
  String get host;

  /// 是否支持 NVA 协议
  bool get isNvaDevice;

  /// 是否已连接
  bool get isConnected;

  /// 连接事件的流
  Stream<CastDeviceEvent> get events;

  /// 建立连接
  Future<void> connect();

  /// 断开连接
  Future<void> disconnect();

  /// 播放视频
  /// [url] 视频地址
  /// [title] 标题
  /// [metadata] NVA协议的附加元数据 (aid, cid, epid 等)
  Future<void> play({
    required String url,
    required String title,
    Map<String, dynamic>? metadata,
  });

  /// 暂停
  Future<void> pause();

  /// 恢复播放
  Future<void> resume();

  /// 停止
  Future<void> stop();

  /// 跳转到指定位置 (秒)
  Future<void> seek(int seconds);

  /// 设置音量 (0-100)
  Future<void> setVolume(int volume);

  /// 获取音量
  Future<int?> getVolume();

  /// 设置播放速度
  Future<void> setSpeed(double speed);

  /// 切换清晰度
  Future<void> switchQuality(int qn);

  /// 切换弹幕开关
  Future<void> toggleDanmaku(bool open);
}

/// 投屏设备事件
class CastDeviceEvent {
  final CastEventType type;
  final Map<String, dynamic>? data;

  const CastDeviceEvent({required this.type, this.data});
}

enum CastEventType {
  connected,
  disconnected,
  progressChanged, // data: {duration, position}
  playStateChanged, // data: {playState: 3-7}
  speedChanged, // data: {currSpeed, supportSpeedList}
  qnChanged, // data: {curQn, supportQnList, userDesireQn}
  episodeChanged,
  danmakuChanged,
  error,
}
