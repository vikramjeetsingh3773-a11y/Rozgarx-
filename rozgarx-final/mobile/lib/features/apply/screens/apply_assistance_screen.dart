import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';

class ApplyAssistanceScreen extends StatefulWidget {
  final String jobId;
  final String jobTitle;

  const ApplyAssistanceScreen({
    super.key,
    required this.jobId,
    required this.jobTitle,
  });

  @override
  State<ApplyAssistanceScreen> createState() =>
      _ApplyAssistanceScreenState();
}

class _ApplyAssistanceScreenState extends State<ApplyAssistanceScreen> {
  int _currentStep = 0;

  final List<String> _steps = ['Eligibility', 'Documents', 'Apply'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF202124)),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Apply: ${widget.jobTitle}',
          style: const TextStyle(
              color: Color(0xFF202124),
              fontSize: 13,
              fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Column(
        children: [
          // Step bar
          Container(
            color: Colors.white,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: List.generate(_steps.length, (i) {
                final isActive = i == _currentStep;
                final isDone = i < _currentStep;
                return Expanded(
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: isDone
                            ? const Color(0xFF34A853)
                            : isActive
                                ? const Color(0xFF1A73E8)
                                : const Color(0xFFE8EAED),
                        child: Text(
                          isDone ? '✓' : '${i + 1}',
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: isDone || isActive
                                  ? Colors.white
                                  : const Color(0xFF9AA0A6)),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _steps[i],
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: isActive
                                ? const Color(0xFF1A73E8)
                                : const Color(0xFF9AA0A6)),
                      ),
                      if (i < _steps.length - 1)
                        Expanded(
                          child: Container(
                            height: 1,
                            margin:
                                const EdgeInsets.symmetric(horizontal: 4),
                            color: isDone
                                ? const Color(0xFF34A853)
                                : const Color(0xFFE8EAED),
                          ),
                        ),
                    ],
                  ),
                );
              }),
            ),
          ),

          // Step Content
          Expanded(
            child: IndexedStack(
              index: _currentStep,
              children: [
                _EligibilityStep(jobTitle: widget.jobTitle),
                _DocumentsStep(),
                _ApplyStep(jobId: widget.jobId),
              ],
            ),
          ),

          // Navigation
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                if (_currentStep > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          setState(() => _currentStep--),
                      style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Back'),
                    ),
                  ),
                if (_currentStep > 0) const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _currentStep < 2
                        ? () => setState(() => _currentStep++)
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A73E8),
                      foregroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(
                      _currentStep < 2 ? 'Continue →' : 'Applied ✓',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EligibilityStep extends StatelessWidget {
  final String jobTitle;
  const _EligibilityStep({required this.jobTitle});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFE6F4EA),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFF34A853).withOpacity(0.3)),
            ),
            child: const Row(
              children: [
                Text('✅', style: TextStyle(fontSize: 20)),
                SizedBox(width: 10),
                Text('You appear eligible for this position',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF34A853))),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('Eligibility Breakdown',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF202124))),
          const SizedBox(height: 10),
          _EligibilityRow('✓', 'Age Requirement', '18–32 years',
              const Color(0xFF34A853)),
          _EligibilityRow('✓', 'Educational Qualification',
              'Graduation from recognized university',
              const Color(0xFF34A853)),
          _EligibilityRow('?', 'State Domicile',
              'All India — No restriction', const Color(0xFFF9AB00)),
        ],
      ),
    );
  }
}

class _EligibilityRow extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  final Color color;

  const _EligibilityRow(this.icon, this.title, this.subtitle, this.color);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: TextStyle(fontSize: 16, color: color)),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF202124))),
              Text(subtitle,
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF5F6368))),
            ],
          ),
        ],
      ),
    );
  }
}

class _DocumentsStep extends StatelessWidget {
  final List<String> _docs = [
    '📄 10th Marksheet',
    '📄 12th Marksheet',
    '🎓 Graduation Certificate',
    '🪪 Aadhaar Card',
    '📸 Passport Size Photo (white background)',
    '✍️ Signature (black ink on white paper)',
    '🏷️ Caste Certificate (if applicable)',
    '🏦 Bank Account Details',
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Required Documents',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF202124))),
          const SizedBox(height: 10),
          ..._docs.map((doc) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE8EAED)),
                ),
                child: Row(
                  children: [
                    Text(doc,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF202124))),
                  ],
                ),
              )),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '⚠️ Application fees must be paid on the official website. RozgarX AI does not collect any fees.',
              style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFFE65100),
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApplyStep extends StatefulWidget {
  final String jobId;
  const _ApplyStep({required this.jobId});

  @override
  State<_ApplyStep> createState() => _ApplyStepState();
}

class _ApplyStepState extends State<_ApplyStep> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _loading = true),
        onPageFinished: (_) => setState(() => _loading = false),
      ))
      ..loadRequest(Uri.parse('https://ssc.nic.in'));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_loading)
          const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}
