import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../widgets/job_card.dart';
import '../../../shared/models/job_model.dart';

class JobsListScreen extends StatefulWidget {
  const JobsListScreen({super.key});
  @override
  State<JobsListScreen> createState() => _JobsListScreenState();
}

class _JobsListScreenState extends State<JobsListScreen> {
  final _scrollController = ScrollController();
  final List<JobModel> _jobs = [];
  DocumentSnapshot? _lastDoc;
  bool _loading = false;
  bool _hasMore = true;
  String? _selectedCategory;
  String _sortBy = 'latest';

  final _categories = ['All', 'SSC', 'Railway', 'Banking', 'Police',
    'Defence', 'StatePSC', 'Teaching'];

  @override
  void initState() {
    super.initState();
    _fetchJobs();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >
          _scrollController.position.maxScrollExtent - 200) {
        if (!_loading && _hasMore) _fetchJobs();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchJobs({bool reset = false}) async {
    if (_loading) return;
    if (reset) {
      setState(() { _jobs.clear(); _lastDoc = null; _hasMore = true; });
    }
    setState(() => _loading = true);

    try {
      Query query = FirebaseFirestore.instance
          .collection('jobs')
          .where('metadata.status', isEqualTo: 'approved');

      if (_selectedCategory != null && _selectedCategory != 'All') {
        query = query.where('basicInfo.category',
            isEqualTo: _selectedCategory);
      }

      query = _sortBy == 'latest'
          ? query.orderBy('metadata.createdAt', descending: true)
          : query.orderBy('importantDates.lastDate', descending: false);

      if (_lastDoc != null) query = query.startAfterDocument(_lastDoc!);
      query = query.limit(15);

      final snap = await query.get();
      final jobs = snap.docs.map(JobModel.fromFirestore).toList();

      setState(() {
        _jobs.addAll(jobs);
        _lastDoc = snap.docs.isNotEmpty ? snap.docs.last : null;
        _hasMore = snap.docs.length >= 15;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Job Notifications'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sort),
            onPressed: _showSortSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          // Category filter chips
          SizedBox(
            height: 48,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _categories.length,
              itemBuilder: (_, i) {
                final cat = _categories[i];
                final isSelected = cat == 'All'
                    ? _selectedCategory == null
                    : _selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(cat,
                        style: TextStyle(
                            fontSize: 12,
                            color: isSelected
                                ? Colors.white
                                : AppColors.primary,
                            fontWeight: FontWeight.w500)),
                    selected: isSelected,
                    onSelected: (_) {
                      setState(() =>
                          _selectedCategory = cat == 'All' ? null : cat);
                      _fetchJobs(reset: true);
                    },
                    selectedColor: AppColors.primary,
                    backgroundColor: AppColors.primary.withOpacity(0.08),
                    checkmarkColor: Colors.white,
                    side: BorderSide.none,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                );
              },
            ),
          ),

          const Divider(height: 1),

          // Job list
          Expanded(
            child: _jobs.isEmpty && _loading
                ? const Center(child: CircularProgressIndicator())
                : _jobs.isEmpty
                    ? _EmptyState(
                        onReset: () {
                          setState(() => _selectedCategory = null);
                          _fetchJobs(reset: true);
                        })
                    : ListView.builder(
                        controller: _scrollController,
                        itemCount: _jobs.length + (_hasMore ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (i == _jobs.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                  child: CircularProgressIndicator()),
                            );
                          }
                          return JobCard(
                            job: _jobs[i],
                            onTap: () =>
                                context.push('/jobs/${_jobs[i].jobId}'),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Sort By',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ...['latest', 'deadline'].map((s) => RadioListTile<String>(
                  title: Text(s == 'latest'
                      ? 'Latest First'
                      : 'Deadline First'),
                  value: s,
                  groupValue: _sortBy,
                  activeColor: AppColors.primary,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) {
                    setState(() => _sortBy = v!);
                    Navigator.pop(context);
                    _fetchJobs(reset: true);
                  },
                )),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onReset;
  const _EmptyState({required this.onReset});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('📋', style: TextStyle(fontSize: 48)),
      const SizedBox(height: 12),
      const Text('No jobs found',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      const Text('Try changing the category filter',
          style: TextStyle(color: Colors.grey)),
      const SizedBox(height: 16),
      TextButton(onPressed: onReset, child: const Text('Clear Filters')),
    ]),
  );
}
