import 'dart:async';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/root_screen.dart';
import 'screens/startup_screen.dart';
import 'state/app_store.dart';
import 'app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final store = AppStore();
  runApp(
    CowlogApp(
      store: store,
      refreshUi: const bool.fromEnvironment('COWLOG_UI_REFRESH'),
    ),
  );
  unawaited(store.initialize());
}

class CowlogApp extends StatelessWidget {
  const CowlogApp({
    super.key,
    required this.store,
    this.showStartup = false,
    this.refreshUi = false,
  });
  final AppStore store;
  final bool showStartup;
  final bool refreshUi;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Cowlog',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: AppColors.ink,
        onPrimary: AppColors.onInk,
        secondary: AppColors.accent,
        onSecondary: Colors.white,
        surface: AppColors.surface,
        onSurface: AppColors.ink,
        outline: AppColors.line,
        surfaceTint: Colors.transparent,
      ),
      scaffoldBackgroundColor: refreshUi
          ? AppColors.refreshCanvas
          : AppColors.background,
      splashFactory: NoSplash.splashFactory,
      highlightColor: const Color(0x0f000000),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: refreshUi
            ? AppColors.refreshCanvas
            : AppColors.background,
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
          fontFeatures: tabularFigures,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: refreshUi ? 0 : 3,
        shadowColor: const Color(0x14000000),
        color: AppColors.surface,
        margin: const EdgeInsets.symmetric(vertical: 5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(refreshUi ? 22 : 28),
          side: refreshUi
              ? const BorderSide(color: AppColors.refreshDivider)
              : BorderSide.none,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: refreshUi ? AppColors.surface : AppColors.surfaceHigh,
        hintStyle: const TextStyle(color: AppColors.muted),
        prefixIconColor: AppColors.muted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: refreshUi
              ? const BorderSide(color: AppColors.refreshDivider)
              : BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.muted, width: 1),
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.accent,
        inactiveTrackColor: AppColors.surfaceHigh,
        thumbColor: Colors.white,
        overlayColor: Color(0x1ff26a55),
        trackHeight: 4,
        activeTickMarkColor: Colors.transparent,
        inactiveTickMarkColor: Colors.transparent,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accent,
        linearTrackColor: AppColors.surfaceHigh,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(99),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      dividerColor: AppColors.line,
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: refreshUi
            ? AppColors.refreshCanvas
            : AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: refreshUi
            ? const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              )
            : null,
      ),
      datePickerTheme: refreshUi
          ? const DatePickerThemeData(
              backgroundColor: AppColors.surface,
              headerBackgroundColor: AppColors.refreshCanvas,
              todayBorder: BorderSide(color: AppColors.accent),
            )
          : null,
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.ink,
        contentTextStyle: TextStyle(color: AppColors.onInk),
      ),
      // Apple の文字サイズの規則（Human Interface Guidelines の Dynamic Type 既定値）。
      // iOS では Flutter が San Francisco（日本語はヒラギノ）を使う。
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          letterSpacing: .4,
        ), // Large Title
        headlineMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: .38,
        ), // Title 1
        headlineSmall: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -.26,
        ), // Title 2
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -.45,
        ), // Title 3
        titleMedium: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -.43,
        ), // Headline
        bodyLarge: TextStyle(fontSize: 17, letterSpacing: -.43), // Body
        bodyMedium: TextStyle(fontSize: 15, letterSpacing: -.23), // Subheadline
        bodySmall: TextStyle(
          color: AppColors.muted,
          fontSize: 13,
          letterSpacing: -.08,
        ), // Footnote
        labelLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -.31,
        ), // Callout
        labelMedium: TextStyle(fontSize: 12), // Caption 1
        labelSmall: TextStyle(fontSize: 11, letterSpacing: .06), // Caption 2
      ),
    ),
    builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: CowlogUi(refreshed: refreshUi, child: child!),
    ),
    home: showStartup
        ? StartupScreen(child: RootScreen(store: store))
        : RootScreen(store: store),
  );
}
