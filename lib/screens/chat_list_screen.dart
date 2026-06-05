import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/user_session.dart';
import '../models/im_models.dart';
import '../services/api_service.dart';
import '../services/im_service.dart';
import 'chat_screen.dart';

class ChatListScreen extends StatefulWidget {
  final UserSession session; final ImService im;
  const ChatListScreen({super.key, required this.session, required this.im});
  @override State<ChatListScreen> createState()=>_ChatListScreenState();
}
class _ChatListScreenState extends State<ChatListScreen>{
  final api=const ApiService(); List<ConversationItem> items=[]; bool loading=true; StreamSubscription? sub;
  @override void initState(){super.initState(); load(); sub=widget.im.messages.listen((_)=>load());}
  Future<void> load() async { try{final r=await api.getMessageList(widget.session.token); if(mounted)setState(()=>items=r);}catch(_){ } finally{ if(mounted)setState(()=>loading=false); } }
  @override void dispose(){sub?.cancel(); super.dispose();}
  @override Widget build(BuildContext context)=>RefreshIndicator(onRefresh:load, child:CustomScrollView(slivers:[
    SliverToBoxAdapter(child:Padding(padding:const EdgeInsets.fromLTRB(20,18,20,12), child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('即时消息',style:TextStyle(fontSize:32,fontWeight:FontWeight.w900,letterSpacing:-1.1)),Text('历史消息走 PHP，实时接收走 WuKongIM SDK',style:TextStyle(color:Colors.black.withOpacity(.5),fontWeight:FontWeight.w600))]))),
    if(loading) const SliverFillRemaining(child:Center(child:CircularProgressIndicator()))
    else if(items.isEmpty) SliverFillRemaining(child:_Empty(session:widget.session))
    else SliverList(delegate:SliverChildBuilderDelegate((c,i){ final it=items[i]; return _ConversationTile(item:it,onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>ChatScreen(session:widget.session, im:widget.im, peerId:it.userId, peerName:it.nickname, peerAvatar:it.avatar))));},childCount:items.length))
  ]));
}
class _ConversationTile extends StatelessWidget{final ConversationItem item; final VoidCallback onTap; const _ConversationTile({required this.item,required this.onTap}); @override Widget build(BuildContext context)=>Container(margin:const EdgeInsets.symmetric(horizontal:18,vertical:7),decoration:BoxDecoration(color:Colors.white.withOpacity(.78),borderRadius:BorderRadius.circular(26),boxShadow:[BoxShadow(color:Colors.black.withOpacity(.05),blurRadius:24,offset:const Offset(0,12))]),child:ListTile(onTap:onTap,contentPadding:const EdgeInsets.symmetric(horizontal:14,vertical:9),leading:CircleAvatar(radius:26,backgroundImage:item.avatar.isNotEmpty?CachedNetworkImageProvider(item.avatar):null,child:item.avatar.isEmpty?Text(item.nickname.characters.first):null),title:Text(item.nickname,style:const TextStyle(fontWeight:FontWeight.w900)),subtitle:Text(item.preview,maxLines:1,overflow:TextOverflow.ellipsis),trailing:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Text(item.msgTime.length>10?item.msgTime.substring(5,16):item.msgTime,style:TextStyle(fontSize:11,color:Colors.black.withOpacity(.42))),if(item.unread>0)Container(margin:const EdgeInsets.only(top:6),padding:const EdgeInsets.all(6),decoration:const BoxDecoration(shape:BoxShape.circle,color:Color(0xFFFF5A5F)),child:Text('${item.unread}',style:const TextStyle(color:Colors.white,fontSize:10,fontWeight:FontWeight.w800))) ])));}
class _Empty extends StatelessWidget{final UserSession session; const _Empty({required this.session}); @override Widget build(BuildContext context)=>Center(child:Padding(padding:const EdgeInsets.all(28),child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.mark_chat_unread_rounded,size:64),const SizedBox(height:12),const Text('暂无会话',style:TextStyle(fontSize:22,fontWeight:FontWeight.w900)),const SizedBox(height:8),Text('可用测试账号：abcd 与 abcc 互发，当前用户 ID：${session.id}',textAlign:TextAlign.center)])));}
