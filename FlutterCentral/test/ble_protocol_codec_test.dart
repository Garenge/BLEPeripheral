import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_central/src/ble_chunk_reassembler.dart';
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
    final envelope = {
      'v': 1,
      'op': 'paired',
      'id': 'flutter-1',
      'ok': true,
      'body': {'token': 'tok-body'},
    };
    final decoded = codec.decode(utf8.encode(jsonEncode(envelope)));

    expect(decoded.kind, BleDecodedMessageKind.protocol);
    expect(decoded.token, 'tok-body');
    expect(codec.summaryForProtocol(envelope), contains('token=yes'));
  });

  test('ignores non-string body token values', () {
    final decoded = codec.decode(
      utf8.encode(
        jsonEncode({
          'v': 1,
          'op': 'echo',
          'id': 'bad-body-token',
          'ok': true,
          'body': {'token': 123},
        }),
      ),
    );

    expect(decoded.kind, BleDecodedMessageKind.protocol);
    expect(decoded.token, isNull);
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

  test('rejects non-integer chunk indexes and counts', () {
    Map<String, Object?> chunkBody(Object index, Object count) {
      return {
        'stream': 'stream-1',
        'index': index,
        'count': count,
        'encoding': 'base64',
        'data': base64Encode(utf8.encode('x')),
      };
    }

    for (final body in [
      chunkBody(-1, 2),
      chunkBody(0, -2),
      chunkBody(1.5, 2),
      chunkBody(true, 2),
    ]) {
      expect(
        codec.chunkFragmentFromEnvelope({
          'v': 1,
          'op': bleProtocolOpChunk,
          'id': 'chunk-invalid',
          'ok': true,
          'body': body,
        }),
        isNull,
      );
    }
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

  test('rejects protocol envelopes with invalid version numbers', () {
    for (final version in [true, 1.5]) {
      final decoded = codec.decode(
        utf8.encode(
          jsonEncode({
            'v': version,
            'op': 'ping',
            'id': 'bad-version',
            'body': {},
          }),
        ),
      );

      expect(decoded.kind, BleDecodedMessageKind.raw);
    }
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

  test('chunk reassembler completes and clears buffered bytes', () {
    final reassembler = BleChunkReassembler();

    final first = reassembler.capture(_chunk('stream-1', 0, 2, 'hello '));
    final second = reassembler.capture(_chunk('stream-1', 1, 2, 'world'));

    expect(first.accepted, isTrue);
    expect(first.complete, isNull);
    expect(second.accepted, isTrue);
    expect(utf8.decode(second.complete!), 'hello world');
    expect(reassembler.activeStreams, 0);
    expect(reassembler.bufferedBytes, 0);
  });

  test(
    'chunk reassembler trims oldest stream when stream limit is reached',
    () {
      final reassembler = BleChunkReassembler(maxStreams: 1);

      reassembler.capture(_chunk('stream-old', 0, 2, 'old'));
      final result = reassembler.capture(_chunk('stream-new', 0, 2, 'new'));

      expect(result.accepted, isTrue);
      expect(result.trimmedStream, 'stream-old');
      expect(result.trimReason, 'stream-limit');
      expect(reassembler.activeStreams, 1);
      expect(reassembler.bufferedBytes, 3);
    },
  );

  test('chunk reassembler rejects count and byte limit overflow', () {
    final countLimited = BleChunkReassembler(maxPartsPerStream: 1);
    final byteLimited = BleChunkReassembler(maxBufferedBytes: 3);

    final countResult = countLimited.capture(_chunk('parts', 0, 2, 'x'));
    final byteResult = byteLimited.capture(_chunk('bytes', 0, 2, 'toolong'));

    expect(countResult.accepted, isFalse);
    expect(countResult.rejectReason, 'part-count-limit');
    expect(byteResult.accepted, isFalse);
    expect(byteResult.rejectReason, 'byte-limit');
    expect(byteLimited.activeStreams, 0);
    expect(byteLimited.bufferedBytes, 0);
  });

  test(
    'chunk reassembler replaces duplicate parts without double counting',
    () {
      final reassembler = BleChunkReassembler();

      reassembler.capture(_chunk('stream-1', 0, 2, 'hello'));
      final duplicate = reassembler.capture(_chunk('stream-1', 0, 2, 'hi'));

      expect(duplicate.accepted, isTrue);
      expect(reassembler.bufferedBytes, 2);
      final complete = reassembler.capture(_chunk('stream-1', 1, 2, ' there'));
      expect(utf8.decode(complete.complete!), 'hi there');
      expect(reassembler.bufferedBytes, 0);
    },
  );

  test('chunk reassembler resets a stream when count changes', () {
    final reassembler = BleChunkReassembler();

    reassembler.capture(_chunk('stream-1', 0, 2, 'old'));
    final changed = reassembler.capture(_chunk('stream-1', 0, 3, 'new'));

    expect(changed.accepted, isTrue);
    expect(changed.trimmedStream, 'stream-1');
    expect(changed.trimReason, 'count-changed');
    expect(reassembler.activeStreams, 1);
    expect(reassembler.bufferedBytes, 3);
  });
}

BleChunkFragment _chunk(String stream, int index, int count, String text) {
  return BleChunkFragment(
    stream: stream,
    index: index,
    count: count,
    bytes: utf8.encode(text),
  );
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
