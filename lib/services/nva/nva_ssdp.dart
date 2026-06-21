import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/services/nva/nva_handshake.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

/// NVA SSDP 组播广播器
///
/// 向 239.255.255.250:1900 定时发送 SSDP NOTIFY,
/// 声明 DLNA MediaRenderer + NVA NirvanaControl 服务。
class NvaSsdp {
  static const _multicastAddr = '239.255.255.250';
  static const _multicastPort = 1900;

  RawDatagramSocket? _socket;
  Timer? _timer;
  bool _running = false;

  final String usn;
  final String serverUuid;
  final int httpPort;
  final String friendlyName;
  final String manufacturer;
  final String modelName;

  int _bootId = 0;

  NvaSsdp({
    required this.httpPort,
    String? serverUuid,
    this.friendlyName = 'PiliPlus TV',
    this.manufacturer = 'Bilibili Inc.',
    this.modelName = 'PiliPlus',
  })  : serverUuid = serverUuid ?? NvaUuid.generateServerUuid(),
        usn = 'uuid:${serverUuid ?? NvaUuid.generateServerUuid()}';

  bool get isRunning => _running;

  String? _cachedAddr;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    _bootId++;

    // 缓存本机地址
    _cachedAddr = await _resolveAddr();

    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _socket!.broadcastEnabled = true;

    // 立即发送
    _broadcast();

    // 每30秒重发 (实际DLNA约1800秒, NVA更频繁)
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _broadcast());

    if (kDebugMode) debugPrint('NVA SSDP started');
  }

  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    _timer = null;

    // 发送 byebye
    if (_socket != null) {
      _broadcast(nts: 'ssdp:byebye');
      await Future.delayed(const Duration(milliseconds: 100));
      _socket!.close();
      _socket = null;
    }
    if (kDebugMode) debugPrint('NVA SSDP stopped');
  }

  void _broadcast({String nts = 'ssdp:alive'}) {
    if (_socket == null) return;

    final location = _cachedAddr;
    if (location == null) return;

    final locationUrl = 'http://$location:${httpPort}/description.xml';
    final cacheControl = nts == 'ssdp:byebye' ? 'max-age=0' : 'max-age=1800';

    final types = [
      'uuid:$usn::upnp:rootdevice',
      'uuid:$usn',
      'uuid:$usn::urn:schemas-upnp-org:device:MediaRenderer:1',
      'uuid:$usn::urn:schemas-upnp-org:service:RenderingControl:1',
      'uuid:$usn::urn:schemas-upnp-org:service:ConnectionManager:1',
      'uuid:$usn::urn:schemas-upnp-org:service:AVTransport:1',
      // NVA 专属
      'uuid:$usn::urn:schemas-upnp-org:service:NirvanaControl:3',
    ];

    for (final nt in types) {
      final msg = StringBuffer();
      msg.writeln('NOTIFY * HTTP/1.1');
      msg.writeln('HOST: $_multicastAddr:$_multicastPort');
      msg.writeln('CACHE-CONTROL: $cacheControl');
      msg.writeln('LOCATION: $locationUrl');
      msg.writeln('NT: $nt');
      msg.writeln('NTS: $nts');
      msg.writeln('SERVER: Linux/3.0.0, UPnP/1.0, Platinum/1.0.5.13');
      msg.writeln('USN: $nt');
      msg.writeln('BOOTID.UPNP.ORG: $_bootId');
      msg.writeln('CONFIGID.UPNP.ORG: 0');
      msg.writeln();

      final data = msg.toString().codeUnits;
      _socket!.send(data, InternetAddress(_multicastAddr), _multicastPort);
    }
  }

  /// 响应 M-SEARCH
  void respondToMSearch(RawDatagramSocket socket, InternetAddress remoteAddr,
      int remotePort, String st) {
    final location = _cachedAddr;
    if (location == null) return;
    final locationUrl = 'http://$location:${httpPort}/description.xml';

    final ntList = [
      'uuid:$usn::upnp:rootdevice',
      'uuid:$usn',
      'uuid:$usn::urn:schemas-upnp-org:device:MediaRenderer:1',
      'uuid:$usn::urn:schemas-upnp-org:service:RenderingControl:1',
      'uuid:$usn::urn:schemas-upnp-org:service:ConnectionManager:1',
      'uuid:$usn::urn:schemas-upnp-org:service:AVTransport:1',
      'uuid:$usn::urn:schemas-upnp-org:service:NirvanaControl:3',
    ];

    for (final nt in ntList) {
      if (st != 'ssdp:all' && st != nt) continue;
      final msg = StringBuffer();
      msg.writeln('HTTP/1.1 200 OK');
      msg.writeln('CACHE-CONTROL: max-age=1800');
      msg.writeln('LOCATION: $locationUrl');
      msg.writeln('EXT:');
      msg.writeln('ST: $nt');
      msg.writeln('USN: $nt');
      msg.writeln('SERVER: Linux/3.0.0, UPnP/1.0, Platinum/1.0.5.13');
      msg.writeln('BOOTID.UPNP.ORG: $_bootId');
      msg.writeln('CONFIGID.UPNP.ORG: 0');
      msg.writeln();

      socket.send(msg.toString().codeUnits, remoteAddr, remotePort);
    }
  }

  static Future<String?> _resolveAddr() async {
    for (final interface in await NetworkInterface.list()) {
      for (final addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
          return addr.address;
        }
      }
    }
    return null;
  }
}
