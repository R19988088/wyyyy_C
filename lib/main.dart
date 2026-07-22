import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player.dart';
import 'player_page.dart';
import 'rust_player_repository.dart';
import 'services/audio_handler.dart';
import 'services/cover_feedback.dart';
import 'settings_page.dart';
import 'src/rust/api.dart' as rust_api;
import 'src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await LiquidGlassWidgets.initialize();
  await RustLib.init();
  final supportDirectory = await getApplicationSupportDirectory();
  await rust_api.initialize(dataDirectory: supportDirectory.path);
  await rust_api.restoreSession();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final handler = await initializeAudioService();
  final repository = await RustPlayerRepository.create(handler);
  final preferences = await SharedPreferences.getInstance();
  final coverFeedback = CoverFeedbackSettings(
    hapticStrength: (preferences.getDouble('coverHapticStrength') ?? .7)
        .clamp(0.0, 1.0)
        .toDouble(),
    soundStrength: (preferences.getDouble('coverSoundStrength') ?? .7)
        .clamp(0.0, 1.0)
        .toDouble(),
  );
  runApp(
    LiquidGlassWidgets.wrap(
      respectSystemAccessibility: true,
      theme: GlassThemeData.simple(
        blur: 18,
        thickness: 28,
        quality: GlassQuality.premium,
      ),
      child: PlayerApp(
        repository: repository,
        initialDark: preferences.getBool('darkMode') ?? false,
        saveDarkMode: (value) => preferences.setBool('darkMode', value),
        initialCoverFeedback: coverFeedback,
        saveCoverFeedback: (value) async {
          await Future.wait([
            preferences.setDouble('coverHapticStrength', value.hapticStrength),
            preferences.setDouble('coverSoundStrength', value.soundStrength),
          ]);
        },
        initialListCoverSwitching:
            preferences.getBool('listCoverSwitching') ?? false,
        saveListCoverSwitching: (value) async {
          await preferences.setBool('listCoverSwitching', value);
        },
      ),
    ),
  );
}

class PlayerApp extends StatefulWidget {
  const PlayerApp({
    super.key,
    required this.repository,
    this.initialDark = false,
    this.saveDarkMode,
    this.initialCoverFeedback = CoverFeedbackSettings.defaults,
    this.saveCoverFeedback,
    this.initialListCoverSwitching = false,
    this.saveListCoverSwitching,
  });

  final PlayerRepository repository;
  final bool initialDark;
  final Future<bool> Function(bool value)? saveDarkMode;
  final CoverFeedbackSettings initialCoverFeedback;
  final Future<void> Function(CoverFeedbackSettings value)? saveCoverFeedback;
  final bool initialListCoverSwitching;
  final Future<void> Function(bool value)? saveListCoverSwitching;

  @override
  State<PlayerApp> createState() => _PlayerAppState();
}

class _PlayerAppState extends State<PlayerApp> {
  late ThemeMode _themeMode = widget.initialDark
      ? ThemeMode.dark
      : ThemeMode.light;
  late CoverFeedbackSettings _coverFeedback = widget.initialCoverFeedback;
  late bool _listCoverSwitching = widget.initialListCoverSwitching;

  @override
  void initState() {
    super.initState();
    CoverFeedback.configure(_coverFeedback);
  }

  void _setCoverFeedback(CoverFeedbackSettings value) {
    setState(() => _coverFeedback = value);
    CoverFeedback.configure(value);
    final save = widget.saveCoverFeedback;
    if (save != null) unawaited(save(value));
  }

  @override
  Widget build(BuildContext context) {
    final dark = _themeMode == ThemeMode.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.black.withValues(alpha: .3),
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: '网易云音乐',
        themeMode: _themeMode,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: Builder(
          builder: (context) => PlayerPage(
            repository: widget.repository,
            listCoverSwitching: _listCoverSwitching,
            openSettings: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsPage(
                    repository: widget.repository,
                    dark: dark,
                    coverFeedback: _coverFeedback,
                    listCoverSwitching: _listCoverSwitching,
                    onThemeChanged: (value) {
                      setState(
                        () => _themeMode = value
                            ? ThemeMode.dark
                            : ThemeMode.light,
                      );
                      widget.saveDarkMode?.call(value);
                    },
                    onCoverFeedbackChanged: _setCoverFeedback,
                    onListCoverSwitchingChanged: (value) {
                      setState(() => _listCoverSwitching = value);
                      widget.saveListCoverSwitching?.call(value);
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xffe5473e),
      brightness: brightness,
      surface: dark ? const Color(0xff141414) : const Color(0xfff6f5f2),
    );
    final outlineShadows = _outlineShadows(
      (dark ? Colors.black : Colors.white).withValues(alpha: .6),
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      dividerColor: scheme.onSurface.withValues(alpha: .1),
    );
    final outlineStyle = TextStyle(shadows: outlineShadows);
    return base.copyWith(
      iconTheme: base.iconTheme.copyWith(shadows: outlineShadows),
      primaryIconTheme: base.primaryIconTheme.copyWith(shadows: outlineShadows),
      textTheme: base.textTheme.merge(
        TextTheme(
          displayLarge: outlineStyle,
          displayMedium: outlineStyle,
          displaySmall: outlineStyle,
          headlineLarge: outlineStyle,
          headlineMedium: outlineStyle,
          headlineSmall: outlineStyle,
          titleLarge: outlineStyle,
          titleMedium: outlineStyle,
          titleSmall: outlineStyle,
          bodyLarge: outlineStyle,
          bodyMedium: outlineStyle,
          bodySmall: outlineStyle,
          labelLarge: outlineStyle,
          labelMedium: outlineStyle,
          labelSmall: outlineStyle,
        ),
      ),
    );
  }
}

List<Shadow> _outlineShadows(Color color) => [
  for (final offset in const [
    Offset(-.5, -.5),
    Offset(0, -.5),
    Offset(.5, -.5),
    Offset(-.5, 0),
    Offset(.5, 0),
    Offset(-.5, .5),
    Offset(0, .5),
    Offset(.5, .5),
  ])
    Shadow(color: color, offset: offset),
];
