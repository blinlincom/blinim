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
      seedColor: BlinStyle.cyan,
      brightness: brightness,
      primary: BlinStyle.cyan,
      secondary: BlinStyle.purple,
      surface: dark ? BlinStyle.darkSurface : BlinStyle.bgElevated,
      error: BlinStyle.danger,
    );
    final textColor = dark ? const Color(0xFFF4F8FF) : BlinStyle.ink;
    final mutedColor = dark ? const Color(0xFF9BA9BE) : BlinStyle.muted;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? BlinStyle.darkBg : BlinStyle.bg,
      fontFamily: 'sans',
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          color: textColor,
          fontSize: 34,
          height: 1.08,
          fontWeight: FontWeight.w900,
          letterSpacing: -.9,
        ),
        headlineMedium: TextStyle(
          color: textColor,
          fontSize: 24,
          height: 1.18,
          fontWeight: FontWeight.w900,
          letterSpacing: -.35,
        ),
        titleLarge: TextStyle(
          color: textColor,
          fontSize: 19,
          height: 1.25,
          fontWeight: FontWeight.w900,
        ),
        titleMedium: TextStyle(
          color: textColor,
          fontSize: 16,
          height: 1.3,
          fontWeight: FontWeight.w800,
        ),
        bodyLarge: TextStyle(
          color: textColor,
          fontSize: 16,
          height: 1.48,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: TextStyle(
          color: mutedColor,
          fontSize: 14,
          height: 1.45,
          fontWeight: FontWeight.w600,
        ),
        labelLarge: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w900,
          letterSpacing: .05,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: textColor,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textColor,
          fontSize: 20,
          fontWeight: FontWeight.w900,
          letterSpacing: -.2,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF111B2D) : const Color(0xFFF8FBFF),
        labelStyle: TextStyle(color: mutedColor, fontWeight: FontWeight.w700),
        hintStyle: TextStyle(color: mutedColor, fontWeight: FontWeight.w600),
        prefixIconColor: mutedColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: dark ? BlinStyle.darkLine : BlinStyle.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: BlinStyle.green, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: BlinStyle.danger),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: (dark ? const Color(0xFF0B1424) : Colors.white)
            .withValues(alpha: .98),
        indicatorColor: BlinStyle.cyan.withValues(alpha: dark ? .26 : .18),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontSize: 12,
            height: 1.05,
            color: s.contains(WidgetState.selected) ? textColor : mutedColor,
            fontWeight: s.contains(WidgetState.selected)
                ? FontWeight.w900
                : FontWeight.w700,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            size: 24,
            color: s.contains(WidgetState.selected) ? textColor : mutedColor,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          backgroundColor: dark ? BlinStyle.green : BlinStyle.ink,
          foregroundColor: dark ? BlinStyle.darkBg : Colors.white,
          disabledBackgroundColor: mutedColor.withValues(alpha: .16),
          disabledForegroundColor: mutedColor.withValues(alpha: .72),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 46),
          foregroundColor: textColor,
          side: BorderSide(color: dark ? BlinStyle.darkLine : BlinStyle.line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: dark ? const Color(0xFF101C2E) : Colors.white,
        selectedColor: BlinStyle.green.withValues(alpha: dark ? .20 : .13),
        side: BorderSide(color: dark ? BlinStyle.darkLine : BlinStyle.line),
        labelStyle: TextStyle(color: textColor, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? const Color(0xFFEAF3FF) : const Color(0xFF152033),
        contentTextStyle: TextStyle(
          color: dark ? BlinStyle.darkBg : Colors.white,
          fontWeight: FontWeight.w800,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: dark ? BlinStyle.darkSurface : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      dividerTheme: DividerThemeData(
        color: dark ? BlinStyle.darkLine : BlinStyle.line,
        thickness: 1,
        space: 1,
      ),
    );
  }
}

class _Boot extends StatelessWidget {
  const _Boot();
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = dark ? const Color(0xFFF4F8FF) : BlinStyle.ink;
    final subtitleColor = dark ? const Color(0xFF9BA9BE) : BlinStyle.muted;
    return Scaffold(
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
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BlinStyle.softShadow(.14)],
                  ),
                  child: const Icon(
                    Icons.hub_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '搭个话',
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.0,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '正在进入年轻社区',
                  style: TextStyle(
                    color: subtitleColor,
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
}

class _BootSkeletonLine extends StatelessWidget {
  final double width;
  const _BootSkeletonLine({required this.width});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? const Color(0xFF121E2F) : Colors.white;
    return Container(
      width: width,
      height: 16,
      decoration: BoxDecoration(
        color: base.withValues(alpha: dark ? .26 : .72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: base.withValues(alpha: dark ? .32 : .9),
        ),
      ),
    );
  }
}
