import 'package:connectivity_plus/connectivity_plus.dart';
import 'cache_service.dart';

class NetworkService {
  final CacheService _cache;
  final Connectivity _connectivity = Connectivity();

  NetworkService(this._cache);

  Stream<List<ConnectivityResult>> get connectivityStream =>
      _connectivity.onConnectivityChanged;

  Future<bool> get isOnline async {
    final result = await _connectivity.checkConnectivity();
    return result != ConnectivityResult.none;
  }

  Future<bool> get isOffline async => !(await isOnline);

  Future<void> trackJobView(String jobId) async {
    await _cache.saveSetting('last_viewed_$jobId',
        DateTime.now().toIso8601String());
  }

  Future<void> prefetchUserData() async {
    final cached = _cache.getCachedUser();
    if (cached != null) {
      final category = _cache.deviceCategory;
      if (category != null) {
        await _cache.setDeviceCategory(category);
      }
    }
  }

  bool get hasCachedData => _cache.getCachedJobs().isNotEmpty;

  bool get isCacheStale => _cache.isCacheStale;
}
