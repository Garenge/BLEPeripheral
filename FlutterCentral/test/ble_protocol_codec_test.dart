import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_central/src/ble_protocol_codec.dart';

void main() {
  const codec = BleProtocolCodec();

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
}
