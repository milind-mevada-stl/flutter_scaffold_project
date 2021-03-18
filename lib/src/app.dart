import 'dart:async';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_base_project/config.dart';
import 'package:flutter_base_project/src/analytics/analytics.dart';
import 'package:flutter_base_project/src/app_update/app_update.dart';
import 'package:flutter_base_project/src/error_logger/error_logger.dart';
import 'package:flutter_base_project/src/remote_config/remote_config_repository.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http_interceptor/http_interceptor.dart';
import 'package:performance_interceptor/dio_performance_interceptor.dart';
import 'package:performance_interceptor/performance_interceptor.dart';

Future<void> initApp() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();

  if (kDebugMode) {
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(false);
  } else {
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
  }

  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterError;

  final shouldEnablePerformanceMonitoring =
      Config.appFlavor is Production && Config.appMode == AppMode.release;
  await FirebasePerformance.instance
      .setPerformanceCollectionEnabled(shouldEnablePerformanceMonitoring);

  try {
    await RemoteConfigRepository().initConfig();
    await RemoteConfigRepository().syncConfig();
  } catch (e) {
    debugPrint(e.toString());
  }

  await runZonedGuarded<Future<void>>(
    () async {
      runApp(
        EasyLocalization(
          path: 'lib/assets/strings',
          supportedLocales: const <Locale>[
            Locale('en', 'US'),
          ],
          useOnlyLangCode: false,
          child: App(),
        ),
      );
    },
    (error, StackTrace stackTrace) async {
      if (Config.appMode == AppMode.release) {
        await FirebaseCrashlytics.instance.recordError(error, stackTrace);
        await getErrorLogger().logEvent(
          exception: error,
          stackTrace: stackTrace,
        );
      }
    },
  );
}

class App extends StatefulWidget {
  @override
  _AppState createState() => _AppState();
}

class _AppState extends State<App> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      //TODO Change App Title
      title: 'Flutter Demo',
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        EasyLocalization.of(context).delegate,
      ],
      locale: EasyLocalization.of(context).locale,
      supportedLocales: EasyLocalization.of(context).supportedLocales,
      navigatorObservers: [
        navigationObserverAnalytics(),
      ],
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  'welcome_message'.tr(),
                ),
                Text(
                  RemoteConfigRepository().getString('welcome_msg'),
                ),
                RaisedButton(
                  onPressed: () async {
                    const url = 'https://jsonplaceholder.typicode.com/photos';
                    final client = HttpClientWithInterceptor.build(
                      interceptors: [
                        HttpPerformanceInterceptor(),
                      ],
                    );
                    await client.get(url);
                    debugPrint("HTTP RESPONSE");

                    final dio = Dio();
                    dio.interceptors.add(DioPerformanceInterceptor());
                    await dio.get(url);
                    debugPrint("DIO RESPONSE");
                  },
                  child: const Text('Action'),
                ),
                AppUpdateWidget(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
