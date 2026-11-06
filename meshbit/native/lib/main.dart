import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nearby/nearby.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() => runApp(const MeshbitApp());

class MeshbitApp extends StatelessWidget {
  const MeshbitApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'MESHBIT',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff78977d), brightness: Brightness.dark), scaffoldBackgroundColor: const Color(0xff101411), useMaterial3: true),
    home: const MeshHome(),
  );
}

class MeshEnvelope {
  MeshEnvelope({required this.id, required this.ttl, required this.nonce, required this.cipherText, required this.mac});
  final String id, nonce, cipherText, mac;
  final int ttl;

  Map<String, dynamic> toJson() => {
    'v': 1, 'id': id, 'ttl': ttl, 'nonce': nonce,
    'cipherText': cipherText, 'mac': mac,
  };

  factory MeshEnvelope.fromJson(Map<String, dynamic> json) {
    if (json['v'] != 1) throw const FormatException('Unsupported mesh packet version');
    final id = json['id'];
    final ttl = json['ttl'];
    final nonce = json['nonce'];
    final cipherText = json['cipherText'];
    final mac = json['mac'];
    if (id is! String || !RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id)) {
      throw const FormatException('Invalid packet ID');
    }
    if (ttl is! int || ttl < 0 || ttl > 7) {
      throw const FormatException('Invalid packet hop limit');
    }
    if (nonce is! String || base64Decode(nonce).length != 12) {
      throw const FormatException('Invalid packet nonce');
    }
    if (mac is! String || base64Decode(mac).length != 16) {
      throw const FormatException('Invalid packet authentication tag');
    }
    if (cipherText is! String || cipherText.length > 6000 || base64Decode(cipherText).length > 4096 + 128) {
      throw const FormatException('Packet payload too large');
    }
    return MeshEnvelope(id:id, ttl:ttl, nonce:nonce, cipherText:cipherText, mac:mac);
  }

  MeshEnvelope forwarded() => MeshEnvelope(
    id:id, ttl:ttl - 1, nonce:nonce, cipherText:cipherText, mac:mac,
  );
}

class MeshChatMessage {
  const MeshChatMessage({required this.id,required this.senderId,required this.senderAlias,required this.text,required this.createdAt,required this.isMine});
  final String id, senderId, senderAlias, text;
  final DateTime createdAt;
  final bool isMine;
}

class MeshEngine {
  static const publicChannelId = 'mesh:general';
  MeshEngine(this.onStatus, this.onMessage, this.onPeers);
  final void Function(String) onStatus;
  final void Function(MeshEnvelope) onMessage;
  final void Function(List<Peer>) onPeers;
  late final NearbyService _nearby;
  final _uuid = const Uuid();
  final _aes = AesGcm.with256bits();
  final _secureStorage = const FlutterSecureStorage();
  final _peers = <String, Peer>{};
  final _seen = <String>{};
  final _trustedPeers = <String>{};
  String? _outgoingAttemptPeer;
  String? pendingOutgoingPeer;
  String? pendingOutgoingPin;
  StreamSubscription? _discoverySub, _requestsSub, _payloadSub, _peerStateSub;
  Database? _db;
  String nodeId = '';
  bool running = false;
  int get connectedPeerCount => _initialized ? _nearby.connectedPeers.length : 0;
  bool _initialized = false;
  Future<void>? _initFuture;

  Future<void> init() async {
    if (_initialized) return;
    final pending = _initFuture;
    if (pending != null) { await pending; return; }
    final future = _initialize();
    _initFuture = future;
    try { await future; } catch (_) { _initFuture = null; rethrow; }
  }

  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    nodeId = prefs.getString('mesh.node') ?? _uuid.v4();
    await prefs.setString('mesh.node', nodeId);
    final dbPath = p.join(await getDatabasesPath(), 'meshbit_mesh.db');
    _db = await openDatabase(dbPath, version:3, onCreate:(db,_) async {
      await db.execute('CREATE TABLE packets(id TEXT PRIMARY KEY, json TEXT NOT NULL, delivered INTEGER NOT NULL DEFAULT 0, originated INTEGER NOT NULL DEFAULT 0, created INTEGER NOT NULL)');
      await db.execute('CREATE TABLE forwards(packet_id TEXT NOT NULL, peer_id TEXT NOT NULL, ttl INTEGER NOT NULL, sent_at INTEGER NOT NULL, PRIMARY KEY(packet_id,peer_id))');
    }, onUpgrade:(db,oldVersion,newVersion) async {
      if(oldVersion < 2) await db.execute('ALTER TABLE packets ADD COLUMN originated INTEGER NOT NULL DEFAULT 0');
      if(oldVersion < 3) await db.execute('CREATE TABLE forwards(packet_id TEXT NOT NULL, peer_id TEXT NOT NULL, ttl INTEGER NOT NULL, sent_at INTEGER NOT NULL, PRIMARY KEY(packet_id,peer_id))');
    });
    final retentionCutoff = DateTime.now().subtract(const Duration(days:7)).millisecondsSinceEpoch;
    await _db!.delete('packets', where:'created < ?', whereArgs:[retentionCutoff]);
    await _db!.delete('forwards', where:'sent_at < ?', whereArgs:[retentionCutoff]);
    final rows = await _db!.query('packets');
    for (final row in rows) { try { _rememberSeen(row['id'] as String); } catch (_) {} }
    _nearby = NearbyService(localDisplayName:'MESHBIT', localPeerId:_uuid.v4());
    _initialized = true;
  }

  Future<void> start() async {
    if (running) return;
    await init();
    if (Platform.isIOS) {
      final bluetoothStatus = await Permission.bluetooth.request();
      if (bluetoothStatus.isPermanentlyDenied || bluetoothStatus.isDenied) {
        throw Exception('Activa Bluetooth para MESHBIT en Ajustes del iPhone.');
      }
    }
    if (Platform.isAndroid) {
      final android = await DeviceInfoPlugin().androidInfo;
      final requiredPermissions = android.version.sdkInt >= 31
          ? [Permission.bluetoothScan, Permission.bluetoothAdvertise, Permission.bluetoothConnect]
          : [Permission.locationWhenInUse];
      final statuses = await requiredPermissions.request();
      if (statuses.values.any((status) => status.isPermanentlyDenied || status.isDenied)) {
        throw Exception('Faltan permisos de Bluetooth o ubicación cercana. Actívalos en Ajustes para iniciar MESH.');
      }
    }
    _discoverySub = _nearby.discoveredPeersStream.listen((list) {
      for (final peer in list) { _peers[peer.id] = peer; }
      onPeers(_peers.values.toList());
    });
    _requestsSub = _nearby.connectionRequestsStream.listen((request) async {
      onStatus('Solicitud de conexión: ${request.peer.displayName} · código ${request.authenticationPin}. Compara el código con el otro teléfono antes de aceptar.');
      _pendingRequest = request.peer.id;
      _pendingPin = request.authenticationPin;
    });
    _peerStateSub = _nearby.peerStateStream.listen((event) {
      if (event.sasPin != null && _outgoingAttemptPeer != null) {
        pendingOutgoingPeer = event.peer.id;
        pendingOutgoingPin = event.sasPin;
        onStatus('Compara el código con el otro teléfono. La retransmisión queda bloqueada hasta confirmarlo.');
      }
      if (event.state == PeerConnectionState.connected) {
        _peers[event.peer.id] = event.peer;
        onPeers(_peers.values.toList());
        if (_trustedPeers.contains(event.peer.id)) {
          onStatus('Vecino verificado: ${event.peer.displayName}.');
          _flush();
        } else {
          onStatus('Conexión cifrada establecida. Falta confirmar el código de seguridad.');
        }
      }
      if (event.state == PeerConnectionState.disconnected) {
        _trustedPeers.remove(event.peer.id);
        _peers.remove(event.peer.id);
        if (pendingOutgoingPeer == event.peer.id) { pendingOutgoingPeer=null; pendingOutgoingPin=null; _outgoingAttemptPeer=null; }
        onPeers(_peers.values.toList());
      }
    });
    _payloadSub = _nearby.payloadReceivedStream.listen((payload) async {
      if (payload.type != PayloadType.bytes || payload.bytes == null) return;
      final sourcePeer = payload.peerId;
      if (sourcePeer == null || !_trustedPeers.contains(sourcePeer)) {
        onStatus('Paquete descartado: el vecino todavía no está verificado.');
        return;
      }
      await _receive(payload.bytes!, sourcePeer);
    });
    await _nearby.startAdvertising(options: const AdvertisingOptions(serviceId:'meshbit',strategy:DiscoveryStrategy.bleOnly,securityMode:SecurityMode.pinVerification));
    await _nearby.startDiscovery(options: const DiscoveryOptions(serviceId:'meshbit',strategy:DiscoveryStrategy.bleOnly));
    await WakelockPlus.enable();
    running = true;
    onStatus('Bluetooth LE activo: busca teléfonos cercanos sin Wi-Fi ni datos móviles.');
  }

  String? _pendingRequest, _pendingPin;
  String? get pendingPeer => _pendingRequest;
  String? get pendingPin => _pendingPin;
  Future<void> acceptPending({required bool pinConfirmed}) async {
    if (!pinConfirmed) throw Exception('Compara el código de seguridad antes de aceptar.');
    final id = _pendingRequest;
    if (id == null) return;
    await _nearby.acceptConnection(id);
    _trustedPeers.add(id);
    _pendingRequest = null; _pendingPin = null;
    onStatus('Conexión local aceptada. Canal protegido activo.');
    await _flush();
  }

  Future<void> connect(Peer peer) async {
    _outgoingAttemptPeer = peer.id;
    onStatus('Solicitando conexión segura a ${peer.displayName}…');
    try {
      final ok = await _nearby.requestConnection(peer);
      if (ok) {
        _peers[peer.id] = peer;
        onPeers(_peers.values.toList());
        if (pendingOutgoingPin == null) {
          onStatus('Conexión establecida. Esperando verificación del código de seguridad.');
        }
      } else {
        pendingOutgoingPeer = null;
        pendingOutgoingPin = null;
        _outgoingAttemptPeer = null;
        onStatus('La conexión no se completó.');
      }
    } catch (error) {
      _outgoingAttemptPeer = null;
      rethrow;
    }
  }

  Future<void> confirmOutgoingPin({required bool pinConfirmed}) async {
    if (!pinConfirmed) throw Exception('Compara el código en ambos teléfonos antes de confirmar.');
    final peerId = pendingOutgoingPeer;
    if (peerId == null || pendingOutgoingPin == null) return;
    _trustedPeers.add(peerId);
    pendingOutgoingPeer = null;
    pendingOutgoingPin = null;
    _outgoingAttemptPeer = null;
    onStatus('Vecino verificado. Ya puede retransmitir paquetes MESH.');
    await _flush();
  }

  Future<void> sendText(String destination, String text, String keyHex, {String senderAlias = 'mesh-user'}) async {
    final key = _parseKey(keyHex);
    if (key == null) throw Exception('La clave debe tener exactamente 64 caracteres hexadecimales.');
    if (destination.trim().isEmpty) throw Exception('Falta el ID del destinatario.');
    if (text.trim().isEmpty) throw Exception('Escribe un mensaje antes de enviarlo.');
    if (utf8.encode(text).length > 4096) throw Exception('El mensaje supera el límite de 4 KB.');
    final packetId = _uuid.v4();
    final inner = jsonEncode({'v':1,'kind':'text','id':packetId,'from':nodeId,'alias':senderAlias.trim().isEmpty?'mesh-user':senderAlias.trim(),'to':destination.trim(),'text':text,'createdAt':DateTime.now().millisecondsSinceEpoch});
    final box = await _aes.encrypt(utf8.encode(inner), secretKey:SecretKey(key));
    final envelope = MeshEnvelope(id:packetId,ttl:7,nonce:base64Encode(box.nonce),cipherText:base64Encode(box.cipherText),mac:base64Encode(box.mac.bytes));
    _rememberSeen(envelope.id);
    await _store(envelope, originated:true);
    await _broadcast(envelope);
    onStatus('Mensaje cifrado guardado y enviado a la red. Se reenviará si aparece otra ruta.');
  }

  Future<void> _receive(Uint8List bytes, String sourcePeer) async {
    try {
      if (bytes.length > 6200) return;
      final map = jsonDecode(utf8.decode(bytes)) as Map<String,dynamic>;
      final env = MeshEnvelope.fromJson(map);
      final existing = await _db!.query('packets', where:'id=?', whereArgs:[env.id], limit:1);
      if (_seen.contains(env.id)) {
        if (existing.isNotEmpty && env.ttl > 0) {
          final saved = MeshEnvelope.fromJson(jsonDecode(existing.first['json'] as String));
          final improved = env.forwarded();
          if (improved.ttl > saved.ttl) {
            await _db!.update('packets', {'json':jsonEncode(improved.toJson())}, where:'id=?', whereArgs:[env.id]);
            await _broadcast(improved, excludePeer:sourcePeer);
          }
        }
        return;
      }
      _rememberSeen(env.id);
      final forwarded = env.ttl > 0 ? env.forwarded() : env;
      await _store(forwarded);
      onMessage(forwarded);
      if (env.ttl > 0) await _broadcast(forwarded, excludePeer:sourcePeer);
    } catch (_) { onStatus('Se descartó un paquete local inválido.'); }
  }

  Future<MeshChatMessage?> decryptPacket(MeshEnvelope env, String keyHex, String conversationId) async {
    final key = _parseKey(keyHex);
    if (key == null) throw Exception('La clave debe tener exactamente 64 caracteres hexadecimales.');
    final clear = await _aes.decrypt(
      SecretBox(base64Decode(env.cipherText), nonce:base64Decode(env.nonce), mac:Mac(base64Decode(env.mac))),
      secretKey:SecretKey(key),
    );
    final decoded = jsonDecode(utf8.decode(clear)) as Map<String,dynamic>;
    if (decoded['v'] != 1 || decoded['kind'] != 'text' || decoded['id'] != env.id) {
      throw const FormatException('Mensaje MESH inválido.');
    }
    final from = decoded['from']?.toString() ?? '';
    final to = decoded['to']?.toString() ?? '';
    final isMine = from == nodeId;
    final isPublic = conversationId == publicChannelId && to == publicChannelId;
    final isDirect = conversationId != publicChannelId &&
      ((isMine && to == conversationId) || (!isMine && from == conversationId && to == nodeId));
    if (!isPublic && !isDirect) return null;
    if (!isMine && (to == nodeId || isPublic)) {
      await _db!.update('packets', {'delivered':1}, where:'id=?', whereArgs:[env.id]);
    }
    final stamp = decoded['createdAt'];
    return MeshChatMessage(
      id:env.id,
      senderId:from,
      senderAlias:(decoded['alias']?.toString().trim().isNotEmpty ?? false) ? decoded['alias'].toString() : from,
      text:decoded['text']?.toString() ?? '',
      createdAt:DateTime.fromMillisecondsSinceEpoch(stamp is int ? stamp : DateTime.now().millisecondsSinceEpoch),
      isMine:isMine,
    );
  }

  Future<List<MeshChatMessage>> loadConversation(String conversationId, String keyHex) async {
    await init();
    final rows = await _db!.query('packets', orderBy:'created ASC', limit:1000);
    final messages = <MeshChatMessage>[];
    for (final row in rows) {
      try {
        final env = MeshEnvelope.fromJson(jsonDecode(row['json'] as String) as Map<String,dynamic>);
        final message = await decryptPacket(env, keyHex, conversationId);
        if (message != null) messages.add(message);
      } catch (_) {}
    }
    messages.sort((a,b)=>a.createdAt.compareTo(b.createdAt));
    return messages;
  }

  Future<String> getOrCreatePublicChannelKey() async {
    const storageKey = 'meshbit.channel.general.key.v1';
    final existing = await _secureStorage.read(key:storageKey);
    if (existing != null && _parseKey(existing) != null) return existing;
    final generated = generateKey();
    await _secureStorage.write(key:storageKey, value:generated);
    return generated;
  }

  Future<void> savePublicChannelKey(String value) async {
    if (_parseKey(value) == null) throw Exception('La clave debe tener 64 caracteres hexadecimales.');
    await _secureStorage.write(key:'meshbit.channel.general.key.v1', value:value.trim().toLowerCase());
  }

  Future<void> saveContactKey(String peerId, String value) async {
    if (_parseKey(value) == null) throw Exception('La clave privada debe tener 64 caracteres hexadecimales.');
    await _secureStorage.write(key:'meshbit.contact.$peerId.key.v1', value:value.trim().toLowerCase());
  }

  Future<String?> loadContactKey(String peerId) => _secureStorage.read(key:'meshbit.contact.$peerId.key.v1');

  Future<void> deleteContactKey(String peerId) => _secureStorage.delete(key:'meshbit.contact.$peerId.key.v1');

  Future<void> saveAlias(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mesh.alias', value.trim().isEmpty ? 'mesh-user' : value.trim().substring(0, value.trim().length > 24 ? 24 : value.trim().length));
  }

  Future<String> loadAlias() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('mesh.alias') ?? 'mesh-user';
  }

  Future<List<Map<String,String>>> loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('mesh.contacts') ?? const <String>[];
    final contacts = <Map<String,String>>[];
    for (final value in raw) {
      try {
        final item = jsonDecode(value) as Map<String,dynamic>;
        final id = item['id']?.toString() ?? '';
        final alias = item['alias']?.toString() ?? '';
        if (id.isNotEmpty && alias.isNotEmpty) contacts.add({'id':id,'alias':alias});
      } catch (_) {}
    }
    return contacts;
  }

  Future<void> saveContact(String peerId, String alias) async {
    final id = peerId.trim();
    final name = alias.trim();
    if (id.isEmpty || name.isEmpty || id == nodeId) throw Exception('Revisa el alias y el ID del contacto.');
    final contacts = await loadContacts();
    contacts.removeWhere((contact)=>contact['id']==id);
    contacts.add({'id':id,'alias':name.substring(0,name.length > 24 ? 24 : name.length)});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('mesh.contacts', contacts.map(jsonEncode).toList());
  }

  Future<void> removeContact(String peerId) async {
    final contacts = await loadContacts();
    contacts.removeWhere((contact)=>contact['id']==peerId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('mesh.contacts', contacts.map(jsonEncode).toList());
    await deleteContactKey(peerId);
  }

  void _rememberSeen(String id) {
    if (!_seen.add(id)) return;
    if (_seen.length > 1000) _seen.remove(_seen.first);
  }

  Future<void> _store(MeshEnvelope env, {bool originated = false}) async {
    await _db!.insert('packets', {'id':env.id,'json':jsonEncode(env.toJson()),'originated':originated ? 1 : 0,'created':DateTime.now().millisecondsSinceEpoch}, conflictAlgorithm:ConflictAlgorithm.ignore);
    final count = Sqflite.firstIntValue(await _db!.rawQuery('SELECT COUNT(*) FROM packets')) ?? 0;
    if (count > 1000) {
      final oldest = await _db!.query('packets', columns:['id'], orderBy:'created ASC', limit:1);
      if (oldest.isNotEmpty) {
        final oldestId = oldest.first['id'] as String;
        await _db!.delete('packets', where:'id=?', whereArgs:[oldestId]);
        await _db!.delete('forwards', where:'packet_id=?', whereArgs:[oldestId]);
      }
    }
  }

  Future<List<MeshEnvelope>> loadInbox() async {
    await init();
    final rows = await _db!.query('packets', where:'originated=0', orderBy:'created DESC', limit:100);
    return rows.map((row) => MeshEnvelope.fromJson(jsonDecode(row['json'] as String) as Map<String,dynamic>)).toList();
  }
  Future<void> _broadcast(MeshEnvelope env, {String? excludePeer}) async {
    final neighbors = _nearby.connectedPeers
        .where((peer) => peer.id != excludePeer && _trustedPeers.contains(peer.id))
        .toList();
    if (neighbors.isEmpty) {
      onStatus('Sin vecinos verificados: paquete guardado localmente para retransmitir más tarde.');
      return;
    }
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(env.toJson())));
    for (final peer in neighbors) {
      try {
        final prior = await _db!.query('forwards', where:'packet_id=? AND peer_id=?', whereArgs:[env.id,peer.id], limit:1);
        if (prior.isNotEmpty && (prior.first['ttl'] as int) >= env.ttl) continue;
        await _nearby.sendBytes(peer.id, bytes);
        await _db!.insert('forwards', {
          'packet_id':env.id,
          'peer_id':peer.id,
          'ttl':env.ttl,
          'sent_at':DateTime.now().millisecondsSinceEpoch,
        }, conflictAlgorithm:ConflictAlgorithm.replace);
      } catch (_) {
        // Do not mark failed transmissions as forwarded; the next reconnect retries them.
      }
    }
  }

  Future<void> _flush() async {
    final rows = await _db!.query('packets', orderBy:'created ASC', limit:500);
    for (final row in rows) {
      try {
        final env = MeshEnvelope.fromJson(jsonDecode(row['json'] as String));
        if (env.ttl > 0) await _broadcast(env);
      } catch (_) {}
    }
  }
  static List<int>? _parseKey(String input) {
    final s = input.trim();
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(s)) return null;
    return [for (var i=0;i<s.length;i+=2) int.parse(s.substring(i,i+2),radix:16)];
  }
  static String generateKey() {
    final random = Random.secure();
    return List.generate(32, (_) => random.nextInt(256).toRadixString(16).padLeft(2,'0')).join();
  }
  Future<void> stop() async {
    await _nearby.stopDiscovery(); await _nearby.stopAdvertising(); await _nearby.disconnectAll();
    await WakelockPlus.disable();
    running = false; onStatus('MESH detenido.');
  }
  Future<void> dispose() async {
    await _discoverySub?.cancel(); await _requestsSub?.cancel(); await _payloadSub?.cancel(); await _peerStateSub?.cancel();
    if (_initialized) await _nearby.dispose();
    await WakelockPlus.disable();
    await _db?.close();
  }
}

class MeshbitChatPage extends StatefulWidget {
  const MeshbitChatPage({super.key});
  @override
  State<MeshbitChatPage> createState() => _MeshbitChatPageState();
}

class _MeshbitChatPageState extends State<MeshbitChatPage> {
  late final WebViewController controller;
  bool loading = true;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) { if (mounted) setState(() { loading = true; failed = false; }); },
        onPageFinished: (_) { if (mounted) setState(() { loading = false; failed = false; }); },
        onWebResourceError: (_) { if (mounted) setState(() { loading = false; failed = true; }); },
      ))
      ..loadRequest(Uri.parse('https://meshbit.matthieupierremarie.workers.dev/app/'));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('CHAT MESHBIT')),
    body: Stack(children:[
      WebViewWidget(controller:controller),
      if(loading) const LinearProgressIndicator(),
      if(failed) Positioned.fill(child:ColoredBox(color:const Color(0xff101411),child:Center(child:Padding(padding:const EdgeInsets.all(28),child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.wifi_off,size:42,color:Color(0xffa8c5ac)),const SizedBox(height:14),const Text('El chat necesita internet',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),const SizedBox(height:8),const Text('La red MESH por Bluetooth sigue disponible. Vuelve a MESH y continúa conversando sin Wi-Fi ni datos móviles.',textAlign:TextAlign.center,style:TextStyle(color:Colors.white70)),const SizedBox(height:18),FilledButton(onPressed:()=>Navigator.of(context).pop(),child:const Text('VOLVER A MESH'))]))))),
    ]),
  );
}

class MeshHome extends StatefulWidget {
  const MeshHome({super.key});
  @override
  State<MeshHome> createState() => _MeshHomeState();
}

class _MeshHomeState extends State<MeshHome> {
  late final MeshEngine engine;
  final composer = TextEditingController();
  String status = 'Preparando Bluetooth…';
  String alias = 'mesh-user';
  String publicKey = '';
  int selectedTab = 0;
  String? selectedContactId;
  String? selectedContactAlias;
  List<Map<String,String>> contacts = [];
  List<Peer> peers = [];
  List<MeshChatMessage> messages = [];
  bool busy = true;
  bool bubbleMode = true;
  bool pinConfirmed = false;
  bool outgoingPinConfirmed = false;
  bool _refreshing = false;
  bool _refreshPending = false;

  bool get _isPublicChat => selectedTab == 0;
  String get _conversationId => _isPublicChat ? MeshEngine.publicChannelId : (selectedContactId ?? '');
  String get _conversationTitle => _isPublicChat ? '#general' : (selectedContactAlias ?? 'Conversación privada');

  @override
  void initState() {
    super.initState();
    engine = MeshEngine(
      (value) {
        if (!mounted) return;
        setState(() {
          status = value;
          if (value.startsWith('Solicitud de conexión:')) pinConfirmed = false;
        });
      },
      (_) {
        _reloadConversation();
      },
      (value) {
        if (mounted) setState(() => peers = value);
      },
    );
    _boot();
  }

  Future<void> _boot() async {
    try {
      await engine.init();
      final loadedKey = await engine.getOrCreatePublicChannelKey();
      final loadedAlias = await engine.loadAlias();
      final loadedContacts = await engine.loadContacts();
      if (!mounted) return;
      setState(() {
        publicKey = loadedKey;
        alias = loadedAlias;
        contacts = loadedContacts;
      });
      await engine.start();
      await _reloadConversation();
    } catch (error) {
      if (mounted) notice('MESH no pudo iniciarse: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _reloadConversation() async {
    if (!mounted || (publicKey.isEmpty && _isPublicChat)) return;
    if (_refreshing) { _refreshPending = true; return; }
    final conversationId = _conversationId;
    if (conversationId.isEmpty) {
      if (mounted) setState(() => messages = []);
      return;
    }
    _refreshing = true;
    try {
      final keyHex = _isPublicChat ? publicKey : await engine.loadContactKey(conversationId);
      if (keyHex == null || keyHex.isEmpty) {
        if (mounted) setState(() => messages = []);
        return;
      }
      final loaded = await engine.loadConversation(conversationId, keyHex);
      if (mounted && conversationId == _conversationId) setState(() => messages = loaded);
    } finally {
      _refreshing = false;
      if (_refreshPending && mounted) {
        _refreshPending = false;
        _reloadConversation();
      }
    }
  }

  @override
  void dispose() {
    composer.dispose();
    engine.dispose();
    super.dispose();
  }

  void notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _sendMessage() async {
    final text = composer.text.trim();
    if (text.isEmpty || busy) return;
    final conversationId = _conversationId;
    final keyHex = _isPublicChat ? publicKey : await engine.loadContactKey(conversationId);
    if (keyHex == null || keyHex.isEmpty) {
      notice('Falta la clave de esta conversación. Revísala en el contacto.');
      return;
    }
    setState(() => busy = true);
    try {
      await engine.sendText(conversationId, text, keyHex, senderAlias: alias);
      composer.clear();
      await _reloadConversation();
    } catch (error) {
      notice('No se pudo preparar el mensaje: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _showChannelKey() async {
    final controller = TextEditingController(text: 'MESH1:$publicKey');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xff1b241f),
        title: const Text('Acceso al canal #general'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Esta clave permite leer y publicar en el canal local. Compártela solo con las personas que quieras incluir y por un canal de confianza.'),
          const SizedBox(height: 14),
          TextField(controller: controller, maxLines: 3, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Código de acceso')),
        ]),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: 'MESH1:$publicKey'));
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              notice('Código copiado. Compártelo fuera de MESHBIT.');
            },
            child: const Text('COPIAR'),
          ),
          FilledButton(
            onPressed: () async {
              var value = controller.text.trim();
              if (value.startsWith('MESH1:')) value = value.substring(6);
              try {
                await engine.savePublicChannelKey(value);
                if (mounted) setState(() => publicKey = value);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                await _reloadConversation();
                notice('Clave del canal actualizada en el almacén seguro.');
              } catch (error) {
                notice(error.toString());
              }
            },
            child: const Text('GUARDAR CLAVE'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _addContact() async {
    final aliasController = TextEditingController();
    final idController = TextEditingController();
    final keyController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xff1b241f),
          title: const Text('Añadir conversación privada'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: aliasController, decoration: const InputDecoration(labelText: 'Alias', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(controller: idController, decoration: const InputDecoration(labelText: 'ID MESH del contacto', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(controller: keyController, obscureText: true, decoration: const InputDecoration(labelText: 'Clave compartida · 64 caracteres hex', border: OutlineInputBorder())),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    setDialogState(() => keyController.text = MeshEngine.generateKey());
                    await Clipboard.setData(ClipboardData(text: keyController.text));
                    if (dialogContext.mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('Clave generada y copiada. Compártela por otro canal seguro.')));
                  },
                  icon: const Icon(Icons.key),
                  label: const Text('GENERAR Y COPIAR CLAVE'),
                ),
              ),
              const Text('La misma clave debe guardarse en ambos teléfonos. El secreto se guarda en Keychain o en el almacén protegido de Android.', style: TextStyle(color: Colors.white60, fontSize: 12)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('CANCELAR')),
            FilledButton(
              onPressed: () async {
                try {
                  await engine.saveContact(idController.text, aliasController.text);
                  await engine.saveContactKey(idController.text.trim(), keyController.text);
                  final updated = await engine.loadContacts();
                  if (mounted) setState(() => contacts = updated);
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  notice('Contacto guardado. La clave quedó protegida por el sistema del teléfono.');
                } catch (error) {
                  notice(error.toString());
                }
              },
              child: const Text('GUARDAR'),
            ),
          ],
        ),
      ),
    );
    aliasController.dispose();
    idController.dispose();
    keyController.dispose();
  }

  Future<void> _removeContact(Map<String,String> contact) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xff1b241f),
        title: const Text('Eliminar contacto'),
        content: Text('¿Eliminar la conversación con ${contact['alias']} y borrar su clave guardada de este teléfono?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('CANCELAR')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('ELIMINAR')),
        ],
      ),
    );
    if (confirm != true) return;
    await engine.removeContact(contact['id']!);
    final updated = await engine.loadContacts();
    if (mounted) setState(() => contacts = updated);
  }

  Future<void> _showProfile() async {
    final controller = TextEditingController(text: alias);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xff1b241f),
        title: const Text('Tu identidad local'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: controller, maxLength: 24, decoration: const InputDecoration(labelText: 'Alias visible en los chats', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          const Text('ID privado del dispositivo', style: TextStyle(color: Color(0xffa8c5ac), fontSize: 12)),
          SelectableText(engine.nodeId, style: const TextStyle(fontSize: 12)),
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: engine.nodeId));
              notice('ID copiado.');
            },
            icon: const Icon(Icons.copy),
            label: const Text('COPIAR ID'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('CERRAR')),
          FilledButton(
            onPressed: () async {
              final cleaned = controller.text.trim();
              await engine.saveAlias(cleaned);
              if (mounted) setState(() => alias = cleaned.isEmpty ? 'mesh-user' : cleaned.substring(0, cleaned.length > 24 ? 24 : cleaned.length));
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('GUARDAR ALIAS'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  void _selectTab(int tab) {
    setState(() {
      if (tab == selectedTab && tab == 1) {
        selectedContactId = null;
        selectedContactAlias = null;
      } else {
        selectedTab = tab;
        if (tab != 1) selectedContactId = null;
        selectedContactAlias = null;
      }
    });
    _reloadConversation();
  }

  void _openContact(Map<String,String> contact) {
    setState(() {
      selectedTab = 1;
      selectedContactId = contact['id'];
      selectedContactAlias = contact['alias'];
    });
    _reloadConversation();
  }

  Widget _chatHeader() => Container(
    padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xff28342c)))),
    child: Row(children: [
      Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(color: const Color(0xff24372a), borderRadius: BorderRadius.circular(12)),
        child: Icon(_isPublicChat ? Icons.hub_outlined : Icons.lock_outline, color: const Color(0xffa8c5ac), size: 19),
      ),
      const SizedBox(width: 11),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_conversationTitle, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        Text(_isPublicChat ? 'Canal local cifrado · Bluetooth LE' : 'Privado · clave compartida', style: const TextStyle(fontSize: 11, color: Colors.white54)),
      ])),
      if (_isPublicChat) IconButton(tooltip: 'Clave del canal', onPressed: _showChannelKey, icon: const Icon(Icons.vpn_key_outlined, color: Color(0xffa8c5ac))),
      IconButton(tooltip: bubbleMode ? 'Cambiar a vista terminal' : 'Cambiar a burbujas', onPressed: () => setState(() => bubbleMode = !bubbleMode), icon: Icon(bubbleMode ? Icons.subject : Icons.chat_bubble_outline, color: const Color(0xffa8c5ac))),
    ]),
  );

  String _timeLabel(DateTime time) {
    final local = time.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Widget _messageTile(MeshChatMessage message) {
    final mine = message.isMine;
    if (!bubbleMode) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(mine ? 'tú' : message.senderAlias, style: TextStyle(color: mine ? const Color(0xffa8c5ac) : const Color(0xffd3bb8b), fontWeight: FontWeight.w700, fontSize: 12)),
            const SizedBox(width: 8),
            Text(_timeLabel(message.createdAt), style: const TextStyle(color: Colors.white30, fontSize: 10)),
          ]),
          const SizedBox(height: 3),
          Text(message.text, style: const TextStyle(fontSize: 14, height: 1.4, color: Color(0xffe6ece7))),
        ]),
      );
    }
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: mine ? const Color(0xff294332) : const Color(0xff202923),
            border: Border.all(color: mine ? const Color(0xff466b50) : const Color(0xff303b33)),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(17),
              topRight: const Radius.circular(17),
              bottomLeft: Radius.circular(mine ? 17 : 5),
              bottomRight: Radius.circular(mine ? 5 : 17),
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!mine) Text(message.senderAlias, style: const TextStyle(color: Color(0xffb7cbb9), fontWeight: FontWeight.w700, fontSize: 11)),
            Text(message.text, style: const TextStyle(fontSize: 14, height: 1.4, color: Color(0xffedf3ee))),
            const SizedBox(height: 3),
            Align(alignment: Alignment.centerRight, child: Text(_timeLabel(message.createdAt), style: const TextStyle(color: Colors.white38, fontSize: 10))),
          ]),
        ),
      ),
    );
  }

  Widget _buildChat() {
    final hasKey = _isPublicChat ? publicKey.isNotEmpty : selectedContactId != null;
    return Column(children: [
      _chatHeader(),
      Expanded(
        child: messages.isEmpty
          ? Center(child: Padding(
              padding: const EdgeInsets.all(30),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(_isPublicChat ? Icons.waves : Icons.lock_outline, size: 42, color: const Color(0xff607965)),
                const SizedBox(height: 14),
                Text(_isPublicChat ? 'El canal está en silencio' : 'Conversación privada lista', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 7),
                Text(
                  _isPublicChat
                    ? 'Comparte la clave de #general con tus contactos. Los teléfonos cercanos pueden intercambiar mensajes sin Internet.'
                    : 'Envía un mensaje. Si el contacto todavía no está cerca, el paquete permanecerá guardado en la red hasta que aparezca una ruta.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54, height: 1.5),
                ),
              ]),
            ))
          : ListView.builder(
              itemCount: messages.length,
              padding: const EdgeInsets.only(top: 12, bottom: 16),
              itemBuilder: (context, index) => _messageTile(messages[index]),
            ),
      ),
      SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
          decoration: const BoxDecoration(color: Color(0xff151c17), border: Border(top: BorderSide(color: Color(0xff28342c)))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: TextField(
              controller: composer,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
              decoration: InputDecoration(
                hintText: hasKey ? 'Mensaje…' : 'Clave no disponible',
                filled: true,
                fillColor: const Color(0xff202923),
                contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
              ),
            )),
            const SizedBox(width: 8),
            SizedBox(
              width: 46,
              height: 46,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xff78977d), foregroundColor: const Color(0xff0d140f), padding: EdgeInsets.zero, shape: const CircleBorder()),
                onPressed: busy || !hasKey ? null : _sendMessage,
                child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.arrow_upward),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _buildContacts() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
        child: Row(children: [
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('CONVERSACIONES', style: TextStyle(color: Color(0xffa8c5ac), fontSize: 11, letterSpacing: 2)),
            SizedBox(height: 4),
            Text('Tus contactos privados', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ])),
          FilledButton.icon(onPressed: _addContact, icon: const Icon(Icons.add, size: 18), label: const Text('AÑADIR')),
        ]),
      ),
      Expanded(
        child: contacts.isEmpty
          ? const Center(child: Padding(
              padding: EdgeInsets.all(28),
              child: Text('Todavía no tienes contactos. Añade el ID MESH de una persona y guarda una clave privada compartida.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, height: 1.5)),
            ))
          : ListView.separated(
              itemCount: contacts.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xff28342c)),
              itemBuilder: (context, index) {
                final contact = contacts[index];
                final contactAlias = contact['alias'] ?? 'Contacto';
                return ListTile(
                  leading: CircleAvatar(backgroundColor: const Color(0xff2b4031), child: Text(contactAlias.isEmpty ? '?' : contactAlias.substring(0, 1).toUpperCase(), style: const TextStyle(color: Color(0xffc6d9c8)))),
                  title: Text(contactAlias, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(contact['id'] ?? '', style: const TextStyle(fontSize: 10, color: Colors.white38), maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: PopupMenuButton<String>(onSelected: (choice) { if (choice == 'remove') _removeContact(contact); }, itemBuilder: (_) => const [PopupMenuItem(value: 'remove', child: Text('Eliminar contacto'))]),
                  onTap: () => _openContact(contact),
                );
              },
            ),
      ),
    ]);
  }

  Widget _buildNodes() {
    final incoming = engine.pendingPeer;
    final outgoing = engine.pendingOutgoingPin;
    return ListView(padding: const EdgeInsets.all(18), children: [
      Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(color: const Color(0xff1c2820), borderRadius: BorderRadius.circular(17), border: Border.all(color: const Color(0xff344a39))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('ESTADO DE LA RED', style: TextStyle(color: Color(0xffa8c5ac), fontSize: 11, letterSpacing: 2)),
          const SizedBox(height: 9),
          Row(children: [
            Icon(engine.running ? Icons.bluetooth_connected : Icons.bluetooth_disabled, color: engine.running ? const Color(0xff9bd4a1) : Colors.white54),
            const SizedBox(width: 9),
            Expanded(child: Text(status, style: const TextStyle(fontSize: 13, height: 1.4))),
          ]),
          const SizedBox(height: 9),
          Text('${engine.connectedPeerCount} conexiones activas · ${peers.length} nodos detectados', style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ]),
      ),
      if (incoming != null) Card(
        color: const Color(0xff342e1c),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('SOLICITUD DE CONEXIÓN', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xffe9d4a0))),
            Text('Código de seguridad: ${engine.pendingPin}', style: const TextStyle(fontSize: 15)),
            CheckboxListTile(contentPadding: EdgeInsets.zero, value: pinConfirmed, onChanged: (value) => setState(() => pinConfirmed = value ?? false), title: const Text('He comparado el código en ambos teléfonos')),
            FilledButton(onPressed: pinConfirmed ? () async {
              try {
                await engine.acceptPending(pinConfirmed: true);
                setState(() => pinConfirmed = false);
              } catch (error) { notice(error.toString()); }
            } : null, child: const Text('ACEPTAR CONEXIÓN')),
          ]),
        ),
      ),
      if (outgoing != null) Card(
        color: const Color(0xff203047),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('VERIFICA ESTE VECINO', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Código de seguridad: $outgoing', style: const TextStyle(fontSize: 15)),
            CheckboxListTile(contentPadding: EdgeInsets.zero, value: outgoingPinConfirmed, onChanged: (value) => setState(() => outgoingPinConfirmed = value ?? false), title: const Text('El código coincide con el otro teléfono')),
            FilledButton(onPressed: outgoingPinConfirmed ? () async {
              try {
                await engine.confirmOutgoingPin(pinConfirmed: true);
                setState(() => outgoingPinConfirmed = false);
              } catch (error) { notice(error.toString()); }
            } : null, child: const Text('CONFIRMAR VECINO')),
          ]),
        ),
      ),
      const SizedBox(height: 17),
      Row(children: [
        const Expanded(child: Text('DISPOSITIVOS CERCANOS', style: TextStyle(color: Color(0xffa8c5ac), fontSize: 11, letterSpacing: 2))),
        IconButton(onPressed: () => setState(() => peers = List<Peer>.from(peers)), icon: const Icon(Icons.refresh)),
      ]),
      if (peers.isEmpty) const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Text('No hay dispositivos visibles por Bluetooth en este momento. Mantén MESHBIT abierto en los teléfonos cercanos.', style: TextStyle(color: Colors.white54)),
      ),
      ...peers.map((peer) => Card(
        color: const Color(0xff1b241f),
        child: ListTile(
          leading: const Icon(Icons.bluetooth_searching, color: Color(0xffa8c5ac)),
          title: Text(peer.displayName),
          subtitle: Text(peer.id, style: const TextStyle(fontSize: 10, color: Colors.white38)),
          trailing: TextButton(onPressed: () => engine.connect(peer), child: const Text('CONECTAR')),
        ),
      )),
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      leading: selectedTab == 1 && selectedContactId != null ? IconButton(tooltip:'Volver a contactos',onPressed:()=>_selectTab(1),icon:const Icon(Icons.arrow_back)) : null,
      backgroundColor: const Color(0xff101611),
      titleSpacing: 16,
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('MESHBIT', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 3, fontSize: 18)),
        Text(engine.running ? 'RED LOCAL ACTIVA' : 'INICIANDO RED LOCAL', style: const TextStyle(fontSize: 9, letterSpacing: 1.8, color: Color(0xff9fbaa4))),
      ]),
      actions: [
        if (selectedTab == 0 || (selectedTab == 1 && selectedContactId != null))
          IconButton(tooltip: bubbleMode ? 'Vista terminal' : 'Vista burbujas', onPressed: () => setState(() => bubbleMode = !bubbleMode), icon: Icon(bubbleMode ? Icons.subject : Icons.chat_bubble_outline)),
        IconButton(tooltip: 'Mi identidad', onPressed: _showProfile, icon: const Icon(Icons.person_outline)),
      ],
    ),
    body: IndexedStack(
      index: selectedTab,
      children: [
        selectedTab == 0 ? _buildChat() : const SizedBox.shrink(),
        selectedTab == 1 ? (selectedContactId == null ? _buildContacts() : _buildChat()) : const SizedBox.shrink(),
        selectedTab == 2 ? _buildNodes() : const SizedBox.shrink(),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      backgroundColor: const Color(0xff151c17),
      indicatorColor: const Color(0xff2a3b2e),
      selectedIndex: selectedTab,
      onDestinationSelected: _selectTab,
      destinations: const [
        NavigationDestination(icon: Icon(Icons.hub_outlined), selectedIcon: Icon(Icons.hub), label: 'MESH'),
        NavigationDestination(icon: Icon(Icons.lock_outline), selectedIcon: Icon(Icons.lock), label: 'PRIVADOS'),
        NavigationDestination(icon: Icon(Icons.radar), selectedIcon: Icon(Icons.radar), label: 'NODOS'),
      ],
    ),
  );
}
