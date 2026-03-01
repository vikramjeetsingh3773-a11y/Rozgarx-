import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/models/job_model.dart';
import '../../../shared/widgets/job_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // App Bar
            SliverAppBar(
              floating: true,
              backgroundColor: Colors.white,
              elevation: 0,
              title: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A73E8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Text('RX',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 10)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('RozgarX AI',
                      style: TextStyle(
                          color: Color(0xFF202124),
                          fontWeight: FontWeight.w700,
                          fontSize: 16)),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined,
                      color: Color(0xFF202124)),
                  onPressed: () {},
                ),
              ],
            ),

            // Greeting
            SliverToBoxAdapter(
              child: Container(
                color: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Good morning 👋',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF202124))),
                    SizedBox(height: 2),
                    Text("Here's what's new today",
                        style: TextStyle(
                            fontSize: 13, color: Color(0xFF5F6368))),
                  ],
                ),
              ),
            ),

            // Stats Row
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    _StatCard(
                        emoji: '⏰',
                        value: '5',
                        label: 'Closing Soon',
                        color: const Color(0xFFEA4335)),
                    const SizedBox(width: 8),
                    _StatCard(
                        emoji: '🆕',
                        value: '12',
                        label: 'New Today',
                        color: const Color(0xFF1A73E8)),
                    const SizedBox(width: 8),
                    _StatCard(
                        emoji: '⭐',
                        value: 'Free',
                        label: 'Your Plan',
                        color: const Color(0xFFF9AB00)),
                  ],
                ),
              ),
            ),

            // Section Header
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('⏰ Closing Soon',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: Color(0xFF202124))),
                    GestureDetector(
                      onTap: () => context.go('/jobs'),
                      child: const Text('See all',
                          style: TextStyle(
                              color: Color(0xFF1A73E8),
                              fontWeight: FontWeight.w600,
                              fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ),

            // Jobs from Firestore
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('jobs')
                  .where('isActive', isEqualTo: true)
                  .where('applicationEnd',
                      isGreaterThanOrEqualTo: Timestamp.now())
                  .orderBy('applicationEnd')
                  .limit(10)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SliverToBoxAdapter(
                    child: Center(
                        child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(),
                    )),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: Column(
                          children: [
                            Text('📋', style: TextStyle(fontSize: 48)),
                            SizedBox(height: 12),
                            Text('No jobs yet',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16)),
                            SizedBox(height: 4),
                            Text('Jobs will appear here once added',
                                style: TextStyle(
                                    color: Color(0xFF5F6368),
                                    fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                final jobs = snapshot.data!.docs
                    .map((doc) => JobModel.fromFirestore(doc))
                    .toList();

                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      child: JobCard(
                        job: jobs[index],
                        onTap: () =>
                            context.go('/jobs/${jobs[index].id}'),
                      ),
                    ),
                    childCount: jobs.length,
                  ),
                );
              },
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 20)),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String emoji;
  final String value;
  final String label;
  final Color color;

  const _StatCard({
    required this.emoji,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: color)),
            Text(label,
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    color: color)),
          ],
        ),
      ),
    );
  }
}
