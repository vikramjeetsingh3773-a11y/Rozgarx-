import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/models/job_model.dart';
import '../../../core/theme/app_theme.dart';

// ============================================================
// LEGAL SAFE APPLY ASSISTANCE
// - Does NOT submit forms on behalf of users
// - Does NOT collect government fees  
// - Opens official site in embedded WebView
// - User fills and submits manually
// ============================================================

class ApplyAssistanceScreen extends StatefulWidget {
  final JobModel job;
  final bool hasAccess;
  const ApplyAssistanceScreen({
    super.key, required this.job, required this.hasAccess,
  });
  @override
  State<ApplyAssistanceScreen> createState() => _ApplyAssistanceScreenState();
}

class _ApplyAssistanceScreenState extends State<ApplyAssistanceScreen> {
  int _step = 0;
  bool _checkingEligibility = false;
  Map<String, dynamic>? _eligibility;
  final List<Map<String, dynamic>> _docChecklist = [];
  bool _kitBuilt = false;

  @override
  void initState() {
    super.initState();
    if (widget.hasAccess) _runEligibilityCheck();
    _buildDocumentKit();
  }

  Future<void> _runEligibilityCheck() async {
    setState(() => _checkingEligibility = true);
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'asia-south1');
      final result = await fn.httpsCallable('checkJobEligibility')
          .call({'jobId': widget.job.jobId});
      if (mounted) {
        setState(() {
          _eligibility = Map<String, dynamic>.from(result.data);
          _checkingEligibility = false;
        });
      }
    } catch (_) {
      // Fallback: show basic info from job data
      if (mounted) {
        setState(() {
          _eligibility = {
            'isEligible': true,
            'verdict': 'Verify eligibility in the official notification',
            'checks': [
              {'label': 'Age Limit',
               'value': widget.job.eligibility.ageMin != null
                   ? '${widget.job.eligibility.ageMin}–${widget.job.eligibility.ageMax} years'
                   : 'See notification',
               'passed': null},
              {'label': 'Qualification',
               'value': widget.job.eligibility.educationRequired.join(', '),
               'passed': null},
            ],
          };
          _checkingEligibility = false;
        });
      }
    }
  }

  void _buildDocumentKit() {
    _docChecklist.addAll([
      {'name': '10th Marksheet', 'note': 'For DOB/age proof', 'checked': false},
      {'name': '12th Marksheet', 'note': 'If applicable', 'checked': false},
      {'name': 'Graduation Certificate',
       'note': 'If applying for graduate-level post', 'checked': false},
      {'name': 'Caste Certificate',
       'note': 'SC/ST/OBC — if claiming reservation', 'checked': false},
      {'name': 'EWS Certificate', 'note': 'If applicable', 'checked': false},
      {'name': 'Passport-size Photo',
       'note': 'White background, recent, as per specifications',
       'checked': false},
      {'name': 'Signature Scan',
       'note': 'On white paper, clear, not smudged', 'checked': false},
      {'name': 'Valid Photo ID',
       'note': 'Aadhaar / Voter ID / Passport', 'checked': false},
    ]);
    setState(() => _kitBuilt = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.hasAccess) {
      return _UnlockPrompt(job: widget.job);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('Apply: ${widget.job.basicInfo.title}',
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: [
          _StepBar(step: _step),
          Expanded(child: _buildStepBody()),
        ],
      ),
    );
  }

  Widget _buildStepBody() {
    switch (_step) {
      case 0: return _buildEligibilityStep();
      case 1: return _buildKitStep();
      case 2: return _buildWebViewStep();
      default: return _buildEligibilityStep();
    }
  }

  // ── STEP 1: ELIGIBILITY
  Widget _buildEligibilityStep() {
    if (_checkingEligibility) {
      return const Center(child: Column(mainAxisSize: MainAxisSize.min,
          children: [
        CircularProgressIndicator(),
        SizedBox(height: 16),
        Text('Checking eligibility with AI...'),
      ]));
    }
    if (_eligibility == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final isEligible = _eligibility!['isEligible'] as bool? ?? true;
    final verdict = _eligibility!['verdict'] as String? ?? '';
    final checks =
        (_eligibility!['checks'] as List? ?? []).cast<Map<String, dynamic>>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Verdict banner
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: (isEligible ? AppColors.success : AppColors.error)
                .withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: (isEligible ? AppColors.success : AppColors.error)
                  .withOpacity(0.3),
            ),
          ),
          child: Row(children: [
            Icon(isEligible ? Icons.check_circle : Icons.warning_amber,
                color: isEligible ? AppColors.success : AppColors.error),
            const SizedBox(width: 10),
            Expanded(child: Text(verdict, style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isEligible ? AppColors.success : AppColors.error))),
          ]),
        ),
        const SizedBox(height: 16),

        const Text('Eligibility Breakdown',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 8),
        ...checks.map((c) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Icon(
              c['passed'] == true
                  ? Icons.check
                  : c['passed'] == false
                      ? Icons.close
                      : Icons.help_outline,
              size: 18,
              color: c['passed'] == true
                  ? AppColors.success
                  : c['passed'] == false
                      ? AppColors.error
                      : Colors.grey,
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c['label'] ?? '', style: const TextStyle(
                  fontWeight: FontWeight.w500, fontSize: 13)),
              Text(c['value'] ?? '', style: TextStyle(
                  color: Colors.grey.shade600, fontSize: 12)),
            ])),
          ]),
        )),

        // Competition insight
        if (widget.job.analytics.competitionLevel != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.purple.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              const Text('📊', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${widget.job.analytics.competitionLevel} Competition',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (widget.job.analytics.difficultyScore != null)
                  Text('Difficulty: ${widget.job.analytics.difficultyScore}/10',
                      style: TextStyle(color: Colors.grey.shade600,
                          fontSize: 12)),
              ])),
            ]),
          ),
        ],

        const SizedBox(height: 24),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: () => setState(() => _step = 1),
          child: const Text('Continue to Document Checklist'),
        )),
      ]),
    );
  }

  // ── STEP 2: DOCUMENT KIT
  Widget _buildKitStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Document Checklist',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 4),
        const Text('Check off documents you have ready.',
            style: TextStyle(color: Colors.grey, fontSize: 13)),
        const SizedBox(height: 12),

        ..._docChecklist.asMap().entries.map((e) {
          final doc = e.value;
          return CheckboxListTile(
            title: Text(doc['name'], style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w500)),
            subtitle: Text(doc['note'],
                style: const TextStyle(fontSize: 11)),
            value: doc['checked'] as bool,
            onChanged: (v) => setState(() => _docChecklist[e.key]['checked'] = v),
            activeColor: AppColors.primary,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
          );
        }),

        const SizedBox(height: 16),

        // Photo guide
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('📸 Photo & Signature Tips',
                style: TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(height: 6),
            Text('• Photo: White background, passport size, recent',
                style: TextStyle(fontSize: 12)),
            Text('• File size: Usually 20KB–100KB JPG',
                style: TextStyle(fontSize: 12)),
            Text('• Signature: On plain white paper, clear',
                style: TextStyle(fontSize: 12)),
          ]),
        ),

        const SizedBox(height: 16),

        // Fee notice — PROMINENTLY shown
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.info_outline,
                  size: 16, color: AppColors.primary),
              SizedBox(width: 6),
              Text('Application Fee Notice',
                  style: TextStyle(fontWeight: FontWeight.w600,
                      color: AppColors.primary)),
            ]),
            const SizedBox(height: 6),
            if (widget.job.applicationDetails.applicationFee != null)
              Text(widget.job.applicationDetails.applicationFee!,
                  style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 4),
            const Text(
              'Official fees are paid directly on the official website. '
              'RozgarX AI does NOT collect any government fees.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ]),
        ),

        const SizedBox(height: 24),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: () => setState(() => _step = 2),
          child: const Text('Open Official Website'),
        )),
      ]),
    );
  }

  // ── STEP 3: OFFICIAL WEBSITE WEBVIEW
  Widget _buildWebViewStep() {
    final url = widget.job.applicationDetails.applicationLink ??
        widget.job.applicationDetails.officialWebsite;
    if (url == null) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Official website URL is not available for this job.\n'
          'Please check the PDF notification for the application link.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      ));
    }
    return _OfficialWebView(
      url: url,
      jobTitle: widget.job.basicInfo.title,
      organization: widget.job.basicInfo.organization,
      jobId: widget.job.jobId,
    );
  }
}


// ── Official WebView
class _OfficialWebView extends StatefulWidget {
  final String url;
  final String jobTitle;
  final String organization;
  final String jobId;
  const _OfficialWebView({
    required this.url, required this.jobTitle,
    required this.organization, required this.jobId,
  });
  @override
  State<_OfficialWebView> createState() => _OfficialWebViewState();
}

class _OfficialWebViewState extends State<_OfficialWebView> {
  late final WebViewController _ctrl;
  bool _loading = true;
  String _currentUrl = '';

  static const _paymentDomains = [
    'payu.in', 'paytm.com', 'billdesk.com',
    'onlinesbi.com', 'sbi.co.in',
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _loading = true),
        onPageFinished: (url) =>
            setState(() { _currentUrl = url; _loading = false; }),
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  bool get _onPayment =>
      _paymentDomains.any((d) => _currentUrl.contains(d));

  @override
  Widget build(BuildContext context) {
    final domain = Uri.tryParse(_currentUrl.isNotEmpty
        ? _currentUrl : widget.url)?.host ?? '';
    return Column(children: [
      // Domain bar
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        color: _onPayment
            ? AppColors.success.withOpacity(0.1)
            : Colors.grey.shade100,
        child: Row(children: [
          Icon(_onPayment ? Icons.lock : Icons.language,
              size: 13,
              color: _onPayment ? AppColors.success : Colors.grey),
          const SizedBox(width: 6),
          Expanded(child: Text(domain,
              style: TextStyle(fontSize: 11,
                  color: _onPayment ? AppColors.success : Colors.grey),
              overflow: TextOverflow.ellipsis)),
        ]),
      ),
      // Payment warning
      if (_onPayment)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: AppColors.warning.withOpacity(0.12),
          child: const Row(children: [
            Icon(Icons.lock, size: 13, color: AppColors.warning),
            SizedBox(width: 6),
            Expanded(child: Text(
              'Official payment page — RozgarX AI cannot see your payment.',
              style: TextStyle(fontSize: 11, color: AppColors.warning),
            )),
          ]),
        ),
      if (_loading) const LinearProgressIndicator(
          minHeight: 2, color: AppColors.primary),
      Expanded(child: WebViewWidget(controller: _ctrl)),
      // Bottom bar
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        color: Theme.of(context).cardTheme.color,
        child: Row(children: [
          IconButton(icon: const Icon(Icons.arrow_back_ios, size: 18),
              onPressed: () => _ctrl.goBack()),
          IconButton(icon: const Icon(Icons.refresh, size: 18),
              onPressed: () => _ctrl.reload()),
          const Spacer(),
          TextButton.icon(
            icon: const Icon(Icons.check_circle_outline, size: 16),
            label: const Text('Mark Applied', style: TextStyle(fontSize: 12)),
            onPressed: () => _markApplied(context),
          ),
        ]),
      ),
    ]);
  }

  void _markApplied(BuildContext context) {
    final appIdCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20,
            MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Track Your Application',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Save your application details.',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 16),
          TextField(
            controller: appIdCtrl,
            decoration: const InputDecoration(
              labelText: 'Application/Registration Number (optional)',
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () async {
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid != null) {
                await FirebaseFirestore.instance
                    .collection('users').doc(uid)
                    .collection('appliedJobs').doc(widget.jobId)
                    .set({
                  'jobId': widget.jobId,
                  'jobTitle': widget.jobTitle,
                  'organization': widget.organization,
                  'appliedDate': FieldValue.serverTimestamp(),
                  'applicationId': appIdCtrl.text.trim().isNotEmpty
                      ? appIdCtrl.text.trim() : null,
                  'applicationStatus': 'submitted',
                });
              }
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ Application tracked successfully'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Save Application Record'),
          )),
        ]),
      ),
    );
  }
}


// ── Unlock prompt for free users
class _UnlockPrompt extends StatelessWidget {
  final JobModel job;
  const _UnlockPrompt({required this.job});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Application Assistance')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Unlock Application Assistance',
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'Get AI eligibility check, document checklist, and guided '
          'application support for ${job.basicInfo.title}.',
          style: const TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 32),
        _UnlockOption(
          emoji: '🎬',
          title: 'Watch a Short Ad',
          subtitle: '24-hour free access',
          color: AppColors.primary,
          onTap: () async {
            final result = await context.push<bool>('/ad-unlock', extra: {
              'feature': 'apply_assistance',
              'jobTitle': job.basicInfo.title,
            });
            if (result == true && context.mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => ApplyAssistanceScreen(
                      job: job, hasAccess: true),
                ),
              );
            }
          },
        ),
        const SizedBox(height: 12),
        _UnlockOption(
          emoji: '⭐',
          title: 'Upgrade to Premium',
          subtitle: 'Unlimited access + zero ads',
          color: AppColors.warning,
          onTap: () => context.push('/premium'),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            '⚠️ RozgarX AI is an independent career assistance platform '
            'and is not affiliated with any government organization. '
            'Official fees are paid directly on the official website.',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ),
      ]),
    ),
  );
}

class _UnlockOption extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  const _UnlockOption({
    required this.emoji, required this.title,
    required this.subtitle, required this.color, required this.onTap,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: color.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(12),
        color: color.withOpacity(0.05),
      ),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 26)),
        const SizedBox(width: 14),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(
              fontWeight: FontWeight.w600, color: color, fontSize: 15)),
          Text(subtitle, style: TextStyle(
              color: Colors.grey.shade600, fontSize: 12)),
        ])),
        Icon(Icons.chevron_right, color: color),
      ]),
    ),
  );
}

class _StepBar extends StatelessWidget {
  final int step;
  const _StepBar({required this.step});
  @override
  Widget build(BuildContext context) {
    const labels = ['Eligibility', 'Documents', 'Apply'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: List.generate(3, (i) => Expanded(child: Row(children: [
          Container(
            width: 26, height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i <= step ? AppColors.primary : Colors.grey.shade200,
            ),
            child: Center(child: Text('${i + 1}', style: TextStyle(
                color: i <= step ? Colors.white : Colors.grey,
                fontSize: 11, fontWeight: FontWeight.w700))),
          ),
          const SizedBox(width: 4),
          Flexible(child: Text(labels[i], style: TextStyle(
              fontSize: 11,
              color: i <= step ? AppColors.primary : Colors.grey,
              fontWeight: i == step ? FontWeight.w600 : FontWeight.normal))),
          if (i < 2) Expanded(child: Container(height: 1, margin:
              const EdgeInsets.symmetric(horizontal: 4),
              color: i < step ? AppColors.primary : Colors.grey.shade200)),
        ]))),
      ),
    );
  }
}
