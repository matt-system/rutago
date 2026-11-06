import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshbit/main.dart';

void main() {
  test('generated conversation key is 32 bytes encoded as 64 hex chars', () {
    final key = MeshEngine.generateKey();
    expect(key, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(key.length, 64);
  });

  test('mesh envelope preserves opaque ciphertext and decrements hop limit', () {
    final envelope = MeshEnvelope(id:'00000000-0000-4000-8000-000000000001',ttl:12,nonce:base64Encode(List<int>.filled(12,0)),cipherText:base64Encode(utf8.encode('opaque-ciphertext')),mac:base64Encode(List<int>.filled(16,1)));
    final decoded = MeshEnvelope.fromJson(jsonDecode(jsonEncode(envelope.toJson())));
    final forwarded = decoded.forwarded();
    expect(forwarded.id, '00000000-0000-4000-8000-000000000001');
    expect(forwarded.ttl, 11);
    expect(base64Decode(forwarded.cipherText), utf8.encode('opaque-ciphertext'));
    expect(forwarded.toJson().containsKey('from'), isFalse);
    expect(forwarded.toJson().containsKey('to'), isFalse);
  });

  test('mesh envelope rejects invalid hop limits', () {
    expect(() => MeshEnvelope.fromJson({'v':1,'id':'00000000-0000-4000-8000-000000000001','ttl':13,'nonce':base64Encode(List<int>.filled(12,0)),'cipherText':'','mac':base64Encode(List<int>.filled(16,1))}), throwsFormatException);
  });
}
