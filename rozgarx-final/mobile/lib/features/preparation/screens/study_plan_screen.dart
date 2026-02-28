import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';

// ============================================================
// STUDY PLAN SCREEN
// ============================================================
class StudyPlanScreen extends StatefulWidget {
  const StudyPlanScreen({super.key});
  @override
  State<StudyPlanScreen> createState() => _StudyPlanScreenState();
}

class _StudyPlanScreenState extends State<StudyPlanScreen> {
  bool _loading = false;
  Map<String, dynamic>? _currentPlan;
  int _aiQueriesUsed = 0;
  int _aiQueryLimit = 5;

  @override
  void initState() {
    super.initState();
    _loadExistingPlan();
  }

  Future<void> _loadExistingPlan() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final userDoc = await FirebaseFirestore.instance
        .collection('users').doc(uid).get();
    final data = userDoc.data() ?? {};

    setState(() {
      _aiQueriesUsed = data['aiUsage']?['queriesUsed'] ?? 0;
      _aiQueryLimit = data['aiUsage']?['aiLimit'] ?? 5;
    });

    // Check for existing plan
    final plans = await FirebaseFirestore.instance
        .collection('users').doc(uid)
        .collection('studyPlans')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    if (plans.docs.isNotEmpty && mounted) {
      setState(() => _currentPlan = plans.docs.first.data());
    }
  }

  Future<void> _generatePlan() async {
    if (_aiQueriesUsed >= _aiQueryLimit) {
      _showLimitDialog();
      return;
    }
    setState(() => _loading = true);
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'asia-south1');
      final result = await functions.httpsCallable('handleAIQuery').call({
        'queryType': 'study_plan',
        'planType': '30-day',
      });
      setState(() {
        _currentPlan = Map<String, dynamic>.from(result.data);
        _aiQueriesUsed++;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not generate plan: $e')),
        );
      }
    }
  }

  void _showLimitDialog() {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Daily Limit Reached'),
      content: Text(
          'You\'ve used all $_aiQueryLimit free AI queries today. '
          'Upgrade to Premium for unlimited access.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () { Navigator.pop(context); context.push('/premium'); },
          child: const Text('Upgrade'),
        ),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Study Preparation'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: Text(
              '$_aiQueriesUsed/$_aiQueryLimit AI',
              style: TextStyle(
                  fontSize: 12,
                  color: _aiQueriesUsed >= _aiQueryLimit
                      ? AppColors.error
                      : Colors.grey.shade600),
            )),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Generating your personalized plan...'),
                SizedBox(height: 8),
                Text('This may take a moment', style: TextStyle(color: Colors.grey, fontSize: 12)),
              ]))
          : _currentPlan != null
              ? _PlanView(plan: _currentPlan!, onRegenerate: _generatePlan)
              : _EmptyPlanView(
                  onGenerate: _generatePlan,
                  onUpgrade: () => context.push('/premium'),
                  queriesRemaining: _aiQueryLimit - _aiQueriesUsed,
                ),
    );
  }
}

class _EmptyPlanView extends StatelessWidget {
  final VoidCallback onGenerate;
  final VoidCallback onUpgrade;
  final int queriesRemaining;
  const _EmptyPlanView({required this.onGenerate, required this.onUpgrade,
      required this.queriesRemaining});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('📚', style: TextStyle(fontSize: 56)),
        const SizedBox(height: 20),
        Text('AI Study Plan Generator',
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        const Text(
          'Get a personalized 30-day study plan based on your target exam and profile.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 32),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: queriesRemaining > 0 ? onGenerate : null,
          style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14)),
          child: Text(queriesRemaining > 0
              ? 'Generate My Study Plan ($queriesRemaining free left)'
              : 'No AI Queries Left Today'),
        )),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: OutlinedButton(
          onPressed: onUpgrade,
          child: const Text('⭐ Upgrade for Unlimited Plans'),
        )),
      ]),
    ),
  );
}

class _PlanView extends StatelessWidget {
  final Map<String, dynamic> plan;
  final VoidCallback onRegenerate;
  const _PlanView({required this.plan, required this.onRegenerate});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text(plan['planType'] ?? '30-Day Plan',
              style: Theme.of(context).textTheme.titleLarge),
          Text('For: ${plan['examTarget'] ?? 'Your Exam'}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        ])),
        TextButton(onPressed: onRegenerate, child: const Text('Regenerate')),
      ]),
      const SizedBox(height: 16),

      // Strategy
      if (plan['recommendedStrategy'] != null) ...[
        const Text('Strategy', style: TextStyle(
            fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(plan['recommendedStrategy'],
              style: const TextStyle(fontSize: 13, height: 1.5)),
        ),
        const SizedBox(height: 16),
      ],

      // Weekly breakdown preview
      const Text('Weekly Breakdown', style: TextStyle(
          fontWeight: FontWeight.w700, fontSize: 15)),
      const SizedBox(height: 8),
      const Text(
          'Full week-by-week plan is available in the premium dashboard.',
          style: TextStyle(color: Colors.grey, fontSize: 13)),
    ]),
  );
}
