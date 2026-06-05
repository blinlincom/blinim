import 'package:flutter/material.dart';
import 'models/user_session.dart';
import 'services/auth_store.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'widgets/blin_style.dart';

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
  Widget build(BuildContext context) => MaterialApp(
    title: 'Blinlin',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: BlinStyle.green,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: BlinStyle.bg,
      fontFamily: 'sans',
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: BlinStyle.ink,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 70,
        backgroundColor: Colors.white.withValues(alpha: .96),
        indicatorColor: BlinStyle.green.withValues(alpha: .14),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected)
                ? FontWeight.w900
                : FontWeight.w700,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected)
                ? BlinStyle.ink
                : BlinStyle.muted,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: BlinStyle.ink,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
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

class _Boot extends StatelessWidget {
  const _Boot();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
