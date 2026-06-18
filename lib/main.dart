import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/user_session.dart';
import 'services/api_service.dart';
import 'services/auth_store.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'widgets/blin_style.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
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
  StreamSubscription? authExpiredSub;

  @override
  void initState() {
    super.initState();
    authExpiredSub = AuthSessionEvents.expired.listen((_) {
      _handleAuthExpired();
    });
    _load();
  }

  Future<void> _handleAuthExpired() async {
    await AuthStore().clear();
    if (mounted && session != null) setState(() => session = null);
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    var s = await AuthStore().load();
    final theme = prefs.getString('theme_mode') ?? 'system';
    if (s != null) {
      try {
        final api = const ApiService();
        await api.getMessageList(s.token).timeout(const Duration(seconds: 5));
      } on AuthExpiredException {
        await AuthStore().clear();
        s = null;
      } catch (_) {
        // 网络不可用时保留本地登录态，等后续接口返回 401 再统一退出。
      }
    }
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
    await prefs.setString('theme_mode', switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
    if (mounted) setState(() => themeMode = mode);
  }

  Future<void> _handleLogin(UserSession s) async {
    if (!mounted) return;
    setState(() => session = s);
  }

  Future<void> _handleSessionChanged(UserSession s) async {
    await AuthStore().save(s);
    if (!mounted) return;
    setState(() => session = s);
  }

  @override
  void dispose() {
    authExpiredSub?.cancel();
    super.dispose();
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
        ? LoginScreen(onLogin: _handleLogin)
        : HomeScreen(
            session: session!,
            themeMode: themeMode,
            onThemeModeChanged: _setThemeMode,
            onSessionChanged: (s) => unawaited(_handleSessionChanged(s)),
            onLogout: () => setState(() => session = null),
          ),
  );

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: BlinStyle.primary,
      brightness: brightness,
      primary: BlinStyle.primary,
      secondary: BlinStyle.success,
      tertiary: BlinStyle.warning,
      surface: dark ? BlinStyle.darkSurface : BlinStyle.bgElevated,
      error: BlinStyle.danger,
    );
    final textColor = dark ? const Color(0xFFF8FAFC) : BlinStyle.ink;
    final mutedColor = dark ? const Color(0xFFCBD5E1) : BlinStyle.muted;
    final subtleColor = dark ? const Color(0xFF94A3B8) : BlinStyle.subtle;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? BlinStyle.darkBg : BlinStyle.bg,
      fontFamily: 'sans',
      visualDensity: VisualDensity.standard,
      splashFactory: InkRipple.splashFactory,
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          color: textColor,
          fontSize: 20,
          height: 1.25,
          fontWeight: FontWeight.w600,
        ),
        headlineMedium: TextStyle(
          color: textColor,
          fontSize: 20,
          height: 1.25,
          fontWeight: FontWeight.w600,
        ),
        titleLarge: TextStyle(
          color: textColor,
          fontSize: 20,
          height: 1.25,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: TextStyle(
          color: textColor,
          fontSize: 16,
          height: 1.35,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: TextStyle(
          color: mutedColor,
          fontSize: 14,
          height: 1.45,
          fontWeight: FontWeight.w400,
        ),
        bodyMedium: TextStyle(
          color: mutedColor,
          fontSize: 14,
          height: 1.45,
          fontWeight: FontWeight.w400,
        ),
        bodySmall: TextStyle(
          color: subtleColor,
          fontSize: 12,
          height: 1.35,
          fontWeight: FontWeight.w400,
        ),
        labelLarge: TextStyle(
          color: textColor,
          fontSize: 14,
          height: 1.25,
          fontWeight: FontWeight.w500,
        ),
        labelMedium: TextStyle(
          color: mutedColor,
          fontSize: 12,
          height: 1.25,
          fontWeight: FontWeight.w400,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? BlinStyle.darkBg : BlinStyle.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: textColor,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textColor,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF1E293B) : BlinStyle.softFill,
        labelStyle: TextStyle(color: mutedColor, fontWeight: FontWeight.w400),
        hintStyle: TextStyle(color: subtleColor, fontWeight: FontWeight.w400),
        prefixIconColor: mutedColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BlinStyle.buttonRadius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BlinStyle.buttonRadius),
          borderSide: BorderSide(
            color: dark ? BlinStyle.darkLine : BlinStyle.line,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BlinStyle.buttonRadius),
          borderSide: const BorderSide(color: BlinStyle.primary, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BlinStyle.buttonRadius),
          borderSide: const BorderSide(color: BlinStyle.danger),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 66,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: dark ? BlinStyle.darkSurface : BlinStyle.bgElevated,
        indicatorColor: BlinStyle.primary.withValues(alpha: dark ? .22 : .11),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontSize: 12,
            height: 1.05,
            color: s.contains(WidgetState.selected) ? textColor : mutedColor,
            fontWeight: s.contains(WidgetState.selected)
                ? FontWeight.w500
                : FontWeight.w400,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            size: BlinStyle.iconSize,
            color: s.contains(WidgetState.selected)
                ? BlinStyle.primary
                : subtleColor,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: dark ? BlinStyle.darkSurface : BlinStyle.bgElevated,
        indicatorColor: BlinStyle.primary.withValues(alpha: dark ? .22 : .12),
        selectedIconTheme: const IconThemeData(color: BlinStyle.primary),
        unselectedIconTheme: IconThemeData(color: subtleColor),
        selectedLabelTextStyle: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: mutedColor,
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          backgroundColor: BlinStyle.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: mutedColor.withValues(alpha: .16),
          disabledForegroundColor: mutedColor.withValues(alpha: .72),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BlinStyle.buttonRadius),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(48, 48),
          elevation: 0,
          shadowColor: Colors.transparent,
          backgroundColor: dark ? const Color(0xFF263449) : BlinStyle.softFill,
          foregroundColor: textColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BlinStyle.buttonRadius),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 46),
          foregroundColor: textColor,
          side: BorderSide(color: dark ? BlinStyle.darkLine : BlinStyle.line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BlinStyle.buttonRadius),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: BlinStyle.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BlinStyle.buttonRadius),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: textColor,
          minimumSize: const Size(40, 40),
          padding: EdgeInsets.zero,
          iconSize: BlinStyle.iconSize,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BlinStyle.buttonRadius),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: dark ? BlinStyle.darkSurface : BlinStyle.bgElevated,
        selectedColor: BlinStyle.primary.withValues(alpha: dark ? .24 : .12),
        side: BorderSide(color: dark ? BlinStyle.darkLine : BlinStyle.line),
        labelStyle: TextStyle(color: textColor, fontWeight: FontWeight.w400),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BlinStyle.buttonRadius),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? BlinStyle.bgElevated : BlinStyle.ink,
        contentTextStyle: TextStyle(
          color: dark ? BlinStyle.ink : Colors.white,
          fontWeight: FontWeight.w400,
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BlinStyle.buttonRadius),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: dark ? BlinStyle.darkSurface : BlinStyle.bgElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
    return Scaffold(
      body: PageBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              BlinStyle.pagePadding,
              64,
              BlinStyle.pagePadding,
              BlinStyle.pagePadding,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SoftCard(
                  padding: const EdgeInsets.all(BlinStyle.cardPadding),
                  child: InfoLine(
                    avatar: const GradientIcon(
                      icon: Icons.chat_bubble_outline_rounded,
                    ),
                    title: '搭个话',
                    subtitle: '正在连接即时通讯',
                  ),
                ),
                const SizedBox(height: BlinStyle.moduleGap),
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
    final base = dark ? const Color(0xFF1E293B) : BlinStyle.softFill;
    return Container(
      width: width,
      height: 16,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}
