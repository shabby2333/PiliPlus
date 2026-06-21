import 'dart:async';

import 'package:PiliPlus/pages/dlna/cast/cast_device.dart';
import 'package:PiliPlus/pages/dlna/cast/nva_cast_device.dart';
import 'package:PiliPlus/services/nva/nva_command.dart';
import 'package:dlna_dart/dlna.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

/// DLNA / NVA 投屏控制页面
///
/// 统一控制标准DLNA设备和NVA(哔哩必连)设备。
/// - 标准DLNA: 进度条拖拽、播放/暂停/停止、音量
/// - NVA: 以上全部 + 分辨率切换、倍速、弹幕开关
class DlnaControlPage extends StatefulWidget {
  final DLNADevice? dlnaDevice;
  final NvaCastDevice? nvaDevice;
  final String title;
  final Map<String, dynamic>? nvaMetadata;

  const DlnaControlPage({
    super.key,
    this.dlnaDevice,
    this.nvaDevice,
    required this.title,
    this.nvaMetadata,
  });

  bool get isNva => nvaDevice != null;

  @override
  State<DlnaControlPage> createState() => _DlnaControlPageState();
}

class _DlnaControlPageState extends State<DlnaControlPage> {
  // 播放状态
  bool _isPlaying = true;
  bool _isConnected = false;

  // 进度
  double _position = 0; // 秒
  double _duration = 1; // 秒 (避免除零)

  // NVA 特有
  int _currentQn = 0;
  List<Map<String, dynamic>> _supportQnList = [];
  double _currentSpeed = 1.0;
  bool _danmakuOpen = true;

  // 音量
  int _volume = 30;

  Timer? _progressTimer;
  StreamSubscription<CastDeviceEvent>? _nvaEventSub;
  bool _isDragging = false;
  double _dragValue = 0;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    if (widget.isNva && widget.nvaDevice != null) {
      // NVA连接和播放已在view.dart中完成，这里只需监听事件
      _isConnected = true;

      // 获取音量
      try {
        final vol = await widget.nvaDevice!.getVolume();
        if (vol != null) _volume = vol;
      } catch (_) {}

      // 监听 NVA 事件流 (进度、状态、清晰度、倍速等)
      _nvaEventSub = widget.nvaDevice!.events.listen(_onNvaEvent);
      if (mounted) setState(() {});
    } else if (widget.dlnaDevice != null) {
      // 标准DLNA: setUrl/play已在view.dart完成
      _isConnected = true;
      // 获取音量
      try {
        final volStr = await widget.dlnaDevice!.getVolume();
        final vp = VolumeParser(volStr);
        _volume = vp.current;
      } catch (_) {}
      // 开始轮询进度
      _startProgressPolling();
      if (mounted) setState(() {});
    }
  }

  void _startProgressPolling() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!_isConnected || widget.dlnaDevice == null || _isDragging) return;
      try {
        final posStr = await widget.dlnaDevice!.position();
        final pp = PositionParser(posStr);
        if (mounted) {
          setState(() {
            _position = pp.RelTimeInt.toDouble();
            _duration = pp.TrackDurationInt.toDouble();
            if (_duration <= 0) _duration = 1;
          });
        }
      } catch (_) {}
    });
  }

  void _onNvaEvent(CastDeviceEvent event) {
    final data = event.data;
    switch (event.type) {
      case CastEventType.progressChanged:
        if (data != null) {
          _position = (data['position'] as num?)?.toDouble() ?? _position;
          _duration = (data['duration'] as num?)?.toDouble() ?? _duration;
          if (_duration <= 0) _duration = 1;
          if (mounted && !_isDragging) setState(() {});
        }
      case CastEventType.playStateChanged:
        if (data != null) {
          final state = data['playState'] as int?;
          _isPlaying =
              state == NvaPlayState.playing || state == NvaPlayState.loading;
          if (mounted) setState(() {});
        }
      case CastEventType.speedChanged:
        if (data != null) {
          _currentSpeed =
              (data['currSpeed'] as num?)?.toDouble() ?? _currentSpeed;
          if (mounted) setState(() {});
        }
      case CastEventType.qnChanged:
        if (data != null) {
          _currentQn = (data['curQn'] as num?)?.toInt() ?? _currentQn;
          final list = data['supportQnList'];
          if (list is List) {
            _supportQnList = list.cast<Map<String, dynamic>>();
          }
          if (mounted) setState(() {});
        }
      case CastEventType.danmakuChanged:
        if (data != null) {
          _danmakuOpen = data['open'] == true || data['open'] == 'true';
          if (mounted) setState(() {});
        }
      case CastEventType.disconnected:
        _isConnected = false;
        if (mounted) setState(() {});
        SmartDialog.showToast('设备已断开');
      case CastEventType.error:
        SmartDialog.showToast('连接出错');
      default:
        break;
    }
  }

  // ======== 控制操作 ========

  Future<void> _togglePlayPause() async {
    if (widget.isNva && widget.nvaDevice != null) {
      if (_isPlaying) {
        await widget.nvaDevice!.pause();
      } else {
        await widget.nvaDevice!.resume();
      }
    } else if (widget.dlnaDevice != null) {
      if (_isPlaying) {
        await widget.dlnaDevice!.pause();
      } else {
        await widget.dlnaDevice!.play();
      }
    }
    _isPlaying = !_isPlaying;
  }

  Future<void> _stop() async {
    if (widget.isNva && widget.nvaDevice != null) {
      await widget.nvaDevice!.stop();
    } else if (widget.dlnaDevice != null) {
      await widget.dlnaDevice!.stop();
    }
    _isPlaying = false;
  }

  Future<void> _seekTo(double seconds) async {
    final s = seconds.round();
    if (widget.isNva && widget.nvaDevice != null) {
      await widget.nvaDevice!.seek(s);
      _position = seconds;
    } else if (widget.dlnaDevice != null) {
      await widget.dlnaDevice!.seek(PositionParser.toStr(s));
    }
  }

  Future<void> _setVolume(int vol) async {
    if (widget.isNva && widget.nvaDevice != null) {
      await widget.nvaDevice!.setVolume(vol);
    } else if (widget.dlnaDevice != null) {
      await widget.dlnaDevice!.volume(vol);
    }
    _volume = vol;
  }

  Future<void> _setSpeed(double speed) async {
    if (widget.isNva && widget.nvaDevice != null) {
      await widget.nvaDevice!.setSpeed(speed);
      _currentSpeed = speed;
    }
  }

  Future<void> _switchQn(int qn) async {
    if (widget.isNva && widget.nvaDevice != null) {
      await widget.nvaDevice!.switchQuality(qn);
      _currentQn = qn;
    }
  }

  Future<void> _toggleDanmaku() async {
    if (widget.isNva && widget.nvaDevice != null) {
      final newVal = !_danmakuOpen;
      await widget.nvaDevice!.toggleDanmaku(newVal);
      _danmakuOpen = newVal;
    }
  }

  // ======== UI ========

  String _formatTime(double seconds) {
    final s = seconds.round();
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _nvaEventSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = ColorScheme.of(context);
    final progress = _isDragging ? _dragValue : _position;
    final progressPct = _duration > 0 ? progress / _duration : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            widget.nvaDevice?.disconnect();
            Get.back();
          },
        ),
        actions: [
          if (widget.isNva)
            IconButton(
              icon: Icon(
                _danmakuOpen
                    ? Icons.closed_caption
                    : Icons.closed_caption_disabled,
                color: _danmakuOpen ? cs.primary : null,
              ),
              tooltip: '弹幕',
              onPressed: _toggleDanmaku,
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // ---- 进度条 ----
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 16,
                  ),
                ),
                child: Slider(
                  value: progressPct.clamp(0.0, 1.0),
                  onChanged: (v) {
                    _isDragging = true;
                    _dragValue = v * _duration;
                    setState(() {});
                  },
                  onChangeEnd: (v) {
                    _isDragging = false;
                    _seekTo(v * _duration);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatTime(progress),
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      _formatTime(_duration),
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ---- 播放控制 ----
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 后退10秒
                  IconButton.filled(
                    icon: const Icon(Icons.replay_10),
                    onPressed: _isConnected
                        ? () => _seekTo(progress - 10)
                        : null,
                  ),
                  const SizedBox(width: 16),
                  // 播放/暂停
                  IconButton.filled(
                    style: IconButton.styleFrom(
                      minimumSize: const Size(64, 64),
                    ),
                    icon: Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      size: 36,
                    ),
                    onPressed: _isConnected ? _togglePlayPause : null,
                  ),
                  const SizedBox(width: 16),
                  // 前进10秒
                  IconButton.filled(
                    icon: const Icon(Icons.forward_10),
                    onPressed: _isConnected
                        ? () => _seekTo(progress + 10)
                        : null,
                  ),
                  const SizedBox(width: 24),
                  // 停止
                  IconButton(
                    icon: const Icon(Icons.stop),
                    onPressed: _isConnected ? _stop : null,
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ---- 音量 ----
              Row(
                children: [
                  Icon(
                    Icons.volume_up,
                    color: cs.onSurface.withValues(alpha: 0.6),
                  ),
                  Expanded(
                    child: Slider(
                      value: _volume.toDouble(),
                      min: 0,
                      max: 100,
                      divisions: 100,
                      label: '$_volume',
                      onChanged: (v) => _volume = v.round(),
                      onChangeEnd: (v) => _setVolume(v.round()),
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text('$_volume', textAlign: TextAlign.center),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ---- NVA 特有控制 ----
              if (widget.isNva) ...[
                const Divider(),
                const SizedBox(height: 12),

                // 倍速
                _buildSpeedSelector(cs),
                const SizedBox(height: 16),

                // 清晰度
                if (_supportQnList.isNotEmpty) _buildQnSelector(cs),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSpeedSelector(ColorScheme cs) {
    return Row(
      children: [
        Text(
          '倍速',
          style: TextStyle(color: cs.onSurface.withValues(alpha: 0.7)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: kDefaultSpeedList.map((speed) {
                final isSelected = (_currentSpeed - speed).abs() < 0.01;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('${speed}x'),
                    selected: isSelected,
                    onSelected: (_) => _setSpeed(speed),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQnSelector(ColorScheme cs) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _supportQnList.map((qn) {
        final quality = (qn['quality'] as num?)?.toInt() ?? 0;
        final desc =
            qn['displayDesc'] as String? ?? qn['description'] ?? '$quality';
        final isSelected = quality == _currentQn;
        return ChoiceChip(
          label: Text(desc),
          selected: isSelected,
          onSelected: (_) => _switchQn(quality),
        );
      }).toList(),
    );
  }
}
