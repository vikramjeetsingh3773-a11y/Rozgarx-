import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/job_model.dart';

class JobDetailScreen extends StatefulWidget {
  final String jobId;
  const JobDetailScreen({super.key, required this.jobId});
  @override
  State<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> {
  JobModel? _job;
  bool _loading = true;
  bool _isSaved = false;

  @override
  void initState() {
    super.initState();
    _loadJob();
  }

  Future<void> _loadJob() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('jobs').doc(widget.jobId).get();
      if (doc.exists && mounted) {
        final job = JobModel.fromFirestore(doc);
        // Check saved status
        final uid = FirebaseAuth.instance.currentUser?.uid;
        bool saved = false;
        if (uid != null) {
          final savedDoc = await FirebaseFirestore.instance
              .collection('users').doc(uid)
              .collection('savedJobs').doc(widget.jobId).get();
          saved = savedDoc.exists;
        }
        setState(() { _job = job; _isSaved = saved; _loading = false; });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleSave() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _job == null) return;
    final ref = FirebaseFirestore.instance
        .collection('users').doc(uid)
        .collection('savedJobs').doc(widget.jobId);
    setState(() => _isSaved = !_isSaved);
    if (_isSaved) {
      await ref.set({
        'jobId': widget.jobId,
        'savedAt': FieldValue.serverTimestamp(),
        'jobTitle': _job!.basicInfo.title,
      });
    } else {
      await ref.delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(
        body: Center(child: CircularProgressIndicator()));
    if (_job == null) return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Job not found')));

    final job = _job!;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            snap: true,
            title: Text(job.basicInfo.organization,
                style: const TextStyle(fontSize: 14)),
            actions: [
              IconButton(
                icon: Icon(
                    _isSaved ? Icons.bookmark : Icons.bookmark_border),
                onPressed: _toggleSave,
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    _CategoryBadge(category: job.basicInfo.category),
                    const SizedBox(height: 8),
                    Text(job.basicInfo.title,
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 4),
                    Text(job.basicInfo.organization,
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 13)),
                    const SizedBox(height: 12),
                    Wrap(spacing: 10, runSpacing: 8, children: [
                      if (job.basicInfo.vacancies != null)
                        _InfoPill(
                            icon: Icons.people_outline,
                            text:
                                '${job.basicInfo.vacancies} Vacancies',
                            color: AppColors.primary),
                      _InfoPill(
                          icon: Icons.currency_rupee,
                          text: job.salaryDisplay,
                          color: AppColors.success),
                      _InfoPill(
                          icon: Icons.location_on_outlined,
                          text: job.basicInfo.isNational
                              ? 'All India'
                              : (job.basicInfo.state ?? 'India'),
                          color: Colors.orange),
                    ]),
                  ]),
                ),

                // AI Summary
                if (job.aiSummary != null) ...[
                  _Section(title: '🤖 AI Summary', child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(job.aiSummary!,
                        style: TextStyle(
                            color: Colors.grey.shade700,
                            height: 1.5, fontSize: 13)),
                  )),
                ],

                // Important Dates
                _Section(
                  title: '📅 Important Dates',
                  child: _DatesTable(dates: job.importantDates),
                ),

                // Vacancy breakdown
                if (job.vacancies.general != null)
                  _Section(
                    title: '👥 Category-wise Vacancies',
                    child: _VacancyTable(vacancies: job.vacancies),
                  ),

                // Eligibility
                _Section(
                  title: '🎓 Eligibility',
                  child: _EligibilitySection(eligibility: job.eligibility),
                ),

                // Selection process
                if (job.applicationDetails.selectionProcess.isNotEmpty)
                  _Section(
                    title: '🏆 Selection Process',
                    child: _SelectionStages(
                        stages: job.applicationDetails.selectionProcess),
                  ),

                // Exam pattern
                if (job.examPattern != null)
                  _Section(
                    title: '📝 Exam Pattern',
                    child: _ExamPatternSection(pattern: job.examPattern!),
                  ),

                // AI Analytics (premium teaser)
                _Section(
                  title: '📊 Competition Analysis',
                  child: _AnalyticsSection(job: job),
                ),

                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),

      // Bottom action bar
      bottomNavigationBar: _BottomActionBar(
        job: job,
        onViewPDF: job.applicationDetails.officialNotificationPDF != null
            ? () => context.push('/pdf', extra: {
                'jobId': job.jobId,
                'jobTitle': job.basicInfo.title,
                'directUrl': job.applicationDetails.officialNotificationPDF,
              })
            : null,
        onApply: () => context.push('/ad-unlock', extra: {
          'feature': 'apply_assistance',
          'jobTitle': job.basicInfo.title,
        }),
      ),
    );
  }
}

// ── Sub-widgets

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(title, style: const TextStyle(
            fontSize: 15, fontWeight: FontWeight.w700)),
      ),
      child,
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Divider(color: Colors.grey.shade100),
      ),
    ],
  );
}

class _CategoryBadge extends StatelessWidget {
  final String category;
  const _CategoryBadge({required this.category});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.primary.withOpacity(0.1),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(category, style: const TextStyle(
        fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary)),
  );
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _InfoPill({required this.icon, required this.text, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 4),
      Text(text, style: TextStyle(
          fontSize: 12, color: color, fontWeight: FontWeight.w500)),
    ]),
  );
}

class _DatesTable extends StatelessWidget {
  final JobImportantDates dates;
  const _DatesTable({required this.dates});
  String _fmt(DateTime? d) => d == null ? 'N/A' :
      DateFormat('dd MMM yyyy').format(d);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Column(children: [
      _DateRow('Application Start', _fmt(dates.applicationStartDate)),
      _DateRow('Last Date to Apply', _fmt(dates.lastDate),
          highlight: dates.lastDate != null &&
              dates.lastDate!.difference(DateTime.now()).inDays <= 7),
      _DateRow('Exam Date', _fmt(dates.examDate)),
      _DateRow('Admit Card', _fmt(dates.admitCardDate)),
      _DateRow('Result Date', _fmt(dates.resultDate)),
    ]),
  );
}

class _DateRow extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const _DateRow(this.label, this.value, {this.highlight = false});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Expanded(child: Text(label,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13))),
      Text(value, style: TextStyle(
          fontWeight: FontWeight.w600, fontSize: 13,
          color: highlight ? AppColors.error : null)),
    ]),
  );
}

class _VacancyTable extends StatelessWidget {
  final JobVacancies vacancies;
  const _VacancyTable({required this.vacancies});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Column(children: [
      if (vacancies.total != null)
        _VRow('Total', vacancies.total!, bold: true),
      if (vacancies.general != null) _VRow('General (UR)', vacancies.general!),
      if (vacancies.obc != null) _VRow('OBC', vacancies.obc!),
      if (vacancies.sc != null) _VRow('SC', vacancies.sc!),
      if (vacancies.st != null) _VRow('ST', vacancies.st!),
      if (vacancies.ews != null) _VRow('EWS', vacancies.ews!),
    ]),
  );
}

class _VRow extends StatelessWidget {
  final String label;
  final int value;
  final bool bold;
  const _VRow(this.label, this.value, {this.bold = false});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Expanded(child: Text(label, style: TextStyle(
          color: Colors.grey.shade700, fontSize: 13,
          fontWeight: bold ? FontWeight.w700 : FontWeight.normal))),
      Text('$value', style: TextStyle(
          fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
          fontSize: 13, color: bold ? AppColors.primary : null)),
    ]),
  );
}

class _EligibilitySection extends StatelessWidget {
  final JobEligibility eligibility;
  const _EligibilitySection({required this.eligibility});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (eligibility.educationRequired.isNotEmpty)
        _EligRow('Qualification',
            eligibility.educationRequired.join(', ')),
      if (eligibility.ageMin != null)
        _EligRow('Age Limit',
            '${eligibility.ageMin} – ${eligibility.ageMax} years'),
      if (eligibility.experienceRequired != null)
        _EligRow('Experience', eligibility.experienceRequired!),
    ]),
  );
}

class _EligRow extends StatelessWidget {
  final String label;
  final String value;
  const _EligRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(
          color: Colors.grey.shade500, fontSize: 11)),
      Text(value, style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w500)),
    ]),
  );
}

class _SelectionStages extends StatelessWidget {
  final List<SelectionStage> stages;
  const _SelectionStages({required this.stages});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Column(children: stages.map((s) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24, height: 24,
          decoration: BoxDecoration(
              color: AppColors.primary, shape: BoxShape.circle),
          child: Center(child: Text('${s.stage}', style: const TextStyle(
              color: Colors.white, fontSize: 11,
              fontWeight: FontWeight.w700))),
        ),
        const SizedBox(width: 12),
        Expanded(child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(s.name, style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13)),
            if (s.description != null)
              Text(s.description!, style: TextStyle(
                  color: Colors.grey.shade600, fontSize: 12)),
          ]),
        )),
      ],
    )).toList()),
  );
}

class _ExamPatternSection extends StatelessWidget {
  final ExamPattern pattern;
  const _ExamPatternSection({required this.pattern});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Wrap(spacing: 10, runSpacing: 10, children: [
      if (pattern.totalQuestions != null)
        _PatternChip('${pattern.totalQuestions} Questions'),
      if (pattern.totalMarks != null)
        _PatternChip('${pattern.totalMarks} Marks'),
      if (pattern.durationMinutes != null)
        _PatternChip('${pattern.durationMinutes} Minutes'),
      if (pattern.negativeMarking != null)
        _PatternChip('-${pattern.negativeMarking} Negative'),
      if (pattern.mode != null) _PatternChip(pattern.mode!),
    ]),
  );
}

class _PatternChip extends StatelessWidget {
  final String text;
  const _PatternChip(this.text);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(text, style: const TextStyle(
        fontSize: 12, fontWeight: FontWeight.w500)),
  );
}

class _AnalyticsSection extends StatelessWidget {
  final JobModel job;
  const _AnalyticsSection({required this.job});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(children: [
      Expanded(child: _AnalyticsTile(
          label: 'Competition',
          value: job.analytics.competitionLevel ?? 'Analyzing...',
          color: _compColor(job.analytics.competitionLevel))),
      const SizedBox(width: 12),
      Expanded(child: _AnalyticsTile(
          label: 'Difficulty',
          value: job.analytics.difficultyScore != null
              ? '${job.analytics.difficultyScore}/10'
              : 'Analyzing...',
          color: AppColors.warning)),
    ]),
  );

  Color _compColor(String? level) {
    switch (level?.toLowerCase()) {
      case 'low': return AppColors.success;
      case 'high': return AppColors.error;
      default: return AppColors.warning;
    }
  }
}

class _AnalyticsTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _AnalyticsTile({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withOpacity(0.2)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: color.withOpacity(0.7),
          fontSize: 11, fontWeight: FontWeight.w500)),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(color: color,
          fontSize: 15, fontWeight: FontWeight.w700)),
    ]),
  );
}

class _BottomActionBar extends StatelessWidget {
  final JobModel job;
  final VoidCallback? onViewPDF;
  final VoidCallback? onApply;
  const _BottomActionBar({required this.job, this.onViewPDF, this.onApply});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
    decoration: BoxDecoration(
      color: Theme.of(context).cardTheme.color,
      border: Border(top: BorderSide(color: Colors.grey.shade200)),
    ),
    child: Row(children: [
      if (onViewPDF != null)
        Expanded(child: OutlinedButton.icon(
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
          label: const Text('View PDF'),
          onPressed: onViewPDF,
          style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.primary)),
        )),
      if (onViewPDF != null) const SizedBox(width: 12),
      Expanded(
        flex: 2,
        child: ElevatedButton.icon(
          icon: const Icon(Icons.open_in_browser, size: 16),
          label: const Text('Apply Now'),
          onPressed: onApply,
          style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12)),
        ),
      ),
    ]),
  );
}
