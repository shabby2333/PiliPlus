import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/services/nva/nva_handshake.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

/// NVA HTTP XML 描述服务器
///
/// 提供 DLNA 设备描述 XML, 以及 SCPD 服务描述。
/// 同时监听 SSDP M-SEARCH 请求 (UDP 1900端口)。
class NvaHttpServer {
  HttpServer? _http;
  RawDatagramSocket? _ssdpSocket;
  bool _running = false;

  final String serverUuid;
  final String friendlyName;
  final String manufacturer;
  final String manufacturerURL;
  final String modelDescription;
  final String modelName;
  final String modelNumber;
  final String serialNumber;
  final String xBrandName;
  final String hostVersion;
  final String ottVersion;
  final String channelName;
  final String capability;

  /// 获取实际绑定端口 (需在 start 后使用)
  int get port => _http?.port ?? 0;

  NvaHttpServer({
    String? serverUuid,
    this.friendlyName = 'PiliPlus TV',
    this.manufacturer = 'Bilibili Inc.',
    this.manufacturerURL = 'https://bilibili.com/',
    this.modelDescription = '云视听小电视',
    this.modelName = 'PiliPlus',
    this.modelNumber = '1024',
    this.serialNumber = '1024',
    this.xBrandName = 'Generic',
    this.hostVersion = '25',
    this.ottVersion = '104600',
    this.channelName = 'master',
    this.capability = '254',
  }) : serverUuid = serverUuid ?? NvaUuid.generateServerUuid();

  bool get isRunning => _running;

  String? _cachedAddr;

  /// 启动 HTTP 服务 + SSDP 监听
  Future<int> start({int port = 0}) async {
    if (_running) return this.port;

    // 预解析本机地址
    _cachedAddr = await _resolveAddr();

    _http = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _running = true;

    // 启动 SSDP M-SEARCH 监听
    _startSsdpListener();

    _http!.listen(_handleRequest);
    if (kDebugMode) {
      debugPrint('NVA HTTP server started on port ${_http!.port}');
    }
    return _http!.port;
  }

  Future<void> stop() async {
    _running = false;
    _ssdpSocket?.close();
    _ssdpSocket = null;
    await _http?.close(force: true);
    _http = null;
  }

  void _startSsdpListener() async {
    try {
      _ssdpSocket =
          await RawDatagramSocket.bind(InternetAddress.anyIPv4, 1900, reuseAddress: true);
      _ssdpSocket!.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = _ssdpSocket!.receive();
        if (datagram == null) return;
        final data = utf8.decode(datagram.data);
        if (!data.startsWith('M-SEARCH')) return;

        // 提取 ST header
        final stMatch = RegExp(r'ST:\s*(.+)', caseSensitive: false).firstMatch(data);
        if (stMatch == null) return;
        final st = stMatch.group(1)!.trim();

        _respondToMSearch(datagram.address, datagram.port, st);
      });
    } catch (e) {
      if (kDebugMode) debugPrint('NVA SSDP listener failed: $e (port 1900 busy)');
    }
  }

  void _respondToMSearch(
      InternetAddress remoteAddr, int remotePort, String st) {
    if (_http == null) return;
    final locationUrl = 'http://$_cachedAddr:${_http!.port}/description.xml';

    final ntList = [
      'uuid:$serverUuid::upnp:rootdevice',
      'uuid:$serverUuid',
      'uuid:$serverUuid::urn:schemas-upnp-org:device:MediaRenderer:1',
      'uuid:$serverUuid::urn:schemas-upnp-org:service:RenderingControl:1',
      'uuid:$serverUuid::urn:schemas-upnp-org:service:ConnectionManager:1',
      'uuid:$serverUuid::urn:schemas-upnp-org:service:AVTransport:1',
      'uuid:$serverUuid::urn:schemas-upnp-org:service:NirvanaControl:3',
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
      msg.writeln('BOOTID.UPNP.ORG: 1');
      msg.writeln('CONFIGID.UPNP.ORG: 0');
      msg.writeln();

      try {
        _ssdpSocket?.send(msg.toString().codeUnits, remoteAddr, remotePort);
      } catch (_) {}
    }
  }

  static Future<String?> _resolveAddr() async {
    for (final i in await NetworkInterface.list()) {
      for (final a in i.addresses) {
        if (a.type == InternetAddressType.IPv4 && !a.isLoopback) return a.address;
      }
    }
    return '127.0.0.1';
  }

  // ---- HTTP 路由 ----

  Future<void> _handleRequest(HttpRequest req) async {
    final path = req.uri.path;
    String xml;

    switch (path) {
      case '/description.xml':
        xml = _deviceDescription();
      case '/dlna/AVTransport.xml':
        xml = _avTransportScpd();
      case '/dlna/RenderingControl.xml':
        xml = _renderingControlScpd();
      case '/dlna/ConnectionManager.xml':
        xml = _connectionManagerScpd();
      case '/dlna/NirvanaControl.xml':
        xml = _nirvanaControlScpd();
      default:
        req.response.statusCode = 404;
        req.response.close();
        return;
    }

    req.response.headers.contentType = ContentType('text', 'xml', charset: 'utf-8');
    req.response.headers.set('Server',
        'Linux/3.0.0, UPnP/1.0, Platinum/1.0.5.13');
    req.response.write(xml);
    await req.response.close();
  }

  // ---- XML 模板 ----

  String _deviceDescription() => '''<?xml version="1.0"?>
<root xmlns:dlna="urn:schemas-dlna-org:device-1-0" xmlns="urn:schemas-upnp-org:device-1-0">
  <specVersion>
    <major>1</major>
    <minor>0</minor>
  </specVersion>
  <device>
    <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
    <UDN>uuid:$serverUuid</UDN>
    <friendlyName>$friendlyName</friendlyName>
    <manufacturer>$manufacturer</manufacturer>
    <manufacturerURL>$manufacturerURL</manufacturerURL>
    <modelDescription>$modelDescription</modelDescription>
    <modelName>$modelName</modelName>
    <modelNumber>$modelNumber</modelNumber>
    <modelURL>https://app.bilibili.com/</modelURL>
    <serialNumber>$serialNumber</serialNumber>
    <X_brandName>$xBrandName</X_brandName>
    <hostVersion>$hostVersion</hostVersion>
    <ottVersion>$ottVersion</ottVersion>
    <channelName>$channelName</channelName>
    <capability>$capability</capability>
    <dlna:X_DLNADOC xmlns:dlna="urn:schemas-dlna-org:device-1-0">DMR-1.50</dlna:X_DLNADOC>
    <dlna:X_DLNACAP xmlns:dlna="urn:schemas-dlna-org:device-1-0">playcontainer-1-0</dlna:X_DLNACAP>
    <serviceList>
      <service>
        <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
        <serviceId>urn:upnp-org:serviceId:AVTransport</serviceId>
        <controlURL>AVTransport/action</controlURL>
        <eventSubURL>AVTransport/event</eventSubURL>
        <SCPDURL>dlna/AVTransport.xml</SCPDURL>
      </service>
      <service>
        <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
        <serviceId>urn:upnp-org:serviceId:RenderingControl</serviceId>
        <controlURL>RenderingControl/action</controlURL>
        <eventSubURL>RenderingControl/event</eventSubURL>
        <SCPDURL>dlna/RenderingControl.xml</SCPDURL>
      </service>
      <service>
        <serviceType>urn:schemas-upnp-org:service:ConnectionManager:1</serviceType>
        <serviceId>urn:upnp-org:serviceId:ConnectionManager</serviceId>
        <controlURL>ConnectionManager/action</controlURL>
        <eventSubURL>ConnectionManager/event</eventSubURL>
        <SCPDURL>dlna/ConnectionManager.xml</SCPDURL>
      </service>
      <service>
        <serviceType>urn:app-bilibili-com:service:NirvanaControl:3</serviceType>
        <serviceId>urn:app-bilibili-com:serviceId:NirvanaControl</serviceId>
        <controlURL>NirvanaControl/action</controlURL>
        <eventSubURL>NirvanaControl/event</eventSubURL>
        <SCPDURL>dlna/NirvanaControl.xml</SCPDURL>
      </service>
    </serviceList>
  </device>
</root>''';

  String _avTransportScpd() => '''<?xml version="1.0"?>
<scpd xmlns="urn:schemas-upnp-org:service-1-0">
  <specVersion><major>1</major><minor>0</minor></specVersion>
  <actionList>
    <action><name>SetAVTransportURI</name></action>
    <action><name>Play</name></action>
    <action><name>Pause</name></action>
    <action><name>Stop</name></action>
    <action><name>Seek</name></action>
    <action><name>GetPositionInfo</name></action>
    <action><name>GetTransportInfo</name></action>
  </actionList>
</scpd>''';

  String _renderingControlScpd() => '''<?xml version="1.0"?>
<scpd xmlns="urn:schemas-upnp-org:service-1-0">
  <specVersion><major>1</major><minor>0</minor></specVersion>
  <actionList>
    <action><name>SetVolume</name></action>
    <action><name>GetVolume</name></action>
    <action><name>SetMute</name></action>
  </actionList>
</scpd>''';

  String _connectionManagerScpd() => '''<?xml version="1.0"?>
<scpd xmlns="urn:schemas-upnp-org:service-1-0">
  <specVersion><major>1</major><minor>0</minor></specVersion>
  <actionList>
    <action><name>GetProtocolInfo</name></action>
  </actionList>
</scpd>''';

  String _nirvanaControlScpd() => '''<?xml version="1.0"?>
<scpd xmlns="urn:schemas-upnp-org:service-1-0">
  <specVersion><major>1</major><minor>0</minor></specVersion>
  <actionList>
    <action><name>GetAppInfo</name></action>
  </actionList>
</scpd>''';
}
