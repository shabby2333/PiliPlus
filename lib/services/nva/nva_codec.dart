import 'dart:convert';
import 'dart:typed_data';

/// NVA 协议帧类型常量
abstract final class NvaFrameType {
  static const int command = 0xE0;
  static const int response = 0xC0;
  static const int ping = 0xE4;
}

/// NVA 二进制帧
///
/// 帧结构:
/// ```
/// [1b type] [1b paramCount] [4b seqId(BE)] [1b ver?] [params...]
/// ```
/// Command 帧参数: 前2个 [1b len][utf8], 第3个(可选JSON) [4b len][utf8]
/// Response 帧参数: [4b len][utf8]
/// Ping 帧: 无参数, 无版本字段
class NvaFrame {
  final int frameType;
  final int paramCount;
  final int seqId;
  final int? protocolVersion;
  final List<_NvaParam> _params;

  const NvaFrame._({
    required this.frameType,
    required this.paramCount,
    required this.seqId,
    this.protocolVersion,
    required List<_NvaParam> params,
  }) : _params = params;

  // ---- 编码 ----

  Uint8List encode() {
    final builder = BytesBuilder();
    final headerSize = frameType == NvaFrameType.ping ? 6 : 7;
    final header = ByteData(headerSize);
    header.setUint8(0, frameType);
    header.setUint8(1, paramCount);
    header.setUint32(2, seqId, Endian.big);
    if (frameType != NvaFrameType.ping) {
      header.setUint8(6, protocolVersion ?? 1);
    }
    builder.add(header.buffer.asUint8List());
    for (final p in _params) {
      builder.add(p.toBytes());
    }
    return builder.toBytes();
  }

  // ---- 解码 ----

  static NvaFrame decode(Uint8List data) {
    if (data.length < 6) throw FormatException('NVA frame too short');
    final frameType = data[0];
    final paramCount = data[1];
    final seqId = ByteData.sublistView(data, 2, 6).getUint32(0, Endian.big);

    int offset;
    int? protocolVersion;
    if (frameType == NvaFrameType.ping) {
      offset = 6;
    } else {
      if (data.length < 7) throw FormatException('NVA frame too short');
      protocolVersion = data[6];
      offset = 7;
    }

    final params = <_NvaParam>[];
    for (int i = 0; i < paramCount; i++) {
      // Command: 前2个 short(1b头), 第3个 long(4b头)
      // Response: 始终 long(4b头)
      final isShort = frameType == NvaFrameType.command && i < 2;
      final p = _NvaParam.decode(data, offset, isShort: isShort);
      params.add(p);
      offset = p.nextOffset;
    }

    return NvaFrame._(
      frameType: frameType,
      paramCount: paramCount,
      seqId: seqId,
      protocolVersion: protocolVersion,
      params: params,
    );
  }

  // ---- 工厂方法 ----

  factory NvaFrame.command({
    required int seqId,
    required String commandName,
    String? jsonBody,
    int protocolVersion = 1,
  }) {
    final params = <_NvaParam>[
      _NvaParam.short('Command'),
      _NvaParam.short(commandName),
    ];
    if (jsonBody != null) params.add(_NvaParam.long(jsonBody));
    return NvaFrame._(
      frameType: NvaFrameType.command,
      paramCount: params.length,
      seqId: seqId,
      protocolVersion: protocolVersion,
      params: params,
    );
  }

  factory NvaFrame.response({required int seqId, String? jsonBody}) {
    final params = <_NvaParam>[];
    if (jsonBody != null) params.add(_NvaParam.long(jsonBody));
    return NvaFrame._(
      frameType: NvaFrameType.response,
      paramCount: params.length,
      seqId: seqId,
      params: params,
    );
  }

  factory NvaFrame.ping({required int seqId}) {
    return NvaFrame._(
      frameType: NvaFrameType.ping,
      paramCount: 0,
      seqId: seqId,
      params: const [],
    );
  }

  // ---- 便捷访问 ----

  bool get isCommand => frameType == NvaFrameType.command;
  bool get isResponse => frameType == NvaFrameType.response;
  bool get isPing => frameType == NvaFrameType.ping;

  String? get commandName {
    if (!isCommand || _params.length < 2) return null;
    return _params[1].value;
  }

  String? get jsonParam {
    if (isCommand && _params.length >= 3) return _params[2].value;
    if (isResponse && _params.isNotEmpty) return _params[0].value;
    return null;
  }

  Map<String, dynamic>? get jsonMap {
    final j = jsonParam;
    if (j == null) return null;
    return jsonDecode(j) as Map<String, dynamic>;
  }

  @override
  String toString() {
    final t = isCommand ? 'CMD' : (isResponse ? 'RES' : 'PING');
    final b = StringBuffer('NvaFrame($t seq=$seqId');
    if (commandName != null) b.write(' cmd=$commandName');
    final j = jsonParam;
    if (j != null) b.write(' json=${j.length > 80 ? '${j.substring(0, 80)}...' : j}');
    b.write(')');
    return b.toString();
  }
}

// ---- 内部参数 ----

class _NvaParam {
  final String value;
  final int nextOffset;

  const _NvaParam._(this.value, this.nextOffset);

  /// 短参数: 编码时 1 byte 长度前缀
  factory _NvaParam.short(String value) => _NvaParam._(value, 0);

  /// 长参数: 编码时 4 bytes 长度前缀 (大端)
  factory _NvaParam.long(String value) => _NvaParam._(value, 0);

  Uint8List toBytes() {
    final raw = utf8.encode(value);
    // 编码时通过 nextOffset 区分: short 实例 nextOffset 始终为 0
    final lenSize = nextOffset == 0 ? 1 : 4;
    final buf = ByteData(lenSize + raw.length);
    if (lenSize == 1) {
      buf.setUint8(0, raw.length);
    } else {
      buf.setUint32(0, raw.length, Endian.big);
    }
    buf.buffer.asUint8List().setAll(lenSize, raw);
    return buf.buffer.asUint8List();
  }

  factory _NvaParam.decode(Uint8List data, int offset, {required bool isShort}) {
    if (offset >= data.length) throw FormatException('EOF at offset $offset');
    final len = isShort
        ? data[offset]
        : ByteData.sublistView(data, offset, offset + 4).getUint32(0, Endian.big);
    final headSize = isShort ? 1 : 4;
    final start = offset + headSize;
    if (start + len > data.length) {
      throw FormatException('Param len=$len exceeds data at offset=$offset');
    }
    final value = utf8.decode(data.sublist(start, start + len));
    return _NvaParam._(value, start + len);
  }
}
