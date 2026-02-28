// lib/core/network/network_service.dart
// ============================================================
// RozgarX AI — Network Detection Service
//
// Detects bandwidth category ONCE on first launch,
// stores in Hive. Never re-runs on every page load.
//
// Bandwidth categories:
//   low    = slow-2g, 2g, 3g with poor signal
//   medium = 3g with good signal, 4g with poor signal
//   high   = 4g LTE, wifi
//
// Used to adapt UI rendering throughout the app.
// ============================================================

import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../cache/cache_service.dart';

enum BandwidthCategory { low, medium, high }
enum DeviceCategory { lowEnd, midRange, highEnd }

class NetworkService {
  final CacheService _cache;
  final _connectivity = Connectivity();

  StreamSubscription<ConnectivityResult>? _subscription;
  final _onlineController = StreamController<bool>.broadcast();

  bool _isOnline = true;
  BandwidthCategory _bandwidth = BandwidthCategory.medium;
  DeviceCategory _device = DeviceCategory.midRange;

  NetworkService({required CacheService cache}) : _cache = cache;


  // ── GETTERS
  bool get isOnline => _isOnline;
  BandwidthCategory get bandwidth => _bandwidth;
  DeviceCategory get device => _device;
  Stream<bool> get onlineStream => _onlineController.stream;

  bool get isLowEnd =>
      _device == DeviceCategory.lowEnd || _bandwidth == BandwidthCategory.low;

  bool get shouldReduceAnimations => isLowEnd;
  bool get shouldLazyLoadImages => _bandwidth != BandwidthCategory.high;
  bool get shouldDeferAIInsights => _bandwidth == BandwidthCategory.low;


  // ── INITIALIZATION (call once at app startup)
  Future<void> init() async {
    // Detect current online status
    final result = await _connectivity.checkConnectivity();
    _isOnline = result != ConnectivityResult.none;

    // Listen for changes
    _subscription = _connectivity.onConnectivityChanged.listen((result) {
      final nowOnline = result != ConnectivityResult.none;
      if (nowOnline != _isOnline) {
        _isOnline = nowOnline;
        _onlineController.add(_isOnline);
        debugPrint('[Network] Status changed: ${_isOnline ? "ONLINE" : "OFFLINE"}');
      }
    });

    // Detect device category
    await _detectDeviceCategory();

    // Detect bandwidth (from cache or fresh measurement)
    await _detectBandwidth();
  }

  void dispose() {
    _subscription?.cancel();
    _onlineController.close();
  }


  // ── DEVICE DETECTION
  // Reads device RAM to classify as low/mid/high-end.
  // Stored once and reused — no repeated detection.

  Future<void> _detectDeviceCategory() async {
    // Check cache first
    final cached = _cache.bandwidthCategory;
    if (cached.isNotEmpty && _cache._userBox.get('deviceCategory') != null) {
      final cachedDevice = _cache._userBox.get('deviceCategory') as String;
      _device = DeviceCategory.values.firstWhere(
        (e) => e.name == cachedDevice,
        orElse: () => DeviceCategory.midRange,
      );
      return;
    }

    try {
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        // RAM detection via system info
        // Note: direct RAM access requires native plugin in production
        // For now, use SDK version as proxy:
        final sdkInt = androidInfo.version.sdkInt;

        if (sdkInt < 26) {  // Android 8.0
          _device = DeviceCategory.lowEnd;
        } else if (sdkInt < 30) { // Android 10
          _device = DeviceCategory.midRange;
        } else {
          _device = DeviceCategory.highEnd;
        }
      }
    } catch (e) {
      _device = DeviceCategory.midRange; // Safe default
    }

    await _cache._userBox.put('deviceCategory', _device.name);
    debugPrint('[Network] Device category: ${_device.name}');
  }


  // ── BANDWIDTH DETECTION
  // Runs once per day maximum. Uses a lightweight timing test.

  Future<void> _detectBandwidth() async {
    final lastDetectedAt = _cache._userBox.get('bandwidthDetectedAt') as int?;
    final now = DateTime.now().millisecondsSinceEpoch;
    const oneDayMs = 86400000;

    // Use cached value if detected within last 24 hours
    if (lastDetectedAt != null && (now - lastDetectedAt) < oneDayMs) {
      final cached = _cache.bandwidthCategory;
      _bandwidth = BandwidthCategory.values.firstWhere(
        (e) => e.name == cached,
        orElse: () => BandwidthCategory.medium,
      );
      debugPrint('[Network] Bandwidth from cache: ${_bandwidth.name}');
      return;
    }

    if (!_isOnline) {
      _bandwidth = BandwidthCategory.low;
      return;
    }

    try {
      // Lightweight speed test: time a small request
      final stopwatch = Stopwatch()..start();

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);

      // Use a tiny image from a reliable CDN
      final request = await client.getUrl(
        Uri.parse('https://www.gstatic.com/generate_204'),
      );
      request.headers.set('Cache-Control', 'no-cache');
      final response = await request.close();
      await response.drain();
      client.close();

      stopwatch.stop();
      final ms = stopwatch.elapsedMilliseconds;

      if (ms < 200) {
        _bandwidth = BandwidthCategory.high;
      } else if (ms < 800) {
        _bandwidth = BandwidthCategory.medium;
      } else {
        _bandwidth = BandwidthCategory.low;
      }

      debugPrint('[Network] Speed test: ${ms}ms → ${_bandwidth.name}');

    } catch (e) {
      _bandwidth = BandwidthCategory.medium;
      debugPrint('[Network] Speed test failed, defaulting to medium: $e');
    }

    await _cache.saveBandwidthCategory(_bandwidth.name);
  }


  // ── CONNECTIVITY HELPER for UI
  String get connectionStatusMessage {
    if (!_isOnline) return 'No internet connection';
    switch (_bandwidth) {
      case BandwidthCategory.low:
        return 'Slow connection — loading essentials only';
      case BandwidthCategory.medium:
        return 'Connected';
      case BandwidthCategory.high:
        return 'Connected';
    }
  }
}


// ── UI Adaptation Config (passed to widgets)
class UIConfig {
  final bool showAnimations;
  final bool showHeavyCharts;
  final bool lazyLoadImages;
  final bool deferAIInsights;
  final bool showShimmer;  // Always true — improves perceived performance

  const UIConfig({
    this.showAnimations = true,
    this.showHeavyCharts = true,
    this.lazyLoadImages = false,
    this.deferAIInsights = false,
    this.showShimmer = true,
  });

  // Factory constructors for each device tier
  factory UIConfig.highEnd() => const UIConfig(
    showAnimations: true,
    showHeavyCharts: true,
    lazyLoadImages: false,
    deferAIInsights: false,
  );

  factory UIConfig.midRange() => const UIConfig(
    showAnimations: true,
    showHeavyCharts: true,
    lazyLoadImages: true,
    deferAIInsights: false,
  );

  factory UIConfig.lowEnd() => const UIConfig(
    showAnimations: false,
    showHeavyCharts: false,
    lazyLoadImages: true,
    deferAIInsights: true,
  );

  factory UIConfig.fromNetwork(NetworkService network) {
    if (network.isLowEnd) return UIConfig.lowEnd();
    if (network.device == DeviceCategory.midRange) return UIConfig.midRange();
    return UIConfig.highEnd();
  }
}
