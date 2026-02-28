import 'package:hive_flutter/hive_flutter.dart';

class CacheService {
  static const String _jobsBox = 'jobs_box';
  static const String _userBox = 'user_box';
  static const String _settingsBox = 'settings_box';

  Box? _jobsBoxInstance;
  Box? _userBoxInstance;
  Box? _settingsBoxInstance;

  Future<void> init() async {
    _jobsBoxInstance = await Hive.openBox(_jobsBox);
    _userBoxInstance = await Hive.openBox(_userBox);
    _settingsBoxInstance = await Hive.openBox(_settingsBox);
  }

  Box get jobsBox => _jobsBoxInstance!;
  Box get userBox => _userBoxInstance!;
  Box get settingsBox => _settingsBoxInstance!;

  // ── Jobs Cache
  Future<void> cacheJobs(List<Map<String, dynamic>> jobs) async {
    await _jobsBoxInstance?.put('all_jobs', jobs);
    await _jobsBoxInstance?.put('last_sync', DateTime.now().toIso8601String());
  }

  List<Map<String, dynamic>> getCachedJobs() {
    final data = _jobsBoxInstance?.get('all_jobs');
    if (data == null) return [];
    return List<Map<String, dynamic>>.from(data);
  }

  DateTime? getLastSync() {
    final str = _jobsBoxInstance?.get('last_sync');
    if (str == null) return null;
    return DateTime.tryParse(str);
  }

  bool get isCacheStale {
    final lastSync = getLastSync();
    if (lastSync == null) return true;
    return DateTime.now().difference(lastSync).inHours > 6;
  }

  // ── User Cache
  Future<void> cacheUser(Map<String, dynamic> userData) async {
    await _userBoxInstance?.put('user_data', userData);
  }

  Map<String, dynamic>? getCachedUser() {
    final data = _userBoxInstance?.get('user_data');
    if (data == null) return null;
    return Map<String, dynamic>.from(data);
  }

  String? get deviceCategory =>
      _userBoxInstance?.get('device_category') as String?;

  Future<void> setDeviceCategory(String category) async {
    await _userBoxInstance?.put('device_category', category);
  }

  // ── Settings
  Future<void> saveSetting(String key, dynamic value) async {
    await _settingsBoxInstance?.put(key, value);
  }

  dynamic getSetting(String key, {dynamic defaultValue}) {
    return _settingsBoxInstance?.get(key, defaultValue: defaultValue);
  }

  // ── Saved Jobs
  Future<void> saveJob(String jobId) async {
    final saved = getSavedJobIds();
    if (!saved.contains(jobId)) {
      saved.add(jobId);
      await _userBoxInstance?.put('saved_jobs', saved);
    }
  }

  Future<void> unsaveJob(String jobId) async {
    final saved = getSavedJobIds();
    saved.remove(jobId);
    await _userBoxInstance?.put('saved_jobs', saved);
  }

  List<String> getSavedJobIds() {
    final data = _userBoxInstance?.get('saved_jobs');
    if (data == null) return [];
    return List<String>.from(data);
  }

  bool isJobSaved(String jobId) => getSavedJobIds().contains(jobId);

  // ── Clear
  Future<void> clearAll() async {
    await _jobsBoxInstance?.clear();
    await _userBoxInstance?.clear();
    await _settingsBoxInstance?.clear();
  }

  Future<void> clearJobs() async {
    await _jobsBoxInstance?.clear();
  }
}
