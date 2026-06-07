import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_central/src/ble_protocol_codec.dart';

void main() {
  const codec = BleProtocolCodec();
  final fixtures = BlePayloadFixtures.load();

  test('encodes token protected requests', () {
    final bytes = codec.encodeRequest(
      operation: 'echo',
      messageId: 'flutter-7',
      token: 'tok-demo',
      body: {'text': 'hello'},
    );

    final envelope = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    expect(envelope['v'], bleProtocolVersion);
    expect(envelope['op'], 'echo');
    expect(envelope['id'], 'flutter-7');
    expect(envelope['token'], 'tok-demo');
    expect(envelope['body'], {'text': 'hello'});
  });

  test('extracts session token from paired body', () {
    final decoded = codec.decode(
      utf8.encode(
        jsonEncode({
          'v': 1,
          'op': 'paired',
          'id': 'flutter-1',
          'ok': true,
          'body': {'token': 'tok-body'},
        }),
      ),
    );

    expect(decoded.kind, BleDecodedMessageKind.protocol);
    expect(decoded.token, 'tok-body');
  });

  test('summarizes event notifications', () {
    final envelope = {
      'v': 1,
      'op': 'event',
      'id': 'event-3',
      'ok': true,
      'body': {'type': 'paired'},
    };

    expect(
      codec.summaryForProtocol(envelope),
      'op=event id=event-3 token=no ok=true',
    );
  });

  test('summarizes info capability bodies', () {
    final summary = codec.capabilitySummaryForInfoBody({
      'capabilitySchema': 'ble-demo.capabilities.v1',
      'operations': {
        'protected': ['echo', 'telemetry', 'command'],
      },
      'commands': [
        {'name': 'identify'},
        {'name': 'sample'},
        {'name': 'resetCounters'},
      ],
      'events': [
        {'type': 'subscribed'},
        {'type': 'paired'},
      ],
      'eventRuleModes': ['normal', 'quiet', 'burst'],
    });

    expect(
      summary,
      'capabilities schema=ble-demo.capabilities.v1 protected=echo,telemetry,command commands=identify,sample,resetCounters events=2 rules=normal,quiet,burst',
    );
  });

  test('extracts event rule mode from protocol bodies', () {
    expect(codec.eventRuleModeFromBody({'eventRuleMode': 'quiet'}), 'quiet');
    expect(codec.eventRuleModeFromBody({'mode': 'burst'}), 'burst');
    expect(codec.eventRuleModeFromBody({'eventRuleMode': 'loud'}), isNull);
  });

  test('extracts base64 chunk fragments', () {
    final envelope = {
      'v': 1,
      'op': bleProtocolOpChunk,
      'id': 'chunk-stream-0',
      'ok': true,
      'body': {
        'stream': 'stream-1',
        'index': 1,
        'count': 3,
        'encoding': 'base64',
        'data': base64Encode(utf8.encode('world')),
      },
    };

    final chunk = codec.chunkFragmentFromEnvelope(envelope);

    expect(chunk, isNotNull);
    expect(chunk!.stream, 'stream-1');
    expect(chunk.index, 1);
    expect(chunk.count, 3);
    expect(utf8.decode(chunk.bytes), 'world');
  });

  test('rejects invalid chunk fragments', () {
    final envelope = {
      'v': 1,
      'op': bleProtocolOpChunk,
      'id': 'chunk-stream-3',
      'ok': true,
      'body': {
        'stream': 'stream-1',
        'index': 3,
        'count': 3,
        'encoding': 'base64',
        'data': base64Encode(utf8.encode('x')),
      },
    };

    expect(codec.chunkFragmentFromEnvelope(envelope), isNull);
  });

  test('decodes legacy echo payloads', () {
    final decoded = codec.decode([0x00, 0xAA, ...utf8.encode('raw')]);

    expect(decoded.kind, BleDecodedMessageKind.legacyEcho);
    expect(decoded.text, 'raw');
    expect(decoded.body, utf8.encode('raw'));
  });

  test('falls back to raw payloads', () {
    final decoded = codec.decode(utf8.encode('plain text'));

    expect(decoded.kind, BleDecodedMessageKind.raw);
    expect(decoded.text, 'plain text');
  });

  test('decodes recorded payload fixtures', () {
    final legacy = codec.decode(fixtures.bytes('legacy_echo'));
    expect(legacy.kind, BleDecodedMessageKind.legacyEcho);
    expect(legacy.text, 'raw fixture');

    final paired = codec.decode(fixtures.bytes('paired_response'));
    expect(paired.kind, BleDecodedMessageKind.protocol);
    expect(paired.envelope!['op'], 'paired');
    expect(paired.token, 'tok-fixture');

    final echo = codec.decode(fixtures.bytes('echo_response'));
    expect(echo.kind, BleDecodedMessageKind.protocol);
    expect(echo.envelope!['body']['text'], 'hello chunk fixture');
  });

  test('reassembles recorded chunk fixtures', () {
    final firstEnvelope = codec
        .decode(fixtures.bytes('echo_chunk_0'))
        .envelope!;
    final secondEnvelope = codec
        .decode(fixtures.bytes('echo_chunk_1'))
        .envelope!;
    final first = codec.chunkFragmentFromEnvelope(firstEnvelope)!;
    final second = codec.chunkFragmentFromEnvelope(secondEnvelope)!;

    expect(first.stream, second.stream);
    expect(first.index, 0);
    expect(second.index, 1);

    final reassembled = <int>[...first.bytes, ...second.bytes];
    expect(reassembled, fixtures.bytes('echo_response'));
    final decoded = codec.decode(reassembled);
    expect(decoded.envelope!['op'], 'echo');
    expect(decoded.envelope!['body']['text'], 'hello chunk fixture');
  });
}

class BlePayloadFixtures {
  BlePayloadFixtures(this._payloads);

  factory BlePayloadFixtures.load() {
    final file = File('../Shared/BLEProtocolTests/ble_payload_fixtures.json');
    final root = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final payloads = <String, List<int>>{};
    for (final item in root['payloads'] as List<dynamic>) {
      final payload = item as Map<String, dynamic>;
      payloads[payload['name'] as String] = base64Decode(
        payload['base64'] as String,
      );
    }
    return BlePayloadFixtures(payloads);
  }

  final Map<String, List<int>> _payloads;

  List<int> bytes(String name) {
    final value = _payloads[name];
    if (value == null) {
      throw StateError('Missing BLE payload fixture: $name');
    }
    return value;
  }
}
