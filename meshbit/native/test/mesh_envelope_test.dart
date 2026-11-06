import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshbit/main.dart';

void main() {
  test('generated conversation key is 32 bytes encoded as 64 hex chars', () {
    final key = MeshEngine.generateKey();
    expect(key, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(key.length, 64);
  });

  test('mesh envelope preserves relay metadata and ciphertext', () {
    final envelope = MeshEnvelope(id:'id-1',ttl:12,nonce:'n',cipherText:'opaque-ciphertext',mac:'auth-tag');
    final decoded = MeshEnvelope.fromJson(jsonDecode(jsonEncode(envelope.toJson())));
    final forwarded = decoded.forwarded();
    expect(forwarded.id, 'id-1');
    expect(forwarded.ttl, 11);
    expect(forwarded.cipherText, 'opaque-ciphertext');
    expect(forwarded.toJson().containsKey('from'), isFalse);
    expect(forwarded.toJson().containsKey('to'), isFalse);
  });
}
