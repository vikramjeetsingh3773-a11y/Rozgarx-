import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/models/job_model.dart';
import '../../../shared/widgets/job_card.dart';

class JobsListScreen extends StatefulWidget {
  const JobsListScreen({super.key});

  @override
  State<JobsListScreen> createState() => _JobsListScreenState();
}

class _JobsListScreenState extends State<JobsListScreen> {
  String _selectedCategory = 'All';

  final List<String> _categories = [
    'All', 'SSC', 'Railway', 'Banking', 'UPSC', 'Police', 'Defence'
  ];
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Job Notifications',
            style: TextStyle(
                color: Color(0xFF202124),
                fontSize: 16,
                fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list, color: Color(0xFF5F6368)),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          // Category filter chips
          Container(
            height: 44,
            color: Colors.white,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _categories.length,
              itemBuilder: (context, i) {
                final cat = _categories[i];
                final isSelected = cat == _selectedCategory;
                return GestureDetector(
                  onTap: () =>
                      setState(() => _selectedCategory = cat),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF1A73E8)
                          : const Color(0xFFE8F0FE),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(cat,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF1A73E8))),
                  ),
                );
              },
            ),
          ),

          // Jobs list
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _selectedCategory == 'All'
                  ? FirebaseFirestore.instance
                      .collection('jobs')
                      .where('isActive', isEqualTo: true)
                      .orderBy('applicationEnd')
                      .snapshots()
                  : FirebaseFirestore.instance
                      .collection('jobs')
                      .where('isActive', isEqualTo: true)
                      .where('category', isEqualTo: _selectedCategory)
                      .orderBy('applicationEnd')
                      .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('📋',
                            style: TextStyle(fontSize: 48)),
                        const SizedBox(height: 12),
                        Text(
                          _selectedCategory == 'All'
                              ? 'No jobs yet'
                              : 'No $_selectedCategory jobs',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        const Text('Check back later',
                            style: TextStyle(
                                color: Color(0xFF5F6368),
                                fontSize: 13)),
                      ],
                    ),
                  );
                }

                final jobs = snapshot.data!.docs
                    .map((doc) => JobModel.fromFirestore(doc))
                    .toList();

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: jobs.length,
                  itemBuilder: (context, i) => JobCard(
                    job: jobs[i],
                    onTap: () => context.push('/jobs/${jobs[i].id}'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
