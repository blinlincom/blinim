import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/user_session.dart';
import 'services/auth_store.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'widgets/blin_style.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
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
  ThemeMode themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final s = await AuthStore().load();
    final theme = prefs.getString('theme_mode') ?? 'system';
    if (mounted) {
      setState(() {
        session = s;
        themeMode = switch (theme) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        };
        booting = false;
      });
    }
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'theme_mode',
      switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      },
    );
    if (mounted) setState(() => themeMode = mode);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '搭个话',
    debugShowCheckedModeBanner: false,
    themeMode: themeMode,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    home: booting
        ? const _Boot()
        : session == null
        ? LoginScreen(onLogin: (s) => setState(() => session = s))
        : HomeScreen(
            session: session!,
            themeMode: themeMode,
            onThemeModeChanged: _setThemeMode,
            onLogout: () => setState(() => session = null),
          ),
  );

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: BlinStyle.green,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? const Color(0xFF07111F) : BlinStyle.bg,
      fontFamily: 'sans',
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: dark ? Colors.white : BlinStyle.ink,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF111B2B) : Colors.white,
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
        backgroundColor: (dark ? const Color(0xFF0B1424) : Colors.white)
            .withValues(alpha: .96),
        indicatorColor: BlinStyle.green.withValues(alpha: dark ? .22 : .14),
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
                ? (dark ? Colors.white : BlinStyle.ink)
                : BlinStyle.muted,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: dark ? BlinStyle.green : BlinStyle.ink,
          foregroundColor: dark ? const Color(0xFF07111F) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

class _Boot extends StatelessWidget {
  const _Boot();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageBackdrop(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  gradient: BlinStyle.brandGradient,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BlinStyle.softShadow(.16)],
                ),
                child: const Icon(
                  Icons.hub_rounded,
                  color: Colors.white,
                  size: 34,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                '搭个话',
                style: TextStyle(
                  color: BlinStyle.ink,
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.2,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '正在进入年轻社区',
                style: TextStyle(
                  color: BlinStyle.muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 36),
              const _BootSkeletonLine(width: double.infinity),
              const SizedBox(height: 12),
              const _BootSkeletonLine(width: 260),
              const SizedBox(height: 12),
              const _BootSkeletonLine(width: 190),
            ],
          ),
        ),
      ),
    ),
  );
}

class _BootSkeletonLine extends StatelessWidget {
  final double width;
  const _BootSkeletonLine({required this.width});

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: 16,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .72),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Colors.white.withValues(alpha: .9)),
    ),
  );
}
