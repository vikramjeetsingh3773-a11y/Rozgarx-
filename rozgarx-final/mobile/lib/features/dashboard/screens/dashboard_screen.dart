import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../jobs/widgets/job_card.dart';
import '../../../shared/models/job_model.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _userProfile;
  List<JobModel> _deadlineJobs = [];
  List<JobModel> _latestJobs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users').doc(uid).get();
      final profile = userDoc.data();

      // Fetch deadline-soon jobs
      final now = DateTime.now();
      final weekLater = now.add(const Duration(days: 7));
      final deadlineSnap = await FirebaseFirestore.instance
          .collection('jobs')
          .where('metadata.status', isEqualTo: 'approved')
          .where('importantDates.lastDate',
              isGreaterThan: Timestamp.fromDate(now))
          .where('importantDates.lastDate',
              isLessThanOrEqual: Timestamp.fromDate(weekLater))
          .orderBy('importantDates.lastDate')
          .limit(5)
          .get();

      // Fetch latest jobs
      final latestSnap = await FirebaseFirestore.instance
          .collection('jobs')
          .where('metadata.status', isEqualTo: 'approved')
          .orderBy('metadata.createdAt', descending: true)
          .limit(8)
          .get();

      if (mounted) {
        setState(() {
          _userProfile = profile;
          _deadlineJobs =
              deadlineSnap.docs.map(JobModel.fromFirestore).toList();
          _latestJobs =
              latestSnap.docs.map(JobModel.fromFirestore).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _userProfile?['displayName'] ??
        FirebaseAuth.instance.currentUser?.displayName ??
        'Aspirant';
    final isPremium =
        _userProfile?['subscription']?['status'] == 'active';

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: CustomScrollView(
          slivers: [
            // App bar
            SliverAppBar(
              floating: true,
              snap: true,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              elevation: 0,
              title: Row(children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text('RX', style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800,
                        fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                const Text('RozgarX AI',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ]),
              actions: [
                if (!isPremium)
                  TextButton.icon(
                    icon: const Icon(Icons.star, size: 16,
                        color: AppColors.warning),
                    label: const Text('Premium',
                        style: TextStyle(color: AppColors.warning,
                            fontSize: 12, fontWeight: FontWeight.w600)),
                    onPressed: () => context.push('/premium'),
                  ),
                IconButton(
                  icon: const Icon(Icons.notifications_outlined),
                  onPressed: () {},
                ),
              ],
            ),

            SliverToBoxAdapter(
              child: _loading
                  ? const Center(child: Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator()))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Greeting
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Good ${_greeting()}, ${name.split(' ').first} 👋',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const Text('Here\'s what\'s new today',
                                  style: TextStyle(
                                      color: Colors.grey, fontSize: 13)),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Quick stats
                        _QuickStats(
                            deadlineCount: _deadlineJobs.length,
                            latestCount: _latestJobs.length,
                            isPremium: isPremium),

                        // Deadline soon section
                        if (_deadlineJobs.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          _SectionHeader(
                            title: '⏰ Closing Soon',
                            subtitle: 'Apply before deadline',
                            onSeeAll: () => context.go('/jobs'),
                          ),
                          ..._deadlineJobs.map((job) => JobCard(
                                job: job,
                                onTap: () => context.push('/jobs/${job.jobId}'),
                              )),
                        ],

                        // Latest jobs
                        const SizedBox(height: 20),
                        _SectionHeader(
                          title: '🆕 Latest Jobs',
                          subtitle: 'Fresh notifications',
                          onSeeAll: () => context.go('/jobs'),
                        ),
                        ..._latestJobs.map((job) => JobCard(
                              job: job,
                              onTap: () => context.push('/jobs/${job.jobId}'),
                            )),

                        const SizedBox(height: 24),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'morning';
    if (h < 17) return 'afternoon';
    return 'evening';
  }
}

class _QuickStats extends StatelessWidget {
  final int deadlineCount;
  final int latestCount;
  final bool isPremium;
  const _QuickStats(
      {required this.deadlineCount,
      required this.latestCount,
      required this.isPremium});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 88,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _StatCard(
              emoji: '⏰',
              value: '$deadlineCount',
              label: 'Closing Soon',
              color: AppColors.error),
          const SizedBox(width: 12),
          _StatCard(
              emoji: '🆕',
              value: '$latestCount',
              label: 'New Today',
              color: AppColors.primary),
          const SizedBox(width: 12),
          _StatCard(
              emoji: isPremium ? '⭐' : '🔒',
              value: isPremium ? 'Active' : 'Free',
              label: 'Plan',
              color: isPremium ? AppColors.warning : Colors.grey),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String emoji;
  final String value;
  final String label;
  final Color color;
  const _StatCard(
      {required this.emoji,
      required this.value,
      required this.label,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const Spacer(),
        Text(value,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: color)),
        Text(label,
            style: TextStyle(fontSize: 11, color: color.withOpacity(0.7))),
      ]),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onSeeAll;
  const _SectionHeader(
      {required this.title, required this.subtitle, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700)),
          Text(subtitle,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        ])),
        if (onSeeAll != null)
          TextButton(
            onPressed: onSeeAll,
            child: const Text('See all',
                style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
      ]),
    );
  }
}
