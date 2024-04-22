import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:mawaqit/main.dart';
import 'package:mawaqit/src/helpers/Api.dart';
import 'package:mawaqit/src/helpers/PerformanceHelper.dart';
import 'package:mawaqit/src/helpers/SharedPref.dart';
import 'package:mawaqit/src/mawaqit_image/mawaqit_cache.dart';
import 'package:mawaqit/src/models/mosque.dart';
import 'package:mawaqit/src/models/mosqueConfig.dart';
import 'package:mawaqit/src/models/times.dart';
import 'package:mawaqit/src/pages/home/widgets/footer.dart';
import 'package:mawaqit/src/services/audio_manager.dart';
import 'package:mawaqit/src/services/mixins/mosque_helpers_mixins.dart';
import 'package:mawaqit/src/services/mixins/weather_mixin.dart';

import '../helpers/AppDate.dart';
import 'mixins/audio_mixin.dart';
import 'mixins/connectivity_mixin.dart';

final mawaqitApi = "https://mawaqit.net/api/2.0";

const kAfterAdhanHadithDuration = Duration(minutes: 1);
const kAdhanBeforeFajrDuration = Duration(minutes: 10);

const kAzkarDuration = const Duration(seconds: 140);

class MosqueManager extends ChangeNotifier
    with WeatherMixin, AudioMixin, MosqueHelpersMixin, NetworkConnectivity {
  final sharedPref = SharedPref();

  // String? mosqueId;
  String? mosqueUUID;

  bool _flashEnabled = false;
  bool get flashEnabled => _flashEnabled;

  void _updateFlashEnabled() {
    if (mosque != null) {
      final startDate = DateTime.tryParse(mosque!.flash?.startDate ?? 'x');
      final endDate = DateTime.tryParse(mosque!.flash?.endDate ?? 'x');
      final currentDate = AppDateTime.now();

      DateTime? endOfDay;
      if (endDate != null) {
        endOfDay =
            DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
      }

      if (startDate == null && endDate == null) {
        _flashEnabled = true;
      } else if (startDate != null && endDate == null) {
        _flashEnabled = currentDate.isAfter(startDate) ||
            currentDate.isAtSameMomentAs(startDate);
      } else if (startDate == null && endDate != null) {
        _flashEnabled = currentDate.isBefore(endOfDay!) ||
            currentDate.isAtSameMomentAs(endOfDay);
      } else if (startDate != null && endDate != null) {
        _flashEnabled =
            currentDate.isAfter(startDate) && currentDate.isBefore(endOfDay!) ||
                currentDate.isAtSameMomentAs(startDate) ||
                currentDate.isAtSameMomentAs(endOfDay!);
      }
      notifyListeners();
    }
  }

  bool get loaded => mosque != null && times != null && mosqueConfig != null;

  Mosque? mosque;
  Times? times;
  MosqueConfig? mosqueConfig;

  StreamSubscription? _mosqueSubscription;
  StreamSubscription? _timesSubscription;
  StreamSubscription? _configSubscription;

  /// get current home url
  String buildUrl(String languageCode) {
    // if (mosqueId != null) return 'https://mawaqit.net/$languageCode/id/$mosqueId?view=desktop';
    // if (mosqueSlug != null) return 'https://mawaqit.net/$languageCode/$mosqueSlug?view=desktop';
    return 'https://mawaqit.net/$languageCode/id/${mosque?.id}?view=desktop';
  }

  Future<void> init() async {
    await Api.init();
    await loadFromLocale();
    listenToConnectivity();
    notifyListeners();
  }

  /// update mosque id in the app and shared preference
  Future<void> setMosqueUUid(String uuid) async {
    try {
      await fetchMosque(uuid);

      _saveToLocale();

      // print("mosque url${mosque?.url}");
    } catch (e, stack) {
      debugPrintStack(stackTrace: stack);
    }
  }

  Future<void> _saveToLocale() async {
    logger.d("Saving into local");
    // await sharedPref.save('mosqueId', mosqueId);
    await sharedPref.save('mosqueUUId', mosqueUUID);
    // sharedPref.save('mosqueSlug', mosqueSlug);
  }

  Future<void> _toggleScreen() async {
    try {
      await MethodChannel('nativeMethodsChannel').invokeMethod('toggleScreen');
    } on PlatformException catch (e) {
      logger.e(e);
    }
  }

  void scheduleToggleScreen(
      List<String> timeStrings, int beforeDelayMinutes, int afterDelayMinutes) {
    for (String timeString in timeStrings) {
      final parts = timeString.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);

      final now = AppDateTime.now();
      final scheduledDateTime =
          DateTime(now.year, now.month, now.day, hour, minute);

      if (scheduledDateTime.isBefore(now)) {
        // Schedule for the next day if the time has already passed
        scheduledDateTime.add(Duration(days: 1));
      }

      // Schedule one minute before
      final beforeDelay = scheduledDateTime.difference(now) -
          Duration(minutes: beforeDelayMinutes);
      if (beforeDelay.isNegative) {
        // Skip scheduling if the delay is negative
        continue;
      }
      Timer(beforeDelay, () {
        _toggleScreen();
      });
      print("Before delay Minutes: $beforeDelayMinutes");
      print("After delay Minutes: $afterDelayMinutes");

      print("Before delay: $beforeDelay");
      print("Before scheduledDateTime: $scheduledDateTime");

      // Schedule one minute after
      final afterDelay = scheduledDateTime.difference(now) +
          Duration(minutes: afterDelayMinutes);
      Timer(afterDelay, () {
        _toggleScreen();
      });
      print("After delay: $afterDelay");
      print("After scheduledDateTime: $scheduledDateTime");
    }
  }

  static Future<String?> loadLocalUUID() async {
    final sharedPref = SharedPref();
    return await sharedPref.read('mosqueUUId');
  }

  Future<void> loadFromLocale() async {
    // mosqueId = await sharedPref.read('mosqueId');
    mosqueUUID = await sharedPref.read('mosqueUUId');
    if (mosqueUUID != null) {
      await fetchMosque(mosqueUUID!);
    }
  }

  /// this method responsible for
  /// - fetching mosque, times, config
  /// - request audio manager to precache voices
  /// - request mawaqit cache to precache images after first load
  /// - handle errors of response
  /// It will return a future that will be completed when all data is fetched and cached
  Future<void> fetchMosque(String uuid) async {
    _mosqueSubscription?.cancel();
    _timesSubscription?.cancel();
    _configSubscription?.cancel();

    /// if getting item returns an error
    onItemError(e, stack) {
      logger.e(e, stackTrace: stack);

      mosque = null;
      notifyListeners();

      throw e;
    }

    /// cache date before complete the [completer]
    Future<void> completeFuture() async {
      try {
        await Future.wait([
          AudioManager().precacheVoices(mosqueConfig!),
          preCacheImages(),
        ]);
      } catch (e, stack) {
        debugPrintStack(label: e.toString(), stackTrace: stack);
      }
    }

    final mosqueStream = Api.getMosqueStream(uuid).asBroadcastStream();
    final timesStream = Api.getMosqueTimesStream(uuid).asBroadcastStream();
    final configStream = Api.getMosqueConfigStream(uuid).asBroadcastStream();

    _mosqueSubscription = mosqueStream.listen(
      (e) {
        mosque = e;
        _updateFlashEnabled();
        notifyListeners();
      },
      onError: onItemError,
    );

    _timesSubscription = timesStream.listen(
      (e) {
        times = e;
        final today =
            useTomorrowTimes ? AppDateTime.tomorrow() : AppDateTime.now();

        scheduleToggleScreen(
          e.dayTimesStrings(today, salahOnly: false),
          1,
          1,
        );
        notifyListeners();
      },
      onError: onItemError,
    );

    _configSubscription = configStream.listen(
      (e) {
        mosqueConfig = e;
        notifyListeners();
      },
      onError: onItemError,
    );

    /// wait for all streams to complete
    await Future.wait([
      mosqueStream.first.logPerformance('mosque'),
      timesStream.first.logPerformance('times'),
      configStream.first.logPerformance('config'),
    ]).logPerformance('Mosque data loader');
    await completeFuture();

    loadWeather(mosque!);

    mosqueUUID = uuid;
  }

  Future<Mosque> searchMosqueWithId(String mosqueId) =>
      Api.searchMosqueWithId(mosqueId);

  Future<List<Mosque>> searchMosques(String mosque, {page = 1}) async =>
      Api.searchMosques(mosque, page: page);

//todo handle page and get more
  Future<List<Mosque>> searchWithGps() async {
    final position =
        await getCurrentLocation().catchError((e) => throw GpsError());

    final url = Uri.parse(
        "$mawaqitApi/mosque/search?lat=${position.latitude}&lon=${position.longitude}");
    Map<String, String> requestHeaders = {
      // "Api-Access-Token": mawaqitApiToken,
    };
    final response = await http.get(url, headers: requestHeaders);
    // print(response.body);
    if (response.statusCode == 200) {
      final results = jsonDecode(response.body);
      List<Mosque> mosques = [];

      for (var item in results) {
        try {
          mosques.add(Mosque.fromMap(item));
        } catch (e, stack) {
          debugPrintStack(label: e.toString(), stackTrace: stack);
        }
      }

      return mosques;
    } else {
      print(response.body);
      // If that response was not OK, throw an error.
      throw Exception('Failed to fetch mosque');
    }
  }

  Future<Position> getCurrentLocation() async {
    var enabled = await GeolocatorPlatform.instance
        .isLocationServiceEnabled()
        .timeout(Duration(seconds: 5));

    if (!enabled) {
      enabled = await GeolocatorPlatform.instance.openLocationSettings();
    }
    if (!enabled) throw GpsError();

    final permission = await GeolocatorPlatform.instance.requestPermission();
    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) throw GpsError();

    return await GeolocatorPlatform.instance.getCurrentPosition();
  }

  /// handle pre caching for images
  /// Qr, mosque image, mosque logo, announcement image
  Future<void> preCacheImages() async {
    final images = [
      mosque?.image,
      mosque?.logo,
      mosque?.interiorPicture,
      mosque?.exteriorPicture,
      mosqueConfig?.motifUrl,
      kFooterQrLink,
      ...mosque?.announcements
              .map((e) => e.image)
              .where((element) => element != null) ??
          <String>[],
    ].where((e) => e != null).cast<String>();

    /// some images isn't existing anymore so we will ignore errors
    final futures = images
        .map((e) => MawaqitImageCache.cacheImage(e).catchError((e) {}))
        .toList();
    await Future.wait(futures);
  }
}

/// user for invalid mosque id-slug
class InvalidMosqueId implements Exception {}

class GpsError implements Exception {}
