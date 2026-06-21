import 'dart:convert';

// ============================================================
// NVA 客户端命令 (手机 → TV)
// ============================================================

/// 所有 NVA 客户端命令名称
abstract final class NvaClientCmd {
  static const String getTVInfo = 'GetTVInfo';
  static const String getVolume = 'GetVolume';
  static const String setVolume = 'SetVolume';
  static const String pause = 'Pause';
  static const String resume = 'Resume';
  static const String sendDanmaku = 'SendDanmaku';
  static const String switchDanmaku = 'SwitchDanmaku';
  static const String switchSpeed = 'SwitchSpeed';
  static const String switchQn = 'SwitchQn';
  static const String stop = 'Stop';
  static const String seek = 'Seek';
  static const String play = 'Play';
  static const String playUrl = 'PlayUrl';

  /// 是否需要 JSON 参数
  static bool hasJsonParam(String cmd) {
    return _jsonCmds.contains(cmd);
  }

  static const _jsonCmds = {
    setVolume,
    sendDanmaku,
    switchDanmaku,
    switchSpeed,
    switchQn,
    seek,
    play,
    playUrl,
  };
}

// ============================================================
// NVA 服务端命令 (TV → 手机)
// ============================================================

abstract final class NvaServerCmd {
  static const String onProgress = 'OnProgress';
  static const String onDanmakuSwitch = 'OnDanmakuSwitch';
  static const String onEpisodeSwitch = 'OnEpisodeSwitch';
  static const String onQnSwitch = 'OnQnSwitch';
  static const String speedChanged = 'SpeedChanged';
  static const String onPlayState = 'OnPlayState';
}

// ============================================================
// 播放状态常量 (OnPlayState)
// ============================================================

abstract final class NvaPlayState {
  /// 加载中
  static const int loading = 3;

  /// 播放中
  static const int playing = 4;

  /// 暂停
  static const int paused = 5;

  /// 媒体结束 (EOF)
  static const int ended = 6;

  /// 停止
  static const int stopped = 7;
}

// ============================================================
// 默认倍速支持列表
// ============================================================

const List<double> kDefaultSpeedList = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

// ============================================================
// JSON 参数模型
// ============================================================

class PlayParams {
  final String aid;
  final String cid;
  final String epid;
  final String seasonId;
  final String oid;
  final int contentType;
  final int seekTs;
  final String? accessKey;
  final int? currentQn;
  final int? desireQn;
  final bool? danmakuSwitchSave;
  final double? userDesireSpeed;

  const PlayParams({
    required this.aid,
    required this.cid,
    required this.epid,
    required this.seasonId,
    required this.oid,
    required this.contentType,
    this.seekTs = 0,
    this.accessKey,
    this.currentQn,
    this.desireQn,
    this.danmakuSwitchSave,
    this.userDesireSpeed,
  });

  Map<String, dynamic> toJson() => {
    'aid': aid,
    'cid': cid,
    'epid': epid,
    'season_id': seasonId,
    'oid': oid,
    'content_type': contentType,
    'seekTs': seekTs,
    if (accessKey != null) 'access_key': accessKey,
    if (currentQn != null) 'current_qn': currentQn,
    if (desireQn != null) 'desire_qn': desireQn,
    if (danmakuSwitchSave != null) 'danmakuSwitchSave': danmakuSwitchSave,
    if (userDesireSpeed != null) 'userDesireSpeed': userDesireSpeed,
  };

  factory PlayParams.fromJson(Map<String, dynamic> json) => PlayParams(
    aid: '${json['aid'] ?? ''}',
    cid: '${json['cid'] ?? ''}',
    epid: '${json['epid'] ?? ''}',
    seasonId: '${json['season_id'] ?? ''}',
    oid: '${json['oid'] ?? ''}',
    contentType: json['content_type'] ?? 1,
    seekTs: json['seekTs'] ?? 0,
    accessKey: json['access_key'],
    currentQn: json['current_qn'],
    desireQn: json['desire_qn'],
    danmakuSwitchSave: json['danmakuSwitchSave'],
    userDesireSpeed: (json['userDesireSpeed'] as num?)?.toDouble(),
  );

  String toJsonString() => jsonEncode(toJson());
}

class PlayUrlParams {
  final String url;
  final String title;

  const PlayUrlParams({required this.url, required this.title});

  Map<String, dynamic> toJson() => {'url': url, 'title': title};

  factory PlayUrlParams.fromJson(Map<String, dynamic> json) =>
      PlayUrlParams(url: json['url'] ?? '', title: json['title'] ?? '');

  String toJsonString() => jsonEncode(toJson());
}

class SeekParams {
  final int seekTs;

  const SeekParams({required this.seekTs});

  Map<String, dynamic> toJson() => {'seekTs': seekTs};

  factory SeekParams.fromJson(Map<String, dynamic> json) =>
      SeekParams(seekTs: json['seekTs'] ?? 0);

  String toJsonString() => jsonEncode(toJson());
}

class SetVolumeParams {
  final int volume;

  const SetVolumeParams({required this.volume});

  Map<String, dynamic> toJson() => {'volume': volume};

  factory SetVolumeParams.fromJson(Map<String, dynamic> json) =>
      SetVolumeParams(volume: json['volume'] ?? 0);

  String toJsonString() => jsonEncode(toJson());
}

class SwitchSpeedParams {
  final String speed;

  SwitchSpeedParams({required double speed}) : speed = speed.toString();

  Map<String, dynamic> toJson() => {'speed': speed};

  factory SwitchSpeedParams.fromJson(Map<String, dynamic> json) =>
      SwitchSpeedParams(speed: double.tryParse('${json['speed']}') ?? 1.0);

  String toJsonString() => jsonEncode(toJson());
}

class SwitchQnParams {
  final String qn;

  SwitchQnParams({required int qn}) : qn = qn.toString();

  Map<String, dynamic> toJson() => {'qn': qn};

  factory SwitchQnParams.fromJson(Map<String, dynamic> json) =>
      SwitchQnParams(qn: int.tryParse('${json['qn']}') ?? 0);

  String toJsonString() => jsonEncode(toJson());
}

class SwitchDanmakuParams {
  final bool open;

  const SwitchDanmakuParams({required this.open});

  Map<String, dynamic> toJson() => {'open': open ? 'true' : 'false'};

  factory SwitchDanmakuParams.fromJson(Map<String, dynamic> json) =>
      SwitchDanmakuParams(open: json['open'] == 'true' || json['open'] == true);

  String toJsonString() => jsonEncode(toJson());
}

class SendDanmakuParams {
  final int size;
  final int mRemoteDmId;
  final String content;
  final String action;
  final int type; // 1:滚动 5:上侧中央 4:下侧中央
  final int color; // 十进制RGB

  const SendDanmakuParams({
    this.size = 18,
    required this.mRemoteDmId,
    required this.content,
    this.action = '',
    this.type = 1,
    this.color = 0xFFFFFF,
  });

  Map<String, dynamic> toJson() => {
    'size': size,
    'mRemoteDmId': mRemoteDmId,
    'content': content,
    'action': action,
    'type': type,
    'color': color,
  };

  factory SendDanmakuParams.fromJson(Map<String, dynamic> json) =>
      SendDanmakuParams(
        size: json['size'] ?? 18,
        mRemoteDmId: json['mRemoteDmId'] ?? 0,
        content: json['content'] ?? '',
        action: json['action'] ?? '',
        type: json['type'] ?? 1,
        color: json['color'] ?? 0xFFFFFF,
      );

  String toJsonString() => jsonEncode(toJson());
}

// ---- 服务端广播参数 ----

class OnProgressParams {
  final int duration; // 秒
  final int position; // 秒

  const OnProgressParams({required this.duration, required this.position});

  Map<String, dynamic> toJson() => {'duration': duration, 'position': position};

  String toJsonString() => jsonEncode(toJson());
}

class OnPlayStateParams {
  final int playState;

  const OnPlayStateParams({required this.playState});

  Map<String, dynamic> toJson() => {'playState': playState};

  String toJsonString() => jsonEncode(toJson());
}

class OnDanmakuSwitchParams {
  final bool open;

  const OnDanmakuSwitchParams({required this.open});

  Map<String, dynamic> toJson() => {'open': open};

  String toJsonString() => jsonEncode(toJson());
}

class SpeedChangedParams {
  final double currSpeed;
  final List<double> supportSpeedList;

  const SpeedChangedParams({
    required this.currSpeed,
    this.supportSpeedList = kDefaultSpeedList,
  });

  Map<String, dynamic> toJson() => {
    'currSpeed': currSpeed,
    'supportSpeedList': supportSpeedList,
  };

  String toJsonString() => jsonEncode(toJson());
}

/// 清晰度描述项
class QnDescItem {
  final String description;
  final String displayDesc;
  final bool needLogin;
  final bool needVip;
  final int quality;
  final String superscript;

  const QnDescItem({
    this.description = '',
    this.displayDesc = '',
    this.needLogin = false,
    this.needVip = false,
    this.quality = 0,
    this.superscript = '',
  });

  Map<String, dynamic> toJson() => {
    'description': description,
    'displayDesc': displayDesc,
    'needLogin': needLogin,
    'needVip': needVip,
    'quality': quality,
    'superscript': superscript,
  };
}

class OnQnSwitchParams {
  final int curQn;
  final List<QnDescItem> supportQnList;
  final int userDesireQn;

  const OnQnSwitchParams({
    this.curQn = 0,
    this.supportQnList = const [],
    this.userDesireQn = 0,
  });

  Map<String, dynamic> toJson() => {
    'curQn': curQn,
    'supportQnList': supportQnList.map((e) => e.toJson()).toList(),
    'userDesireQn': userDesireQn,
  };

  String toJsonString() => jsonEncode(toJson());
}

class OnEpisodeSwitchPlayItem {
  final String aid;
  final String cid;
  final int contentType;
  final String epId;
  final String seasonId;

  const OnEpisodeSwitchPlayItem({
    this.aid = '',
    this.cid = '',
    this.contentType = 1,
    this.epId = '',
    this.seasonId = '',
  });

  Map<String, dynamic> toJson() => {
    'aid': aid,
    'cid': cid,
    'contentType': contentType,
    'epId': epId,
    'seasonId': seasonId,
  };
}

class OnEpisodeSwitchParams {
  final OnEpisodeSwitchPlayItem playItem;
  final String qnDesc;
  final String title;

  const OnEpisodeSwitchParams({
    required this.playItem,
    this.qnDesc = '',
    this.title = '',
  });

  Map<String, dynamic> toJson() => {
    'playItem': playItem.toJson(),
    'qnDesc': qnDesc,
    'title': title,
  };

  String toJsonString() => jsonEncode(toJson());
}
