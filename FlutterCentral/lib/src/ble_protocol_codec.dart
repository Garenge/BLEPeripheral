import 'dart:convert';

const int bleProtocolVersion = 1;
const String bleDefaultPairCode = '135790';
const String bleProtocolOpChunk = 'chunk';
const int defaultBleMaxChunkStreams = 8;
const int defaultBleMaxChunkPartsPerStream = 256;
const int defaultBleMaxChunkBufferedBytes = 64 * 1024;

class BleProtocolCodec {
  const BleProtocolCodec();

  List<int> encodeRequest({
    required String operation,
    required String messageId,
    required Map<String, Object?> body,
    String? token,
  }) {
    final request = <String, Object?>{
      'v': bleProtocolVersion,
      'op': operation,
      'id': messageId,
      'body': body,
    };
    if (token != null && token.isNotEmpty) {
      request['token'] = token;
    }
    return utf8.encode(jsonEncode(request));
  }

  BleDecodedMessage decode(List<int> value) {
    if (_isEchoReply(value)) {
      final body = value.sublist(2);
      return BleDecodedMessage.legacyEcho(body: body, text: _decodeText(body));
    }

    final json = _tryDecodeJson(value);
    if (json != null && _isProtocolEnvelope(json)) {
      return BleDecodedMessage.protocol(
        envelope: json,
        token: tokenFromEnvelope(json),
      );
    }

    return BleDecodedMessage.raw(bytes: value, text: _decodeText(value));
  }

  String? tokenFromEnvelope(Map<String, dynamic> envelope) {
    final token = envelope['token'];
    if (token is String && token.isNotEmpty) {
      return token;
    }
    final body = envelope['body'];
    if (body is Map<String, dynamic>) {
      final bodyToken = body['token'];
      if (bodyToken is String && bodyToken.isNotEmpty) {
        return bodyToken;
      }
    }
    return null;
  }

  bool _isProtocolEnvelope(Map<String, dynamic> json) {
    return _nonNegativeInteger(json['v']) != null && json['op'] is String;
  }

  String summaryForProtocol(Map<String, dynamic> envelope) {
    final operation = envelope['op'] ?? '?';
    final id = envelope['id'] ?? '-';
    final hasToken = tokenFromEnvelope(envelope) == null ? 'no' : 'yes';
    final error = envelope['err'];
    if (error is Map) {
      return 'op=$operation id=$id token=$hasToken error=${error['code']} (${error['message']})';
    }
    return 'op=$operation id=$id token=$hasToken ok=${envelope['ok']}';
  }

  String capabilitySummaryForInfoBody(Map<dynamic, dynamic> body) {
    final operations = body['operations'];
    final protectedOperations = operations is Map
        ? _stringList(operations['protected'])
        : const <String>[];
    final commands = _commandNames(body['commands']);
    final events = body['events'] is List ? body['events'] as List : const [];
    final schema = body['capabilitySchema'] is String
        ? body['capabilitySchema']
        : 'unknown';

    final modes = eventRuleModesForInfoBody(body);
    return 'capabilities schema=$schema protected=${protectedOperations.join(",")} commands=${commands.join(",")} events=${events.length} rules=${modes.join(",")}';
  }

  String? eventRuleModeFromBody(Map<dynamic, dynamic> body) {
    final value = body['eventRuleMode'] ?? body['mode'];
    if (value is String && supportedEventRuleModes.contains(value)) {
      return value;
    }
    return null;
  }

  BleChunkFragment? chunkFragmentFromEnvelope(Map<dynamic, dynamic> envelope) {
    if (envelope['op'] != bleProtocolOpChunk) {
      return null;
    }
    final body = envelope['body'];
    if (body is! Map) {
      return null;
    }
    final stream = body['stream'];
    final index = body['index'];
    final count = body['count'];
    final encoding = body['encoding'];
    final encodedData = body['data'];
    if (stream is! String ||
        stream.isEmpty ||
        index is! num ||
        count is! num ||
        encoding != 'base64' ||
        encodedData is! String ||
        encodedData.isEmpty) {
      return null;
    }
    final indexValue = _nonNegativeInteger(index);
    final countValue = _positiveInteger(count);
    if (indexValue == null || countValue == null || indexValue >= countValue) {
      return null;
    }
    try {
      return BleChunkFragment(
        stream: stream,
        index: indexValue,
        count: countValue,
        bytes: base64Decode(encodedData),
      );
    } catch (_) {
      return null;
    }
  }

  List<String> eventRuleModesForInfoBody(Map<dynamic, dynamic> body) {
    return _stringList(
      body['eventRuleModes'],
    ).where(supportedEventRuleModes.contains).toList();
  }

  bool _isEchoReply(List<int> value) {
    return value.length >= 2 && value[0] == 0x00 && value[1] == 0xAA;
  }

  int? _nonNegativeInteger(Object? value) {
    if (value is! num ||
        !value.isFinite ||
        value < 0 ||
        value.truncateToDouble() != value) {
      return null;
    }
    return value.toInt();
  }

  int? _positiveInteger(Object? value) {
    final integer = _nonNegativeInteger(value);
    if (integer == null || integer == 0) {
      return null;
    }
    return integer;
  }

  Map<String, dynamic>? _tryDecodeJson(List<int> value) {
    try {
      final decoded = jsonDecode(utf8.decode(value));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  List<String> _commandNames(Object? commands) {
    if (commands is! List) {
      return const [];
    }
    return commands
        .whereType<Map>()
        .map((command) => command['name'])
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toList();
  }

  List<String> _stringList(Object? value) {
    if (value is! List) {
      return const [];
    }
    return value.whereType<String>().where((item) => item.isNotEmpty).toList();
  }

  String _decodeText(List<int> value) {
    try {
      return utf8.decode(value);
    } catch (_) {
      return value
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join(' ');
    }
  }
}

const List<String> supportedEventRuleModes = ['normal', 'quiet', 'burst'];

class BleDecodedMessage {
  const BleDecodedMessage._({
    required this.kind,
    this.envelope,
    this.token,
    this.body = const <int>[],
    this.bytes = const <int>[],
    this.text = '',
  });

  factory BleDecodedMessage.protocol({
    required Map<String, dynamic> envelope,
    String? token,
  }) {
    return BleDecodedMessage._(
      kind: BleDecodedMessageKind.protocol,
      envelope: envelope,
      token: token,
    );
  }

  factory BleDecodedMessage.legacyEcho({
    required List<int> body,
    required String text,
  }) {
    return BleDecodedMessage._(
      kind: BleDecodedMessageKind.legacyEcho,
      body: body,
      text: text,
    );
  }

  factory BleDecodedMessage.raw({
    required List<int> bytes,
    required String text,
  }) {
    return BleDecodedMessage._(
      kind: BleDecodedMessageKind.raw,
      bytes: bytes,
      text: text,
    );
  }

  final BleDecodedMessageKind kind;
  final Map<String, dynamic>? envelope;
  final String? token;
  final List<int> body;
  final List<int> bytes;
  final String text;
}

enum BleDecodedMessageKind { protocol, legacyEcho, raw }

class BleChunkFragment {
  const BleChunkFragment({
    required this.stream,
    required this.index,
    required this.count,
    required this.bytes,
  });

  final String stream;
  final int index;
  final int count;
  final List<int> bytes;
}
