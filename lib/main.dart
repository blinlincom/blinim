import 'package:flutter/material.dart';
import 'models/user_session.dart';
import 'services/auth_store.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BlinlinApp());
}

class BlinlinApp extends StatefulWidget {
  const BlinlinApp({super.key});
  @override State<BlinlinApp> createState()=>_BlinlinAppState();
}
class _BlinlinAppState extends State<BlinlinApp>{
  UserSession? session; bool booting=true;
  @override void initState(){super.initState(); _load();}
  Future<void> _load() async { final s=await AuthStore().load(); if(mounted)setState(() { session = s; booting = false; }); }
  @override Widget build(BuildContext context){
    return MaterialApp(
      title:'Blinlin', debugShowCheckedModeBanner:false,
      theme: ThemeData(
        useMaterial3:true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF101828), brightness: Brightness.light),
        fontFamily: 'sans',
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white.withOpacity(.92), indicatorColor: const Color(0xFF101828),
          labelTextStyle: WidgetStateProperty.resolveWith((s)=>TextStyle(fontWeight:FontWeight.w800,color:s.contains(WidgetState.selected)?const Color(0xFF101828):Colors.black54)),
          iconTheme: WidgetStateProperty.resolveWith((s)=>IconThemeData(color:s.contains(WidgetState.selected)?Colors.white:Colors.black54)),
        ),
      ),
      home: booting ? const _Boot() : session==null ? LoginScreen(onLogin:(s)=>setState(()=>session=s)) : HomeScreen(session:session!, onLogout:()=>setState(()=>session=null)),
    );
  }
}
class _Boot extends StatelessWidget{const _Boot();@override Widget build(BuildContext context)=>const Scaffold(body:Center(child:CircularProgressIndicator()));}
