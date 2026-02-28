// lib/features/jobs/repository/job_repository.dart
// ============================================================
// RozgarX AI — Job Repository
// Offline-first data layer. Always returns cached data
// immediately, then updates from Firestore in background.
//
// Query patterns:
//   - By category (indexed)
//   - By category + state (composite index)
//   - By deadline approaching
//   - Search by title (client-side filter on cached data)
//   - Saved jobs (local cache)
// ============================================================

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../shared/models/job_model.dart';
import '../../core/cache/cache_service.dart';

class JobRepository {
  final FirebaseFirestore _db;
  final CacheService _cache;

  static const _pageSize = 15;

  JobRepository({
    required FirebaseFirestore db,
    required CacheService cache,
  })  : _db = db,
        _cache = cache;


  // ─────────────────────────────────────────────────────────
  // FETCH JOBS (Offline-first strategy)
  // Returns stream: first emission = cached, second = fresh
  // ─────────────────────────────────────────────────────────

  Stream<JobListResult> watchJobs({
    String? category,
    String? state,
    String? qualificationLevel,
    int? maxDifficultyScore,
    JobSortOrder sortBy = JobSortOrder.latestFirst,
    DocumentSnapshot? startAfter,
  }) async* {
    final cacheKey = _buildCacheKey(
      category: category,
      state: state,
      qualificationLevel: qualificationLevel,
      sortBy: sortBy,
    );

    // 1. Emit cached data immediately (no flicker)
    final cached = _cache.getCachedJobList(cacheKey);
    if (cached != null && cached.isNotEmpty) {
      yield JobListResult(
        jobs: cached,
        source: DataSource.cache,
        hasMore: cached.length >= _pageSize,
      );
    } else {
      // Emit loading state
      yield JobListResult(jobs: [], source: DataSource.loading, hasMore: false);
    }

    // 2. Fetch from Firestore if online
    if (!await _cache.isOnline) {
      if (cached == null || cached.isEmpty) {
        yield JobListResult(
          jobs: [],
          source: DataSource.offline,
          hasMore: false,
          error: 'No internet connection. Showing saved data.',
        );
      }
      return;
    }

    try {
      Query query = _db.collection('jobs')
          .where('metadata.status', isEqualTo: 'approved');

      // Apply filters (all indexed)
      if (category != null) {
        query = query.where('basicInfo.category', isEqualTo: category);
      }
      if (state != null) {
        query = query.where('basicInfo.state', isEqualTo: state);
      }

      // Sorting
      query = _applySorting(query, sortBy);

      // Pagination
      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      query = query.limit(_pageSize);

      final snap = await query.get(
        // Use server data — fall back to cache if server fails
        const GetOptions(source: Source.serverAndCache),
      );

      final jobs = snap.docs.map(JobModel.fromFirestore).toList();

      // Apply client-side filters (not indexed)
      final filtered = _applyClientFilters(
        jobs,
        maxDifficultyScore: maxDifficultyScore,
        qualificationLevel: qualificationLevel,
      );

      // Update cache
      if (startAfter == null) {
        // Only cache first page
        await _cache.cacheJobList(cacheKey, filtered);
      }

      // Apply saved status from local cache
      final withSavedStatus = filtered.map((job) =>
        job.copyWith(isSaved: _cache.isJobSaved(job.jobId))
      ).toList();

      yield JobListResult(
        jobs: withSavedStatus,
        source: DataSource.network,
        hasMore: snap.docs.length >= _pageSize,
        lastDoc: snap.docs.isNotEmpty ? snap.docs.last : null,
      );

    } on FirebaseException catch (e) {
      debugPrint('[JobRepo] Firestore error: ${e.code} - ${e.message}');
      // Fall back to cached data
      final fallback = _cache.getCachedJobList(cacheKey);
      yield JobListResult(
        jobs: fallback ?? [],
        source: DataSource.cache,
        hasMore: false,
        error: 'Could not refresh. Showing saved data.',
      );
    }
  }


  // ─────────────────────────────────────────────────────────
  // FETCH SINGLE JOB DETAIL
  // ─────────────────────────────────────────────────────────

  Future<JobModel?> getJobById(String jobId) async {
    // Check cache first
    final cached = _cache.getCachedJob(jobId);
    if (cached != null) return cached;

    // Fetch from Firestore
    try {
      final doc = await _db.collection('jobs').doc(jobId).get();
      if (!doc.exists) return null;

      final job = JobModel.fromFirestore(doc);
      final withSaved = job.copyWith(isSaved: _cache.isJobSaved(jobId));

      await _cache.cacheJob(withSaved);
      return withSaved;

    } catch (e) {
      debugPrint('[JobRepo] getJobById failed: $e');
      return null;
    }
  }


  // ─────────────────────────────────────────────────────────
  // DEADLINE-APPROACHING JOBS (for dashboard)
  // ─────────────────────────────────────────────────────────

  Future<List<JobModel>> getDeadlineSoonJobs({String? category}) async {
    const cacheKey = 'deadline_soon';
    final cached = _cache.getCachedJobList(cacheKey);
    if (cached != null) return cached;

    final sevenDaysLater = DateTime.now().add(const Duration(days: 7));
    final now = DateTime.now();

    try {
      Query query = _db.collection('jobs')
          .where('metadata.status', isEqualTo: 'approved')
          .where('importantDates.lastDate',
              isGreaterThan: Timestamp.fromDate(now))
          .where('importantDates.lastDate',
              isLessThanOrEqual: Timestamp.fromDate(sevenDaysLater))
          .orderBy('importantDates.lastDate')
          .limit(10);

      if (category != null) {
        query = query.where('basicInfo.category', isEqualTo: category);
      }

      final snap = await query.get();
      final jobs = snap.docs.map(JobModel.fromFirestore).toList();
      await _cache.cacheJobList(cacheKey, jobs);
      return jobs;

    } catch (e) {
      debugPrint('[JobRepo] getDeadlineSoonJobs failed: $e');
      return [];
    }
  }


  // ─────────────────────────────────────────────────────────
  // SEARCH (client-side on cached data for low bandwidth)
  // ─────────────────────────────────────────────────────────

  List<JobModel> searchCachedJobs(String query) {
    if (query.trim().isEmpty) return [];

    final lower = query.toLowerCase();
    return _allCachedJobs
        .where((job) =>
          job.basicInfo.title.toLowerCase().contains(lower) ||
          job.basicInfo.organization.toLowerCase().contains(lower) ||
          job.basicInfo.category.toLowerCase().contains(lower) ||
          (job.basicInfo.subCategory?.toLowerCase().contains(lower) ?? false))
        .toList();
  }

  List<JobModel> get _allCachedJobs {
    // Access all values from Hive box via cache service
    return _cache.getCachedJobList('search_pool') ?? [];
  }


  // ─────────────────────────────────────────────────────────
  // SAVE / UNSAVE JOB
  // ─────────────────────────────────────────────────────────

  Future<void> saveJob(String userId, JobModel job) async {
    // Local cache first (immediate response)
    await _cache.saveJob(job);

    // Sync to Firestore if online
    if (await _cache.isOnline) {
      try {
        await _db
            .collection('users')
            .doc(userId)
            .collection('savedJobs')
            .doc(job.jobId)
            .set({
          'jobId': job.jobId,
          'savedAt': FieldValue.serverTimestamp(),
          'jobTitle': job.basicInfo.title,
          'category': job.basicInfo.category,
          'lastDate': job.importantDates.lastDate != null
              ? Timestamp.fromDate(job.importantDates.lastDate!)
              : null,
        });
      } catch (e) {
        // Already saved locally — sync will happen on reconnect
        debugPrint('[JobRepo] saveJob Firestore sync failed: $e');
      }
    }
  }

  Future<void> unsaveJob(String userId, String jobId) async {
    await _cache.unsaveJob(jobId);

    if (await _cache.isOnline) {
      try {
        await _db
            .collection('users')
            .doc(userId)
            .collection('savedJobs')
            .doc(jobId)
            .delete();
      } catch (e) {
        debugPrint('[JobRepo] unsaveJob Firestore sync failed: $e');
      }
    }
  }

  List<JobModel> getSavedJobs() => _cache.getSavedJobs();


  // ─────────────────────────────────────────────────────────
  // SYNC OFFLINE QUEUE (call on reconnect)
  // ─────────────────────────────────────────────────────────

  Future<void> syncOfflineQueue(String userId) async {
    final queue = _cache.getPendingSyncQueue();
    if (queue.isEmpty) return;

    debugPrint('[JobRepo] Syncing ${queue.length} offline operations');

    for (final op in queue) {
      try {
        if (op['action'] == 'save_job') {
          final job = _cache.getSavedJobs()
              .firstWhere((j) => j.jobId == op['jobId'],
                          orElse: () => throw Exception('Job not found'));
          await saveJob(userId, job);
        } else if (op['action'] == 'unsave_job') {
          await _db.collection('users').doc(userId)
              .collection('savedJobs').doc(op['jobId'] as String).delete();
        }
      } catch (e) {
        debugPrint('[JobRepo] Sync failed for op: $op — $e');
      }
    }

    await _cache.clearSyncQueue();
    debugPrint('[JobRepo] Sync complete');
  }


  // ─────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────

  Query _applySorting(Query query, JobSortOrder sortBy) {
    switch (sortBy) {
      case JobSortOrder.latestFirst:
        return query.orderBy('metadata.createdAt', descending: true);
      case JobSortOrder.deadlineFirst:
        return query.orderBy('importantDates.lastDate', descending: false);
      case JobSortOrder.highestVacancies:
        return query.orderBy('basicInfo.vacancies', descending: true);
      case JobSortOrder.lowestCompetition:
        return query.orderBy('analytics.competitionScore', descending: false);
    }
  }

  List<JobModel> _applyClientFilters(
    List<JobModel> jobs, {
    int? maxDifficultyScore,
    String? qualificationLevel,
  }) {
    return jobs.where((job) {
      if (maxDifficultyScore != null &&
          (job.analytics.difficultyScore ?? 10) > maxDifficultyScore) {
        return false;
      }
      return true;
    }).toList();
  }

  String _buildCacheKey({
    String? category,
    String? state,
    String? qualificationLevel,
    JobSortOrder? sortBy,
  }) {
    return [
      category ?? 'all',
      state ?? 'all',
      qualificationLevel ?? 'all',
      sortBy?.name ?? 'latest',
    ].join('_');
  }
}


// ─────────────────────────────────────────────────────────────
// DATA TYPES
// ─────────────────────────────────────────────────────────────

enum JobSortOrder {
  latestFirst,
  deadlineFirst,
  highestVacancies,
  lowestCompetition,
}

enum DataSource {
  cache,
  network,
  offline,
  loading,
}

class JobListResult {
  final List<JobModel> jobs;
  final DataSource source;
  final bool hasMore;
  final DocumentSnapshot? lastDoc;
  final String? error;

  const JobListResult({
    required this.jobs,
    required this.source,
    required this.hasMore,
    this.lastDoc,
    this.error,
  });

  bool get isLoading => source == DataSource.loading;
  bool get isOffline => source == DataSource.offline;
}
