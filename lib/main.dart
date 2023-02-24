import 'dart:async';
import 'dart:isolate';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;
import 'package:mawaqit/i18n/l10n.dart';
import 'package:mawaqit/i18n/AppLanguage.dart';
import 'package:mawaqit/src/enum/connectivity_status.dart';
import 'package:mawaqit/src/helpers/AnalyticsWrapper.dart';
import 'package:mawaqit/src/helpers/AppRouter.dart';
import 'package:mawaqit/src/helpers/ConnectivityService.dart';
import 'package:mawaqit/src/helpers/HiveLocalDatabase.dart';
import 'package:mawaqit/src/pages/SplashScreen.dart';
import 'package:mawaqit/src/services/audio_manager.dart';
import 'package:mawaqit/src/services/developer_manager.dart';
import 'package:mawaqit/src/services/mosque_manager.dart';
import 'package:mawaqit/src/services/settings_manager.dart';
import 'package:mawaqit/src/services/theme_manager.dart';
import 'package:provider/provider.dart';
import 'package:sizer/sizer.dart';

Future<void> main() async {
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // Sizer

    await Firebase.initializeApp();

    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterError;
    Isolate.current.addErrorListener(RawReceivePort((pair) async {
      final List<dynamic> errorAndStacktrace = pair;
      await FirebaseCrashlytics.instance.recordError(
        errorAndStacktrace.first,
        errorAndStacktrace.last,
      );
    }).sendPort);
    return runApp(ProviderScope(child: MyApp()));
  }, (error, stack) => FirebaseCrashlytics.instance.recordError(error, stack));
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ThemeNotifier()),
        ChangeNotifierProvider(create: (context) => AppLanguage()),
        ChangeNotifierProvider(create: (context) => MosqueManager()),
        ChangeNotifierProvider(create: (context) => SettingsManager()),
        ChangeNotifierProvider(create: (context) => AudioManager()),
        ChangeNotifierProvider(create: (context) => DeveloperManager()),
        ChangeNotifierProvider(create: (context) => HiveManager()),
      ],
      child: Consumer<AppLanguage>(builder: (context, model, child) {
        return Sizer(builder: (context, orientation, size) {
          return StreamProvider(
            initialData: ConnectivityStatus.Offline,
            create: (context) => ConnectivityService()
                .connectionStatusController
                .stream
                .map((event) {
              if (event == ConnectivityStatus.Wifi ||
                  event == ConnectivityStatus.Cellular) {
                //todo check actual internet
              }

              return event;
            }),
            child: Consumer<ThemeNotifier>(
              builder: (context, theme, _) => Shortcuts(
                shortcuts: {
                  SingleActivator(LogicalKeyboardKey.select): ActivateIntent()
                },
                child: MaterialApp(
                  themeMode: theme.mode,
                  localeResolutionCallback: (locale, supportedLocales) {
                    if (locale?.languageCode.toLowerCase() == 'ba')
                      return Locale('en');

                    return locale;
                  },
                  theme: theme.lightTheme,
                  darkTheme: theme.darkTheme,
                  locale: model.appLocal,
                  navigatorKey: AppRouter.navigationKey,
                  navigatorObservers: [AnalyticsWrapper.observer()],
                  localizationsDelegates: [
                    S.delegate,
                    GlobalCupertinoLocalizations.delegate,
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                  ],
                  supportedLocales: S.supportedLocales,
                  debugShowCheckedModeBanner: false,
                  home: Splash(),
                ),
              ),
            ),
          );
        });
      }),
    );
  }
}
