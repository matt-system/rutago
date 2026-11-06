import React, {useEffect, useRef, useState} from "react";
import {View,Text,TextInput,Pressable,ScrollView,KeyboardAvoidingView,Platform,StyleSheet,ActivityIndicator} from "react-native";
import * as SecureStore from "expo-secure-store";
import {Identity,generateIdentity,encryptMessage,decryptMessage,fingerprint,newAuthToken} from "../src/crypto/e2ee";
import * as Api from "../src/crypto/api";

type ChatItem={id:string;sender:string;body:string;mine:boolean;time:number;fingerprint?:string};
const ID_KEY="meshbit.identity.v1", TOKEN_KEY="meshbit.auth.v1", USER_KEY="meshbit.username.v1";

export default function Home(){
 const [identity,setIdentity]=useState<Identity|null>(null);
 const [token,setToken]=useState("");
 const [username,setUsername]=useState("");
 const [registerName,setRegisterName]=useState("");
 const [recipient,setRecipient]=useState("");
 const [draft,setDraft]=useState("");
 const [items,setItems]=useState<ChatItem[]>([]);
 const [status,setStatus]=useState("CONECTANDO");
 const [error,setError]=useState("");
 const [busy,setBusy]=useState(false);
 const [myFingerprint,setMyFingerprint]=useState("");
 const [contactFingerprint,setContactFingerprint]=useState("");
 const seen=useRef<Set<string>>(new Set());

 useEffect(()=>{(async()=>{
  try{
   const [savedIdentity,savedToken,savedUsername]=await Promise.all([
    SecureStore.getItemAsync(ID_KEY),SecureStore.getItemAsync(TOKEN_KEY),SecureStore.getItemAsync(USER_KEY)
   ]);
   if(savedIdentity&&savedToken){
    const parsed=JSON.parse(savedIdentity) as Identity;
    setIdentity(parsed);setToken(savedToken);setUsername(savedUsername||"");
    setMyFingerprint(await fingerprint(parsed.boxPublicKey,parsed.signingPublicKey));
    try{
     const me=await Api.me(savedToken);setUsername(me.username);
     await SecureStore.setItemAsync(USER_KEY,me.username);
     setStatus("CUENTA CONECTADA · CIFRADO IMPLEMENTADO");
    }catch{setStatus("SIN CONEXIÓN · REINTENTANDO RELAY");}
   }else setStatus("CREA TU CUENTA");
  }catch(e){setError(String(e));setStatus("NO SE PUDO RECUPERAR LA CUENTA");}
 })();},[]);

 async function createAccount(){
  const name=registerName.trim();
  if(!/^[a-zA-Z0-9_.-]{3,24}$/.test(name)){setError("Usa 3–24 caracteres: letras, números, punto, guion o guion bajo.");return;}
  setBusy(true);setError("");
  try{
   const keys=generateIdentity(), auth=newAuthToken();
   const created=await Api.register(name,auth,keys.boxPublicKey,keys.signingPublicKey);
   await SecureStore.setItemAsync(ID_KEY,JSON.stringify(keys));
   await SecureStore.setItemAsync(TOKEN_KEY,auth);
   await SecureStore.setItemAsync(USER_KEY,created.username);
   setIdentity(keys);setToken(auth);setUsername(created.username);
   setMyFingerprint(await fingerprint(keys.boxPublicKey,keys.signingPublicKey));
   setStatus("CUENTA CONECTADA · CIFRADO IMPLEMENTADO");
  }catch(e){setError(e instanceof Error?e.message:String(e));}
  finally{setBusy(false);}
 }

 async function refreshInbox(currentToken=token,currentIdentity=identity,currentUsername=username){
  if(!currentToken||!currentIdentity||!currentUsername)return;
  try{
   const result=await Api.inbox(currentToken);
   const received:string[]=[];
   for(const msg of result.messages){
    if(seen.current.has(msg.id))continue;
    seen.current.add(msg.id);
    try{
     const body=decryptMessage(msg,currentUsername,currentIdentity);
     const senderFingerprint=await fingerprint(msg.senderBoxPublicKey,msg.senderSigningPublicKey);
     setItems(old=>old.some(x=>x.id===msg.id)?old:[...old,{id:msg.id,sender:msg.sender,body,mine:false,time:msg.createdAt,fingerprint:senderFingerprint}]);
     received.push(msg.id);
    }catch(e){setError("Mensaje rechazado: "+(e instanceof Error?e.message:"firma o clave no válida"));received.push(msg.id);}
   }
   if(received.length)await Api.acknowledge(currentToken,received);
   setStatus("EN LÍNEA · BUZÓN CIFRADO");
  }catch{setStatus("SIN CONEXIÓN · REINTENTANDO");}
 }

 useEffect(()=>{
  if(!token||!identity||!username)return;
  refreshInbox(token,identity,username);
  const timer=setInterval(()=>refreshInbox(token,identity,username),5000);
  return ()=>clearInterval(timer);
 },[token,identity,username]);

 async function sendMessage(){
  const text=draft.trim(), to=recipient.trim();
  if(!text||!to||!identity||!token)return;
  setBusy(true);setError("");
  try{
   const keys=await Api.getKeys(token,to);
   const fp=await fingerprint(keys.boxPublicKey,keys.signingPublicKey);
   setContactFingerprint(fp);
   const envelope=encryptMessage(text,keys.username,keys.boxPublicKey,identity);
   await Api.send(token,envelope);
   setItems(old=>[...old,{id:envelope.id,sender:username,body:text,mine:true,time:Date.now(),fingerprint:fp}]);
   setDraft("");
  }catch(e){setError(e instanceof Error?e.message:String(e));}
  finally{setBusy(false);}
 }

 if(!identity||!token)return <KeyboardAvoidingView style={s.root} behavior={Platform.OS==="ios"?"padding":undefined}>
  <View style={s.header}><Text style={s.logo}>MESH<Text style={{color:"#a4edb5"}}>BIT</Text></Text><Text style={s.status}>● PRIVATE BETA</Text></View>
  <View style={s.meta}><Text style={s.label}>[ PRIVATE MESSAGING ]</Text><Text style={s.heading}>Tu cuenta <Text style={{color:"#a4edb5"}}>/ 01</Text></Text><Text style={s.sub}>CUENTA ÚNICA · CLAVES EN ESTE DISPOSITIVO</Text></View>
  <View style={s.panel}><Text style={s.panelTitle}>CREAR IDENTIDAD MESHBIT</Text><Text style={s.small}>Elige un nombre de usuario. Tus claves privadas se generan y guardan en el teléfono; Cloudflare recibe solo las claves públicas y los mensajes cifrados.</Text>
   <Text style={s.fieldLabel}>NOMBRE DE USUARIO</Text><TextInput value={registerName} onChangeText={setRegisterName} autoCapitalize="none" autoCorrect={false} style={s.input} placeholder="ej. lucas23" placeholderTextColor="#718078"/>
   <Pressable onPress={createAccount} disabled={busy} style={s.checkButton}>{busy?<ActivityIndicator color="#080b0a"/>:<Text style={s.checkText}>CREAR CUENTA SEGURA</Text>}</Pressable>
   <Text style={s.small}>Importante: esta primera versión queda vinculada a este dispositivo. Si lo pierdes o borras sus datos, no hay recuperación de cuenta todavía.</Text>
  </View>{!!error&&<Text style={s.error}>{error}</Text>}<Text style={s.warning}>[!] Versión inicial de cifrado 1 a 1. Verifica la huella de seguridad de cada contacto por otro canal. Aún no incluye ratchet de Signal, multi-dispositivo ni auditoría externa.</Text>
 </KeyboardAvoidingView>;

 return <KeyboardAvoidingView style={s.root} behavior={Platform.OS==="ios"?"padding":undefined}>
  <View style={s.header}><Text style={s.logo}>MESH<Text style={{color:"#a4edb5"}}>BIT</Text></Text><Text style={s.status}>● {status}</Text></View>
  <View style={s.meta}><Text style={s.label}>[ PRIVATE MESSAGING ]</Text><Text style={s.heading}>Hola, {username}</Text><Text style={s.sub}>CIFRADO EN EL DISPOSITIVO · RELAY CLOUDFLARE</Text></View>
  <View style={s.panel}>
   <Text style={s.panelTitle}>IDENTIDAD Y CIFRADO</Text>
   <Text style={s.contact}>● Claves privadas <Text style={s.ready}>· GUARDADAS EN EL TELÉFONO</Text></Text>
   <Text style={s.contact}>● Relay Cloudflare <Text style={s.ready}>· SOLO TRANSPORTA CIPHERTEXT</Text></Text>
   <Text style={s.small}>Tu huella: {myFingerprint||"calculando..."}</Text>
   <Text style={s.fieldLabel}>ENVIAR A (USUARIO)</Text>
   <TextInput value={recipient} onChangeText={setRecipient} autoCapitalize="none" autoCorrect={false} style={s.input} placeholder="nombre del contacto" placeholderTextColor="#718078"/>
   {!!contactFingerprint&&<Text style={s.small}>Huella del contacto: {contactFingerprint}. Compruébala con esa persona por otro canal antes de confiar en su identidad.</Text>}
  </View>
  <View style={s.chat}><View style={s.chatHead}><Text style={s.panelTitle}># conversación</Text><Text style={s.dim}>E2EE 1:1</Text></View>
   <ScrollView style={{flex:1}} contentContainerStyle={{paddingVertical:12}}>
    {items.map(m=><View key={m.id} style={[s.bubble,m.mine?s.mineBubble:s.theirBubble]}><Text style={s.who}>{m.mine?"tú":m.sender}</Text><Text style={s.body}>{m.body}</Text>{!!m.fingerprint&&<Text style={s.small}>huella: {m.fingerprint}</Text>}</View>)}
    {items.length===0&&<Text style={s.dim}>Aún no hay mensajes. Escribe el nombre de usuario de otro dispositivo Meshbit para comenzar.</Text>}
   </ScrollView>
   <View style={s.compose}><TextInput value={draft} onChangeText={setDraft} placeholder="Mensaje (se cifra antes de enviar)..." placeholderTextColor="#718078" style={s.input} multiline/><Pressable onPress={sendMessage} disabled={busy||!draft.trim()||!recipient.trim()} style={s.send}>{busy?<ActivityIndicator color="#080b0a"/>:<Text style={s.sendText}>↗</Text>}</Pressable></View>
  </View>
  {!!error&&<Text style={s.error}>{error}</Text>}
  <Text style={s.warning}>[!] Beta: cifra autenticada con claves por dispositivo y clave efímera por mensaje. No tiene aún ratchet de doble vía ni recuperación de claves. No usar para comunicaciones de alto riesgo.</Text>
 </KeyboardAvoidingView>;
}

const s=StyleSheet.create({
 root:{flex:1,backgroundColor:"#080b0a",padding:18,paddingTop:Platform.OS==="android"?44:62},
 header:{height:48,borderBottomWidth:1,borderColor:"#26332d",flexDirection:"row",justifyContent:"space-between",alignItems:"flex-start"},
 logo:{fontSize:20,fontWeight:"900",letterSpacing:3,color:"#e8f1eb"},status:{fontSize:9,color:"#a4edb5",paddingTop:6,maxWidth:"58%",textAlign:"right"},
 meta:{paddingVertical:18},label:{color:"#a4edb5",fontSize:10,letterSpacing:2},heading:{fontSize:28,color:"#e8f1eb",fontWeight:"700",marginTop:8},sub:{fontSize:9,color:"#84948b",marginTop:6,letterSpacing:1},
 panel:{backgroundColor:"#101614",borderWidth:1,borderColor:"#26332d",padding:14,marginBottom:12},panelTitle:{fontSize:10,color:"#a4edb5",letterSpacing:1.5,marginBottom:9},
 contact:{fontSize:10,color:"#e8f1eb",paddingVertical:4},ready:{fontSize:8,color:"#a4edb5"},small:{fontSize:9,color:"#84948b",lineHeight:15,marginTop:7},fieldLabel:{fontSize:9,color:"#a4edb5",marginTop:12,marginBottom:6,letterSpacing:1},
 input:{flex:1,color:"#e8f1eb",borderWidth:1,borderColor:"#26332d",paddingHorizontal:10,paddingVertical:9,fontSize:11,minHeight:40},
 checkButton:{marginTop:9,backgroundColor:"#a4edb5",padding:12,alignItems:"center"},checkText:{fontSize:10,fontWeight:"800",color:"#080b0a",letterSpacing:.5},
 chat:{flex:1,minHeight:180,backgroundColor:"#0c110f",borderWidth:1,borderColor:"#26332d",padding:13},chatHead:{flexDirection:"row",justifyContent:"space-between",borderBottomWidth:1,borderColor:"#26332d",paddingBottom:8},dim:{fontSize:10,color:"#84948b"},
 bubble:{maxWidth:"88%",padding:10,marginVertical:6,borderWidth:1},mineBubble:{borderColor:"#42664c",backgroundColor:"#101614",alignSelf:"flex-end"},theirBubble:{borderColor:"#34443a",backgroundColor:"#111916",alignSelf:"flex-start"},
 who:{fontSize:9,color:"#a4edb5",marginBottom:4},body:{fontSize:12,color:"#e8f1eb",lineHeight:18},compose:{flexDirection:"row",gap:8,borderTopWidth:1,borderColor:"#26332d",paddingTop:10,alignItems:"flex-end"},send:{backgroundColor:"#a4edb5",width:44,minHeight:42,alignItems:"center",justifyContent:"center"},sendText:{fontSize:20,color:"#080b0a"},
 warning:{fontSize:9,color:"#d9b878",lineHeight:15,marginTop:10},error:{fontSize:10,color:"#f0a6a6",lineHeight:15,marginBottom:8}
});
