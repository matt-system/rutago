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
    if (ttl is! int || ttl < 0 || ttl > 12) {
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

class MeshEngine {
  MeshEngine(this.onStatus, this.onMessage, this.onPeers);
  final void Function(String) onStatus;
  final void Function(MeshEnvelope) onMessage;
  final void Function(List<Peer>) onPeers;
  late final NearbyService _nearby;
  final _uuid = const Uuid();
  final _aes = AesGcm.with256bits();
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
    _db = await openDatabase(dbPath, version:2, onCreate:(db,_) async {
      await db.execute('CREATE TABLE packets(id TEXT PRIMARY KEY, json TEXT NOT NULL, delivered INTEGER NOT NULL DEFAULT 0, originated INTEGER NOT NULL DEFAULT 0, created INTEGER NOT NULL)');
    }, onUpgrade:(db,oldVersion,newVersion) async {
      if(oldVersion < 2) await db.execute('ALTER TABLE packets ADD COLUMN originated INTEGER NOT NULL DEFAULT 0');
    });
    await _db!.delete('packets', where:'created < ?', whereArgs:[DateTime.now().subtract(const Duration(days:7)).millisecondsSinceEpoch]);
    final rows = await _db!.query('packets');
    for (final row in rows) { try { _seen.add(row['id'] as String); } catch (_) {} }
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
      }
    });
    _payloadSub = _nearby.payloadReceivedStream.listen((payload) async {
      if (payload.type != PayloadType.bytes || payload.bytes == null) return;
      final sourcePeer = payload.peerId;
      if (sourcePeer == null || !_trustedPeers.contains(sourcePeer)) {
        onStatus('Paquete descartado: el vecino todavía no está verificado.');
        return;
      }
      await _receive(payload.bytes!);
    });
    await _nearby.startAdvertising(options: const AdvertisingOptions(serviceId:'meshbit',strategy:DiscoveryStrategy.bleOnly,securityMode:SecurityMode.pinVerification));
    await _nearby.startDiscovery(options: const DiscoveryOptions(serviceId:'meshbit',strategy:DiscoveryStrategy.bleOnly));
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
        onStatus('La conexión no se completó.');
      }
    } finally {
      _outgoingAttemptPeer = null;
    }
  }

  Future<void> confirmOutgoingPin({required bool pinConfirmed}) async {
    if (!pinConfirmed) throw Exception('Compara el código en ambos teléfonos antes de confirmar.');
    final peerId = pendingOutgoingPeer;
    if (peerId == null || pendingOutgoingPin == null) return;
    _trustedPeers.add(peerId);
    pendingOutgoingPeer = null;
    pendingOutgoingPin = null;
    onStatus('Vecino verificado. Ya puede retransmitir paquetes MESH.');
    await _flush();
  }

  Future<void> sendText(String destination, String text, String keyHex) async {
    final key = _parseKey(keyHex);
    if (key == null) throw Exception('La clave debe tener exactamente 64 caracteres hexadecimales.');
    if (destination.trim().isEmpty) throw Exception('Falta el ID del destinatario.');
    if (text.trim().isEmpty) throw Exception('Escribe un mensaje antes de enviarlo.');
    if (utf8.encode(text).length > 4096) throw Exception('El mensaje supera el límite de 4 KB.');
    final inner = jsonEncode({'from':nodeId,'to':destination.trim(),'text':text,'createdAt':DateTime.now().millisecondsSinceEpoch});
    final box = await _aes.encrypt(utf8.encode(inner), secretKey:SecretKey(key));
    final envelope = MeshEnvelope(id:_uuid.v4(),ttl:12,nonce:base64Encode(box.nonce),cipherText:base64Encode(box.cipherText),mac:base64Encode(box.mac.bytes));
    _seen.add(envelope.id);
    await _store(envelope, originated:true);
    await _broadcast(envelope);
    onStatus('Mensaje cifrado guardado y enviado a la red. Se reenviará si aparece otra ruta.');
  }

  Future<void> _receive(Uint8List bytes) async {
    try {
      if (bytes.length > 6200) return;
      final map = jsonDecode(utf8.decode(bytes)) as Map<String,dynamic>;
      final env = MeshEnvelope.fromJson(map);
      final existing = await _db!.query('packets', where:'id=?', whereArgs:[env.id], limit:1);
      if (_seen.contains(env.id)) {
        if (existing.isNotEmpty && (existing.first['delivered'] as int) == 0 && env.ttl > 0) {
          final saved = MeshEnvelope.fromJson(jsonDecode(existing.first['json'] as String));
          final improved = env.forwarded();
          if (improved.ttl > saved.ttl) {
            await _db!.update('packets', {'json':jsonEncode(improved.toJson()),'created':DateTime.now().millisecondsSinceEpoch}, where:'id=?', whereArgs:[env.id]);
            await _broadcast(improved);
          }
        }
        return;
      }
      _seen.add(env.id);
      final forwarded = env.ttl > 0 ? env.forwarded() : env;
      await _store(forwarded);
      onMessage(forwarded);
      if (env.ttl > 0) await _broadcast(forwarded);
    } catch (_) { onStatus('Se descartó un paquete local inválido.'); }
  }

  Future<String> decryptMessage(MeshEnvelope env, String keyHex) async {
    final key = _parseKey(keyHex);
    if (key == null) throw Exception('La clave debe tener exactamente 64 caracteres hexadecimales.');
    final clear = await _aes.decrypt(SecretBox(base64Decode(env.cipherText), nonce:base64Decode(env.nonce), mac:Mac(base64Decode(env.mac))), secretKey:SecretKey(key));
    final decoded = jsonDecode(utf8.decode(clear)) as Map<String,dynamic>;
    if (decoded['to'] != nodeId) throw Exception('Este paquete no está dirigido a este dispositivo.');
    await _db!.update('packets', {'delivered':1}, where:'id=?', whereArgs:[env.id]);
    return '${decoded['from']}: ${decoded['text']}';
  }

  Future<void> _store(MeshEnvelope env, {bool originated = false}) async {
    await _db!.insert('packets', {'id':env.id,'json':jsonEncode(env.toJson()),'originated':originated ? 1 : 0,'created':DateTime.now().millisecondsSinceEpoch}, conflictAlgorithm:ConflictAlgorithm.ignore);
  }

  Future<List<MeshEnvelope>> loadInbox() async {
    await init();
    final rows = await _db!.query('packets', where:'originated=0', orderBy:'created DESC', limit:100);
    return rows.map((row) => MeshEnvelope.fromJson(jsonDecode(row['json'] as String) as Map<String,dynamic>)).toList();
  }
  Future<void> _broadcast(MeshEnvelope env) async {
    final neighbors = _nearby.connectedPeers
        .where((peer) => _trustedPeers.contains(peer.id))
        .toList();
    if (neighbors.isEmpty) {
      onStatus('Sin vecinos verificados: paquete guardado localmente para retransmitir más tarde.');
      return;
    }
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(env.toJson())));
    await Future.wait(neighbors.map((peer) => _nearby.sendBytes(peer.id, bytes)));
  }
  Future<void> _flush() async {
    final rows = await _db!.query('packets', where:'delivered=0', orderBy:'created ASC', limit:100);
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
    running = false; onStatus('MESH detenido.');
  }
  Future<void> dispose() async {
    await _discoverySub?.cancel(); await _requestsSub?.cancel(); await _payloadSub?.cancel(); await _peerStateSub?.cancel();
    if (_initialized) await _nearby.dispose();
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

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) { if (mounted) setState(() => loading = true); },
        onPageFinished: (_) { if (mounted) setState(() => loading = false); },
        onWebResourceError: (_) { if (mounted) setState(() => loading = false); },
      ))
      ..loadRequest(Uri.parse('https://meshbit.matthieupierremarie.workers.dev/app/'));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('CHAT MESHBIT')),
    body: Stack(children:[
      WebViewWidget(controller:controller),
      if(loading) const LinearProgressIndicator(),
    ]),
  );
}

class MeshHome extends StatefulWidget {
  const MeshHome({super.key});
  @override State<MeshHome> createState() => _MeshHomeState();
}
class _MeshHomeState extends State<MeshHome> {
  late final MeshEngine engine;
  String status = 'MESH apagado';
  final List<MeshEnvelope> inbox = [];
  final Map<String,String> decryptedMessages = {};
  List<Peer> peers = [];
  final destination = TextEditingController();
  final body = TextEditingController();
  final key = TextEditingController();
  bool busy = false;
  bool pinConfirmed = false;
  bool outgoingPinConfirmed = false;
  @override void initState() { super.initState(); engine = MeshEngine((s)=>setState(() { status=s; if(s.startsWith('Solicitud de conexión:')) pinConfirmed=false; }),(m)=>setState((){if(!inbox.any((e)=>e.id==m.id)){inbox.insert(0,m); if(inbox.length>100) inbox.removeLast();}}),(p)=>setState(()=>peers=p)); _loadLocalInbox(); }
  Future<void> _loadLocalInbox() async { try { final packets=await engine.loadInbox(); if(mounted) setState(()=>inbox..clear()..addAll(packets)); } catch(e) { if(mounted) notice('No se pudo abrir la bandeja local: $e'); } }
  @override void dispose() { destination.dispose(); body.dispose(); key.dispose(); engine.dispose(); super.dispose(); }
  void notice(String s) { if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s))); }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('MESHBIT',style:TextStyle(letterSpacing:4,fontWeight:FontWeight.w800)),actions:[IconButton(tooltip:'Abrir chat de Meshbit (requiere internet)',icon:const Icon(Icons.chat_bubble_outline),onPressed:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>const MeshbitChatPage()))),Padding(padding:const EdgeInsets.only(right:16),child:Center(child:Text(engine.running?'MESH ACTIVO':'OFFLINE',style:TextStyle(color:engine.running?Colors.lightGreenAccent:Colors.white54,fontSize:11,letterSpacing:1.5))))]),
    body: ListView(padding:const EdgeInsets.all(18),children:[
      Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(color:const Color(0xff1b241e),borderRadius:BorderRadius.circular(18),border:Border.all(color:const Color(0xff35483a))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('RED LOCAL',style:TextStyle(color:Color(0xffa8c5ac),letterSpacing:2,fontSize:11)),
        const SizedBox(height:8), Text(status,style:const TextStyle(fontSize:15)),
        const SizedBox(height:12),
        Row(crossAxisAlignment:CrossAxisAlignment.center,children:[
          Expanded(child:SelectableText('ID de este dispositivo\n${engine.nodeId.isEmpty?'Se genera al iniciar':engine.nodeId}',style:const TextStyle(color:Colors.white70,fontSize:12))),
          IconButton(tooltip:'Copiar ID',onPressed:engine.nodeId.isEmpty?null:()async{await Clipboard.setData(ClipboardData(text:engine.nodeId));notice('ID copiado. Compártelo con tu contacto.');},icon:const Icon(Icons.copy))
        ]),
        const SizedBox(height:16),Row(children:[Expanded(child:FilledButton.icon(onPressed:busy||engine.running?null:()async{setState(()=>busy=true);try{await engine.start();}catch(e){notice('No se pudo iniciar MESH: $e');}finally{if(mounted)setState(()=>busy=false);}},icon:const Icon(Icons.radar),label:const Text('INICIAR MESH'))),const SizedBox(width:8),OutlinedButton(onPressed:engine.running?()=>engine.stop():null,child:const Text('DETENER'))])
      ])),
      if (engine.pendingPeer != null) Card(color:const Color(0xff332d1a),child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('VERIFICACIÓN DE VECINO',style:TextStyle(fontWeight:FontWeight.bold)),Text('Código de seguridad: ${engine.pendingPin}'),CheckboxListTile(contentPadding:EdgeInsets.zero,value:pinConfirmed,onChanged:(value)=>setState(()=>pinConfirmed=value??false),title:const Text('He comparado el código en ambos teléfonos')),const SizedBox(height:8),FilledButton(onPressed:pinConfirmed?()async{try{await engine.acceptPending(pinConfirmed:pinConfirmed);setState(()=>pinConfirmed=false);}catch(e){notice(e.toString());}}:null,child:const Text('ACEPTAR CONEXIÓN'))]))),
      if (engine.pendingOutgoingPin != null) Card(color:const Color(0xff203047),child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('VERIFICA ESTE VECINO',style:TextStyle(fontWeight:FontWeight.bold)),
        Text('Código de seguridad: ${engine.pendingOutgoingPin}'),
        CheckboxListTile(contentPadding:EdgeInsets.zero,value:outgoingPinConfirmed,onChanged:(value)=>setState(()=>outgoingPinConfirmed=value??false),title:const Text('El código coincide con el otro teléfono')),
        FilledButton(onPressed:outgoingPinConfirmed?()async{try{await engine.confirmOutgoingPin(pinConfirmed:outgoingPinConfirmed);setState(()=>outgoingPinConfirmed=false);}catch(e){notice(e.toString());}}:null,child:const Text('CONFIRMAR VECINO'))
      ]))),
      const SizedBox(height:18),const Text('DISPOSITIVOS CERCANOS',style:TextStyle(letterSpacing:2,fontSize:11,color:Color(0xffa8c5ac))),
      if(peers.isEmpty) const Padding(padding:EdgeInsets.symmetric(vertical:16),child:Text('Todavía no se detectan vecinos. Ambos teléfonos deben abrir MESHBIT e iniciar la búsqueda.')),
      ...peers.map((peer)=>ListTile(leading:const Icon(Icons.bluetooth_searching),title:Text(peer.displayName),subtitle:Text(peer.id),trailing:TextButton(onPressed:()=>engine.connect(peer),child:const Text('CONECTAR')))),
      const Divider(height:32),const Text('MENSAJE CIFRADO',style:TextStyle(letterSpacing:2,fontSize:11,color:Color(0xffa8c5ac))),
      const SizedBox(height:8),TextField(controller:destination,decoration:const InputDecoration(labelText:'ID del destinatario',hintText:'ID MESHBIT del otro dispositivo',border:OutlineInputBorder())),
      const SizedBox(height:10),TextField(controller:key,decoration:InputDecoration(labelText:'Clave de conversación (64 caracteres hex)',border:const OutlineInputBorder(),suffixIcon:IconButton(tooltip:'Copiar clave',icon:const Icon(Icons.copy),onPressed:()async{if(key.text.isEmpty){notice('Primero genera o ingresa una clave.');return;}await Clipboard.setData(ClipboardData(text:key.text));notice('Clave copiada. Compártela por un canal seguro, nunca por MESH.');})),obscureText:true),
      Align(alignment:Alignment.centerLeft,child:TextButton.icon(onPressed:()=>setState(()=>key.text=MeshEngine.generateKey()),icon:const Icon(Icons.key),label:const Text('GENERAR CLAVE SEGURA'))),
      const SizedBox(height:8),TextField(controller:body,minLines:2,maxLines:4,decoration:const InputDecoration(labelText:'Mensaje',border:OutlineInputBorder())),
      const SizedBox(height:12),FilledButton.icon(onPressed:busy?null:()async{setState(()=>busy=true);try{await engine.sendText(destination.text,body.text,key.text);body.clear();notice('Mensaje guardado en la cola mesh.');}catch(e){notice(e.toString());}finally{if(mounted)setState(()=>busy=false);}},icon:const Icon(Icons.send),label:const Text('ENVIAR POR MESH')),
      const SizedBox(height:18),
      Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
        const Text('BANDEJA MESH',style:TextStyle(letterSpacing:2,fontSize:11,color:Color(0xffa8c5ac))),
        Text('${inbox.length} paquetes',style:const TextStyle(color:Colors.white54,fontSize:12))
      ]),
      if(inbox.isEmpty) const Padding(padding:EdgeInsets.symmetric(vertical:14),child:Text('Los mensajes que lleguen por esta red aparecerán aquí. Los nodos intermedios los guardan y reenvían sin leerlos.')),
      ...inbox.map((packet)=>Card(
        color:const Color(0xff202b23),
        child:Padding(
          padding:const EdgeInsets.all(14),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text('PAQUETE ${packet.id.substring(0,8)} · TTL ${packet.ttl}',style:const TextStyle(color:Color(0xffa8c5ac),fontSize:11,letterSpacing:1)),
            const SizedBox(height:8),
            FilledButton.tonal(onPressed:()async{
              try{
                final clear=await engine.decryptMessage(packet,key.text);
                setState(()=>decryptedMessages[packet.id]=clear);
              }catch(e){notice('No se pudo abrir: clave incorrecta, paquete alterado o destinatario distinto.');}
            },child:const Text('ABRIR CON CLAVE')),
            if(decryptedMessages.containsKey(packet.id)) Padding(padding:const EdgeInsets.only(top:10),child:Text(decryptedMessages[packet.id]!,style:const TextStyle(fontSize:16)))
          ])
        )
      )),
      const SizedBox(height:20),const Text('La retransmisión usa paquetes cifrados, TTL de 12 saltos y deduplicación por ID. Los nodos intermedios almacenan y reenvían el paquete sin descifrarlo. MESH usa Bluetooth LE, sin Wi-Fi ni datos móviles. Los IDs de emisor y destinatario van dentro del cifrado. Los relays solo ven un ID aleatorio, TTL y ciphertext. Emisor y destinatario deben compartir la clave por un canal seguro.',style:TextStyle(color:Colors.white54,fontSize:12,height:1.5))
    ]),
  );
}
