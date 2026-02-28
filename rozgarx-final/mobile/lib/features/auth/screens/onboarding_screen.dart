import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _page = 0;
  bool _saving = false;

  // Collected data
  String? _educationLevel;
  final List<String> _targetExams = [];
  String? _state;
  String _preparationStage = 'beginner';

  final _exams = ['SSC', 'Railway', 'Banking', 'UPSC', 'State PSC', 'Police', 'Defence', 'Teaching'];
  final _states = ['All India', 'Punjab', 'Haryana', 'UP', 'Bihar', 'Rajasthan',
    'MP', 'Maharashtra', 'Gujarat', 'Karnataka', 'Tamil Nadu', 'West Bengal',
    'Delhi', 'Himachal Pradesh', 'Uttarakhand', 'Jharkhand', 'Odisha', 'Assam'];
  final _eduLevels = ['10th', '12th', 'Graduate', 'Postgraduate', 'Technical Diploma'];
  final _stages = ['beginner', 'intermediate', 'advanced'];

  void _next() {
    if (_page < 3) {
      _pageController.nextPage(duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut);
      setState(() => _page++);
    } else {
      _saveAndContinue();
    }
  }

  Future<void> _saveAndContinue() async {
    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'profile.educationLevel': _educationLevel,
        'profile.targetExams': _targetExams,
        'profile.state': _state,
        'profile.preparationStage': _preparationStage,
        'profile.onboardingComplete': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) context.go('/');
    } catch (_) {
      if (mounted) context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Progress bar
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Step ${_page + 1} of 4',
                          style: TextStyle(color: Colors.grey.shade600,
                              fontSize: 13)),
                      TextButton(
                        onPressed: _saveAndContinue,
                        child: const Text('Skip',
                            style: TextStyle(color: Colors.grey)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: (_page + 1) / 4,
                    backgroundColor: Colors.grey.shade200,
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(4),
                    minHeight: 4,
                  ),
                ],
              ),
            ),

            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _EducationPage(
                    selected: _educationLevel,
                    options: _eduLevels,
                    onSelect: (v) => setState(() => _educationLevel = v),
                  ),
                  _ExamsPage(
                    selected: _targetExams,
                    options: _exams,
                    onToggle: (v) => setState(() {
                      _targetExams.contains(v)
                          ? _targetExams.remove(v)
                          : _targetExams.add(v);
                    }),
                  ),
                  _StatePage(
                    selected: _state,
                    options: _states,
                    onSelect: (v) => setState(() => _state = v),
                  ),
                  _StagePage(
                    selected: _preparationStage,
                    onSelect: (v) => setState(() => _preparationStage = v),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _next,
                  style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: _saving
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : Text(_page < 3 ? 'Continue' : 'Get Started',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EducationPage extends StatelessWidget {
  final String? selected;
  final List<String> options;
  final ValueChanged<String> onSelect;
  const _EducationPage({required this.selected, required this.options, required this.onSelect});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Your Education Level',
          style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 8),
      const Text('We use this to show jobs you\'re eligible for.',
          style: TextStyle(color: Colors.grey)),
      const SizedBox(height: 24),
      ...options.map((opt) => _OptionTile(
        label: opt,
        isSelected: selected == opt,
        onTap: () => onSelect(opt),
      )),
    ]),
  );
}

class _ExamsPage extends StatelessWidget {
  final List<String> selected;
  final List<String> options;
  final ValueChanged<String> onToggle;
  const _ExamsPage({required this.selected, required this.options, required this.onToggle});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Target Exams', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 8),
      const Text('Select all you\'re preparing for (can change later).',
          style: TextStyle(color: Colors.grey)),
      const SizedBox(height: 24),
      Expanded(
        child: Wrap(
          spacing: 10, runSpacing: 10,
          children: options.map((opt) {
            final sel = selected.contains(opt);
            return GestureDetector(
              onTap: () => onToggle(opt),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: sel ? AppColors.primary : Colors.transparent,
                  border: Border.all(
                      color: sel ? AppColors.primary : Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(opt, style: TextStyle(
                    color: sel ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w500)),
              ),
            );
          }).toList(),
        ),
      ),
    ]),
  );
}

class _StatePage extends StatelessWidget {
  final String? selected;
  final List<String> options;
  final ValueChanged<String> onSelect;
  const _StatePage({required this.selected, required this.options, required this.onSelect});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Your State', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 8),
      const Text('For state-level job notifications.',
          style: TextStyle(color: Colors.grey)),
      const SizedBox(height: 24),
      Expanded(
        child: ListView(
          children: options.map((opt) => _OptionTile(
            label: opt,
            isSelected: selected == opt,
            onTap: () => onSelect(opt),
          )).toList(),
        ),
      ),
    ]),
  );
}

class _StagePage extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  const _StagePage({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final stages = [
      ('beginner', '🌱 Just Starting', 'New to government exam preparation'),
      ('intermediate', '📚 Preparing', 'Already studying, need guidance'),
      ('advanced', '🎯 Almost Ready', 'Appeared before, want to crack it this time'),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Preparation Stage',
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Text('We\'ll personalize your experience accordingly.',
            style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 24),
        ...stages.map((s) {
          final isSelected = selected == s.$1;
          return GestureDetector(
            onTap: () => onSelect(s.$1),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withOpacity(0.08)
                    : Colors.transparent,
                border: Border.all(
                    color: isSelected
                        ? AppColors.primary
                        : Colors.grey.shade200),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Text(s.$2.split(' ').first,
                    style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.$2.substring(3),
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      Text(s.$3,
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 12)),
                    ])),
                if (isSelected)
                  const Icon(Icons.check_circle, color: AppColors.primary),
              ]),
            ),
          );
        }),
      ]),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  const _OptionTile({required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primary.withOpacity(0.08) : Colors.transparent,
        border: Border.all(
            color: isSelected ? AppColors.primary : Colors.grey.shade200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Expanded(child: Text(label,
            style: TextStyle(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? AppColors.primary : Colors.black87))),
        if (isSelected) const Icon(Icons.check, color: AppColors.primary, size: 18),
      ]),
    ),
  );
}
