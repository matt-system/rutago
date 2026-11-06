import React,{useState} from "react";
import {View,Text,TextInput,Pressable,ScrollView,KeyboardAvoidingView,Platform,StyleSheet,ActivityIndicator} from "react-native";
import { ClientBuilder } from "@unomed/react-native-matrix-sdk";

type Msg={id:number;body:string;mine:boolean};
export default function Home(){
 const [items,setItems]=useState<Msg[]>([]);
 const [draft,setDraft]=useState("");
 const [homeserver,setHomeserver]=useState("https://matrix.org");
 const [sdkState,setSdkState]=useState("NOT CHECKED");
 const [checking,setChecking]=useState(false);
 const [serverInfo,setServerInfo]=useState("");
 async function checkNativeSdk(){
  setChecking(true);setSdkState("CHECKING");
  try{
   const client=await new ClientBuilder().homeserverUrl(homeserver.trim()).build();
   const details=await client.homeserverLoginDetails();
   const supportsPassword=details.supportsPasswordLogin();
   const supportsOAuth=details.supportsOauthLogin();
   setServerInfo("Password: "+(supportsPassword?"yes":"no")+" · OAuth: "+(supportsOAuth?"yes":"no"));
   setSdkState("NATIVE SDK READY · ACCOUNT NOT CONNECTED");
  }catch(e){
   setServerInfo(String(e));
   setSdkState("SDK / SERVER CHECK FAILED");
  }finally{setChecking(false);}
 }
 function send(){const body=draft.trim();if(!body)return;setItems(v=>[...v,{id:Date.now(),body,mine:true}]);setDraft("");}
 return <KeyboardAvoidingView style={s.root} behavior={Platform.OS==="ios"?"padding":undefined}>
 <View style={s.header}><Text style={s.logo}>MESH<Text style={{color:"#a4edb5"}}>BIT</Text></Text><Text style={s.status}>● NATIVE SDK BUILD</Text></View>
 <View style={s.meta}><Text style={s.label}>[ PRIVATE MESSAGING ]</Text><Text style={s.heading}>Terminal <Text style={{color:"#a4edb5"}}>/ 03</Text></Text><Text style={s.sub}>MATRIX RUST SDK · E2EE ENGINE</Text></View>
 <View style={s.panel}>
  <Text style={s.panelTitle}>NATIVE SECURITY ENGINE</Text>
  <Text style={s.contact}>● Matrix Rust SDK <Text style={s.ready}>· LINKED IN BUILD</Text></Text>
  <Text style={s.contact}>○ End-to-end encrypted session <Text style={s.pending}>· NOT AUTHENTICATED</Text></Text>
  <Text style={s.contact}>○ Bluetooth mesh transport <Text style={s.pending}>· NOT IMPLEMENTED</Text></Text>
  <Text style={s.small}>El SDK oficial aporta el motor criptográfico Matrix. La sesión cifrada solo se activa al autenticar una cuenta y crear/usar salas cifradas.</Text>
  <Text style={s.fieldLabel}>MATRIX HOMESERVER</Text>
  <TextInput value={homeserver} onChangeText={setHomeserver} autoCapitalize="none" autoCorrect={false} style={s.serverInput} placeholderTextColor="#718078"/>
  <Pressable onPress={checkNativeSdk} disabled={checking} style={s.checkButton}>{checking?<ActivityIndicator color="#080b0a"/>:<Text style={s.checkText}>CHECK NATIVE SDK / SERVER</Text>}</Pressable>
  <Text style={s.state}>{sdkState}</Text>{!!serverInfo&&<Text style={s.small}>{serverInfo}</Text>}
 </View>
 <View style={s.chat}><View style={s.chatHead}><Text style={s.panelTitle}># local.sandbox</Text><Text style={s.dim}>LOCAL ONLY</Text></View>
 <ScrollView style={{flex:1}} contentContainerStyle={{paddingVertical:12}}>{items.map(m=><View key={m.id} style={s.bubble}><Text style={s.who}>local draft</Text><Text style={s.body}>{m.body}</Text></View>)}{items.length===0&&<Text style={s.dim}>Este panel sigue siendo una maqueta local. Todavía no envía mensajes.</Text>}</ScrollView>
 <View style={s.compose}><TextInput value={draft} onChangeText={setDraft} placeholder="local draft only..." placeholderTextColor="#718078" style={s.input} onSubmitEditing={send}/><Pressable onPress={send} style={s.send}><Text style={s.sendText}>↗</Text></Pressable></View></View>
 <Text style={s.warning}>[!] NO ES UN CHAT SEGURO: el motor Matrix está incluido en el build, pero no hay sesión autenticada ni envío cifrado conectado. Bluetooth mesh sigue pendiente. No escribas información privada.</Text>
 </KeyboardAvoidingView>;
}
const s=StyleSheet.create({root:{flex:1,backgroundColor:"#080b0a",padding:18,paddingTop:Platform.OS==="android"?44:62},header:{height:48,borderBottomWidth:1,borderColor:"#26332d",flexDirection:"row",justifyContent:"space-between",alignItems:"flex-start"},logo:{fontSize:20,fontWeight:"900",letterSpacing:3,color:"#e8f1eb"},status:{fontSize:9,color:"#a4edb5",paddingTop:6},meta:{paddingVertical:20},label:{color:"#a4edb5",fontSize:10,letterSpacing:2},heading:{fontSize:30,color:"#e8f1eb",fontWeight:"700",marginTop:8},sub:{fontSize:9,color:"#84948b",marginTop:6,letterSpacing:1},panel:{backgroundColor:"#101614",borderWidth:1,borderColor:"#26332d",padding:14,marginBottom:14},panelTitle:{fontSize:10,color:"#a4edb5",letterSpacing:1.5,marginBottom:10},contact:{fontSize:11,color:"#e8f1eb",paddingVertical:5},ready:{fontSize:9,color:"#a4edb5"},pending:{fontSize:9,color:"#e5c58a"},small:{fontSize:9,color:"#84948b",lineHeight:15,marginTop:7},fieldLabel:{fontSize:9,color:"#a4edb5",marginTop:12,marginBottom:6,letterSpacing:1},serverInput:{color:"#e8f1eb",borderWidth:1,borderColor:"#26332d",padding:9,fontSize:11},checkButton:{marginTop:8,backgroundColor:"#a4edb5",padding:11,alignItems:"center"},checkText:{fontSize:10,fontWeight:"800",color:"#080b0a",letterSpacing:.5},state:{fontSize:9,color:"#e5c58a",marginTop:9},chat:{flex:1,minHeight:150,backgroundColor:"#0c110f",borderWidth:1,borderColor:"#26332d",padding:14},chatHead:{flexDirection:"row",justifyContent:"space-between",borderBottomWidth:1,borderColor:"#26332d",paddingBottom:8},dim:{fontSize:10,color:"#84948b"},bubble:{maxWidth:"88%",padding:10,marginVertical:6,borderWidth:1,borderColor:"#42664c",backgroundColor:"#101614",alignSelf:"flex-end"},who:{fontSize:9,color:"#a4edb5",marginBottom:4},body:{fontSize:12,color:"#e8f1eb",lineHeight:18},compose:{flexDirection:"row",gap:8,borderTopWidth:1,borderColor:"#26332d",paddingTop:12},input:{flex:1,color:"#e8f1eb",borderWidth:1,borderColor:"#26332d",paddingHorizontal:12,paddingVertical:10,fontSize:12},send:{backgroundColor:"#a4edb5",width:44,alignItems:"center",justifyContent:"center"},sendText:{fontSize:20,color:"#080b0a"},warning:{fontSize:9,color:"#e5c58a",lineHeight:15,marginTop:12}});
