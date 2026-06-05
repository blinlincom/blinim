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

  @override
  State<BlinlinApp> createState() => _BlinlinAppState();
}

class _BlinlinAppState extends State<BlinlinApp> {
  UserSession? session;
  bool booting = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await AuthStore().load();
    if (mounted) {
      setState(() {
        session = s;
        booting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF6750A4);
    return MaterialApp(
      title: 'Blinlin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFFFFBFE),
        appBarTheme: const AppBarTheme(centerTitle: false),
        cardTheme: CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          height: 72,
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w800
                  : FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      ),
      home: booting
          ? const _Boot()
          : session == null
          ? LoginScreen(onLogin: (s) => setState(() => session = s))
          : HomeScreen(
              session: session!,
              onLogout: () => setState(() => session = null),
            ),
    );
  }
}

class _Boot extends StatelessWidget {
  const _Boot();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
