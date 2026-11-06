import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:nearby/nearby.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

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
  MeshEnvelope({required this.id, required this.from, required this.to, required this.createdAt, required this.ttl, required this.path, required this.nonce, required this.cipherText, required this.mac});
  final String id, from, to, nonce, cipherText, mac;
  final int createdAt, ttl;
  final List<String> path;
  Map<String, dynamic> toJson() => {'v':1,'id':id,'from':from,'to':to,'createdAt':createdAt,'ttl':ttl,'path':path,'nonce':nonce,'cipherText':cipherText,'mac':mac};
  factory MeshEnvelope.fromJson(Map<String,dynamic> j) => MeshEnvelope(id:j['id'],from:j['from'],to:j['to'],createdAt:j['createdAt'],ttl:j['ttl'],path:List<String>.from(j['path'] ?? const []),nonce:j['nonce'],cipherText:j['cipherText'],mac:j['mac']);
  MeshEnvelope forwarded(String node) => MeshEnvelope(id:id,from:from,to:to,createdAt:createdAt,ttl:ttl-1,path:[...path,node],nonce:nonce,cipherText:cipherText,mac:mac);
}

class MeshEngine {
  MeshEngine(this.onStatus, this.onMessage, this.onPeers);
  final void Function(String) onStatus;
  final void Function(String) onMessage;
  final void Function(List<NearbyPeer>) onPeers;
  final _nearby = NearbyService(localDisplayName: 'MESHBIT');
  final _uuid = const Uuid();
  final _aes = AesGcm.with256bits();
  final _peers = <String, NearbyPeer>{};
  final _seen = <String>{};
  StreamSubscription? _discoverySub, _requestsSub, _payloadSub;
  Database? _db;
  String nodeId = '';
  bool running = false;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    nodeId = prefs.getString('mesh.node') ?? _uuid.v4();
    await prefs.setString('mesh.node', nodeId);
    final dbPath = p.join(await getDatabasesPath(), 'meshbit_mesh.db');
    _db = await openDatabase(dbPath, version:1, onCreate:(db,_) async {
      await db.execute('CREATE TABLE packets(id TEXT PRIMARY KEY, json TEXT NOT NULL, delivered INTEGER NOT NULL DEFAULT 0, created INTEGER NOT NULL)');
    });
    final rows = await _db!.query('packets', where:'delivered=0');
    for (final row in rows) { try { _seen.add(row['id'] as String); } catch (_) {} }
  }

  Future<void> start() async {
    if (running) return;
    await init();
    _discoverySub = _nearby.discoveredPeersStream.listen((list) {
      for (final peer in list) { _peers[peer.id] = peer; }
      onPeers(_peers.values.toList());
    });
    _requestsSub = _nearby.connectionRequestsStream.listen((request) async {
      onStatus('Solicitud de conexión: ${request.peer.displayName} · código ${request.authenticationPin}. Compara el código con el otro teléfono antes de aceptar.');
      _pendingRequest = request.peer.id;
      _pendingPin = request.authenticationPin;
    });
    _payloadSub = _nearby.payloadReceivedStream.listen((payload) async {
      if (payload.type != PayloadType.bytes || payload.bytes == null) return;
      await _receive(payload.bytes!);
    });
    await _nearby.startAdvertising(options: AdvertisingOptions(serviceId:'meshbit',strategy:DiscoveryStrategy.hybrid,securityMode:SecurityMode.pinVerification));
    await _nearby.startDiscovery(options: const DiscoveryOptions(serviceId:'meshbit',strategy:DiscoveryStrategy.hybrid));
    running = true;
    onStatus('Buscando dispositivos cercanos. No requiere internet ni datos móviles.');
  }

  String? _pendingRequest, _pendingPin;
  String? get pendingPeer => _pendingRequest;
  String? get pendingPin => _pendingPin;
  Future<void> acceptPending() async {
    final id = _pendingRequest;
    if (id == null) return;
    await _nearby.acceptConnection(id);
    _pendingRequest = null; _pendingPin = null;
    onStatus('Conexión local aceptada. Canal protegido activo.');
    await _flush();
  }

  Future<void> connect(NearbyPeer peer) async {
    onStatus('Solicitando conexión segura a ${peer.displayName}…');
    final ok = await _nearby.requestConnection(peer);
    if (ok) { _peers[peer.id] = peer; onPeers(_peers.values.toList()); onStatus('Conexión establecida con ${peer.displayName}.'); await _flush(); }
    else { onStatus('La conexión no se completó.'); }
  }

  Future<void> sendText(String destination, String text, String keyHex) async {
    final key = _parseKey(keyHex);
    if (key == null) throw Exception('La clave debe tener exactamente 64 caracteres hexadecimales.');
    if (destination.trim().isEmpty) throw Exception('Falta el ID del destinatario.');
    final box = await _aes.encrypt(utf8.encode(text), secretKey:SecretKey(key));
    final envelope = MeshEnvelope(id:_uuid.v4(),from:nodeId,to:destination.trim(),createdAt:DateTime.now().millisecondsSinceEpoch,ttl:12,path:[nodeId],nonce:base64Encode(box.nonce),cipherText:base64Encode(box.cipherText),mac:base64Encode(box.mac.bytes));
    await _store(envelope);
    await _broadcast(envelope);
    onStatus('Mensaje cifrado guardado y enviado a la red. Se reenviará si aparece otra ruta.');
  }

  Future<void> _receive(Uint8List bytes) async {
    try {
      final map = jsonDecode(utf8.decode(bytes)) as Map<String,dynamic>;
      final env = MeshEnvelope.fromJson(map);
      if (_seen.contains(env.id) || env.path.contains(nodeId) || env.ttl < 0) return;
      _seen.add(env.id);
      await _store(env);
      if (env.to == nodeId) {
        onMessage('Mensaje cifrado recibido de ${env.from}. Para leerlo, usa la misma clave de conversación en el panel de envío.');
        await _db!.update('packets', {'delivered':1}, where:'id=?',[env.id]);
      } else if (env.ttl > 0) {
        await _broadcast(env.forwarded(nodeId));
      }
    } catch (_) { onStatus('Se descartó un paquete local inválido.'); }
  }

  Future<void> _store(MeshEnvelope env) async {
    await _db!.insert('packets', {'id':env.id,'json':jsonEncode(env.toJson()),'created':env.createdAt}, conflictAlgorithm:ConflictAlgorithm.ignore);
  }
  Future<void> _broadcast(MeshEnvelope env) async {
    if (_peers.isEmpty) { onStatus('Sin vecinos conectados: mensaje guardado para retransmitir más tarde.'); return; }
    await _nearby.sendBytesToAll(Uint8List.fromList(utf8.encode(jsonEncode(env.toJson()))));
  }
  Future<void> _flush() async {
    final rows = await _db!.query('packets', where:'delivered=0', orderBy:'created ASC', limit:100);
    for (final row in rows) {
      try {
        final env = MeshEnvelope.fromJson(jsonDecode(row['json'] as String));
        if (!env.path.contains(nodeId) && env.ttl > 0) await _broadcast(env.forwarded(nodeId));
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
    await _discoverySub?.cancel(); await _requestsSub?.cancel(); await _payloadSub?.cancel();
    await _nearby.dispose(); await _db?.close();
  }
}

class MeshHome extends StatefulWidget {
  const MeshHome({super.key});
  @override State<MeshHome> createState() => _MeshHomeState();
}
class _MeshHomeState extends State<MeshHome> {
  late final MeshEngine engine;
  String status = 'MESH apagado';
  String message = '';
  List<NearbyPeer> peers = [];
  final destination = TextEditingController();
  final body = TextEditingController();
  final key = TextEditingController();
  bool busy = false;
  @override void initState() { super.initState(); engine = MeshEngine((s)=>setState(()=>status=s),(m)=>setState(()=>message=m),(p)=>setState(()=>peers=p)); }
  @override void dispose() { destination.dispose(); body.dispose(); key.dispose(); engine.dispose(); super.dispose(); }
  void notice(String s) { if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s))); }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('MESHBIT',style:TextStyle(letterSpacing:4,fontWeight:FontWeight.w800)),actions:[Padding(padding:const EdgeInsets.only(right:16),child:Center(child:Text(engine.running?'MESH ACTIVO':'OFFLINE',style:TextStyle(color:engine.running?Colors.lightGreenAccent:Colors.white54,fontSize:11,letterSpacing:1.5))))]),
    body: ListView(padding:const EdgeInsets.all(18),children:[
      Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(color:const Color(0xff1b241e),borderRadius:BorderRadius.circular(18),border:Border.all(color:const Color(0xff35483a))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('RED LOCAL',style:TextStyle(color:Color(0xffa8c5ac),letterSpacing:2,fontSize:11)),
        const SizedBox(height:8), Text(status,style:const TextStyle(fontSize:15)),
        const SizedBox(height:12), SelectableText('ID de este dispositivo\n${engine.nodeId.isEmpty?'Se genera al iniciar':engine.nodeId}',style:const TextStyle(color:Colors.white70,fontSize:12)),
        const SizedBox(height:16),Row(children:[Expanded(child:FilledButton.icon(onPressed:busy||engine.running?null,icon:const Icon(Icons.radar),label:const Text('INICIAR MESH'))),const SizedBox(width:8),OutlinedButton(onPressed:engine.running?()=>engine.stop():null,child:const Text('DETENER'))])
      ])),
      if (engine.pendingPeer != null) Card(color:const Color(0xff332d1a),child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('VERIFICACIÓN DE VECINO',style:TextStyle(fontWeight:FontWeight.bold)),Text('Código de seguridad: ${engine.pendingPin}'),const SizedBox(height:8),FilledButton(onPressed:()=>engine.acceptPending(),child:const Text('ACEPTAR CONEXIÓN'))]))),
      const SizedBox(height:18),const Text('DISPOSITIVOS CERCANOS',style:TextStyle(letterSpacing:2,fontSize:11,color:Color(0xffa8c5ac))),
      if(peers.isEmpty) const Padding(padding:EdgeInsets.symmetric(vertical:16),child:Text('Todavía no se detectan vecinos. Ambos teléfonos deben abrir MESHBIT e iniciar la búsqueda.')),
      ...peers.map((peer)=>ListTile(leading:const Icon(Icons.bluetooth_searching),title:Text(peer.displayName),subtitle:Text(peer.id),trailing:TextButton(onPressed:()=>engine.connect(peer),child:const Text('CONECTAR')))),
      const Divider(height:32),const Text('MENSAJE CIFRADO',style:TextStyle(letterSpacing:2,fontSize:11,color:Color(0xffa8c5ac))),
      const SizedBox(height:8),TextField(controller:destination,decoration:const InputDecoration(labelText:'ID del destinatario',hintText:'ID MESHBIT del otro dispositivo',border:OutlineInputBorder())),
      const SizedBox(height:10),TextField(controller:key,decoration:const InputDecoration(labelText:'Clave de conversación (64 caracteres hex)',border:OutlineInputBorder()),obscureText:true),
      Align(alignment:Alignment.centerLeft,child:TextButton.icon(onPressed:()=>setState(()=>key.text=MeshEngine.generateKey()),icon:const Icon(Icons.key),label:const Text('GENERAR CLAVE SEGURA'))),
      const SizedBox(height:8),TextField(controller:body,minLines:2,maxLines:4,decoration:const InputDecoration(labelText:'Mensaje',border:OutlineInputBorder())),
      const SizedBox(height:12),FilledButton.icon(onPressed:busy?null:()async{setState(()=>busy=true);try{await engine.sendText(destination.text,body.text,key.text);body.clear();notice('Mensaje guardado en la cola mesh.');}catch(e){notice(e.toString());}finally{if(mounted)setState(()=>busy=false);}},icon:const Icon(Icons.send),label:const Text('ENVIAR POR MESH')),
      if(message.isNotEmpty) Padding(padding:const EdgeInsets.only(top:18),child:Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:const Color(0xff202b23),borderRadius:BorderRadius.circular(12)),child:Text(message))),
      const SizedBox(height:20),const Text('La retransmisión usa paquetes cifrados, TTL de 12 saltos y deduplicación por ID. Los nodos intermedios almacenan y reenvían el paquete sin descifrarlo. Para leer un mensaje, emisor y destinatario deben compartir la misma clave de conversación por un canal seguro.',style:TextStyle(color:Colors.white54,fontSize:12,height:1.5))
    ]),
  );
}
