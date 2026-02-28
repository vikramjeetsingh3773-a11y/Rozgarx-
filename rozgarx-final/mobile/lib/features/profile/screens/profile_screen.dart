import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _userData;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users').doc(uid).get();
      if (mounted) setState(() { _userData = doc.data(); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Sign Out')),
        ],
      ),
    );
    if (confirmed == true) {
      await FirebaseAuth.instance.signOut();
      if (mounted) context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final subscription = _userData?['subscription'] ?? {};
    final profile = _userData?['profile'] ?? {};
    final isPremium = subscription['status'] == 'active';
    final expiryDate = subscription['expiryDate'] is Timestamp
        ? (subscription['expiryDate'] as Timestamp).toDate()
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _showEditDialog(context, profile),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  // User header
                  Container(
                    padding: const EdgeInsets.all(24),
                    child: Column(children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundColor: AppColors.primary,
                        child: Text(
                          (user?.displayName ?? user?.email ?? 'U')
                              .substring(0, 1).toUpperCase(),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 28,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        user?.displayName ?? 'Aspirant',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        user?.email ?? '',
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      // Premium/Free badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: isPremium
                              ? AppColors.warning.withOpacity(0.15)
                              : AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(
                            isPremium ? Icons.star : Icons.person_outline,
                            size: 14,
                            color: isPremium
                                ? AppColors.warning
                                : AppColors.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isPremium ? 'Premium Member' : 'Free Plan',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isPremium
                                  ? AppColors.warning
                                  : AppColors.primary,
                            ),
                          ),
                        ]),
                      ),
                    ]),
                  ),

                  // Subscription card
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: isPremium
                        ? _PremiumCard(
                            plan: subscription['plan'] ?? 'monthly',
                            expiryDate: expiryDate)
                        : _UpgradeCard(
                            onUpgrade: () => context.push('/premium')),
                  ),
                  const SizedBox(height: 8),

                  // Profile details
                  _SectionCard(
                    title: 'My Profile',
                    children: [
                      _ProfileRow('Education',
                          profile['educationLevel'] ?? 'Not set'),
                      _ProfileRow('Target Exams',
                          (profile['targetExams'] as List? ?? []).join(', ')
                              .isNotEmpty
                              ? (profile['targetExams'] as List).join(', ')
                              : 'Not set'),
                      _ProfileRow('State',
                          profile['state'] ?? 'Not set'),
                      _ProfileRow('Stage',
                          profile['preparationStage'] ?? 'Beginner'),
                    ],
                  ),

                  // Settings
                  _SectionCard(
                    title: 'Settings',
                    children: [
                      _SettingsTile(
                        icon: Icons.notifications_outlined,
                        title: 'Notification Preferences',
                        onTap: () => _showNotificationSettings(context),
                      ),
                      _SettingsTile(
                        icon: Icons.dark_mode_outlined,
                        title: 'Theme',
                        onTap: () => _showThemeSettings(context),
                      ),
                      _SettingsTile(
                        icon: Icons.restore_outlined,
                        title: 'Restore Purchase',
                        onTap: () => _restorePurchase(),
                      ),
                      _SettingsTile(
                        icon: Icons.privacy_tip_outlined,
                        title: 'Privacy Policy',
                        onTap: () {},
                      ),
                      _SettingsTile(
                        icon: Icons.description_outlined,
                        title: 'Terms & Conditions',
                        onTap: () {},
                      ),
                    ],
                  ),

                  // Saved & Applied Jobs
                  _SectionCard(
                    title: 'My Jobs',
                    children: [
                      _SettingsTile(
                        icon: Icons.bookmark_outlined,
                        title: 'Saved Jobs',
                        trailing: null,
                        onTap: () => _showSavedJobs(context),
                      ),
                      _SettingsTile(
                        icon: Icons.check_circle_outline,
                        title: 'Applied Jobs',
                        trailing: null,
                        onTap: () => _showAppliedJobs(context),
                      ),
                    ],
                  ),

                  // Danger zone
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.logout, size: 18,
                            color: AppColors.error),
                        label: const Text('Sign Out',
                            style: TextStyle(color: AppColors.error)),
                        onPressed: _signOut,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                              color: AppColors.error.withOpacity(0.4)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ),

                  // Legal disclaimer
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: Text(
                      'RozgarX AI is an independent career assistance platform '
                      'and is not affiliated with any government organization.',
                      style: TextStyle(
                          fontSize: 10, color: Colors.grey.shade400),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  void _showEditDialog(
      BuildContext context, Map<String, dynamic> profile) {
    final nameCtrl = TextEditingController(
        text: FirebaseAuth.instance.currentUser?.displayName ?? '');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Profile'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(labelText: 'Full Name'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await FirebaseAuth.instance.currentUser
                  ?.updateDisplayName(nameCtrl.text.trim());
              if (context.mounted) {
                Navigator.pop(context);
                _loadProfile();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showNotificationSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => const _NotificationSettingsSheet(),
    );
  }

  void _showThemeSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Theme', style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ...['System', 'Light', 'Dark'].map((t) => ListTile(
            title: Text(t),
            contentPadding: EdgeInsets.zero,
            onTap: () => Navigator.pop(context),
          )),
        ]),
      ),
    );
  }

  Future<void> _restorePurchase() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Checking for previous purchases...'),
          behavior: SnackBarBehavior.floating),
    );
    // Actual restore handled by InAppPurchase.instance.restorePurchases()
    // in premium_screen.dart
  }

  void _showSavedJobs(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        expand: false,
        builder: (_, ctrl) => Column(children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Saved Jobs', style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          Expanded(child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users').doc(uid)
                .collection('savedJobs')
                .orderBy('savedAt', descending: true)
                .snapshots(),
            builder: (_, snap) {
              if (!snap.hasData) return const Center(
                  child: CircularProgressIndicator());
              if (snap.data!.docs.isEmpty) return const Center(
                  child: Text('No saved jobs yet'));
              return ListView(controller: ctrl, children: snap.data!.docs
                  .map((d) => ListTile(
                title: Text(d['jobTitle'] ?? 'Job'),
                subtitle: Text(d['category'] ?? ''),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                onTap: () {
                  Navigator.pop(context);
                  context.push('/jobs/${d['jobId']}');
                },
              )).toList());
            },
          )),
        ]),
      ),
    );
  }

  void _showAppliedJobs(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        expand: false,
        builder: (_, ctrl) => Column(children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Applied Jobs', style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          Expanded(child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users').doc(uid)
                .collection('appliedJobs')
                .orderBy('appliedDate', descending: true)
                .snapshots(),
            builder: (_, snap) {
              if (!snap.hasData) return const Center(
                  child: CircularProgressIndicator());
              if (snap.data!.docs.isEmpty) return const Center(
                  child: Text('No applied jobs yet'));
              return ListView(controller: ctrl, children: snap.data!.docs
                  .map((d) => ListTile(
                title: Text(d['jobTitle'] ?? 'Job'),
                subtitle: Text(d['applicationId'] != null
                    ? 'App ID: ${d['applicationId']}'
                    : 'Applied'),
                trailing: const Icon(Icons.check_circle_outline,
                    color: AppColors.success, size: 20),
              )).toList());
            },
          )),
        ]),
      ),
    );
  }

  Future<void> _restorePurchases() async {}
}

// Sub-widgets

class _PremiumCard extends StatelessWidget {
  final String plan;
  final DateTime? expiryDate;
  const _PremiumCard({required this.plan, this.expiryDate});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF1A73E8), Color(0xFF0D47A1)],
      ),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(children: [
      const Text('⭐', style: TextStyle(fontSize: 28)),
      const SizedBox(width: 12),
      Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          '${plan[0].toUpperCase()}${plan.substring(1)} Premium',
          style: const TextStyle(color: Colors.white,
              fontWeight: FontWeight.w700, fontSize: 15),
        ),
        if (expiryDate != null)
          Text(
            'Valid until ${DateFormat('dd MMM yyyy').format(expiryDate!)}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
      ])),
    ]),
  );
}

class _UpgradeCard extends StatelessWidget {
  final VoidCallback onUpgrade;
  const _UpgradeCard({required this.onUpgrade});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.warning.withOpacity(0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.warning.withOpacity(0.3)),
    ),
    child: Row(children: [
      const Text('🔒', style: TextStyle(fontSize: 22)),
      const SizedBox(width: 10),
      Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Unlock Premium Features',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const Text('AI plans, analytics, zero ads',
            style: TextStyle(color: Colors.grey, fontSize: 12)),
      ])),
      ElevatedButton(
        onPressed: onUpgrade,
        style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.warning,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
        child: const Text('Upgrade', style: TextStyle(fontSize: 12)),
      ),
    ]),
  );
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.children});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(title, style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600,
            color: Colors.grey.shade500, letterSpacing: 0.5)),
      ),
      Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Column(children: children),
      ),
    ]),
  );
}

class _ProfileRow extends StatelessWidget {
  final String label;
  final String value;
  const _ProfileRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(children: [
      Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
      const Spacer(),
      Flexible(child: Text(value,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          textAlign: TextAlign.right)),
    ]),
  );
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;
  final VoidCallback onTap;
  const _SettingsTile({
    required this.icon, required this.title,
    this.trailing, required this.onTap,
  });
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, size: 20, color: Colors.grey.shade600),
    title: Text(title, style: const TextStyle(fontSize: 14)),
    trailing: trailing ?? const Icon(Icons.chevron_right, size: 18,
        color: Colors.grey),
    onTap: onTap,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    dense: true,
  );
}

class _NotificationSettingsSheet extends StatefulWidget {
  const _NotificationSettingsSheet();
  @override
  State<_NotificationSettingsSheet> createState() =>
      _NotificationSettingsSheetState();
}

class _NotificationSettingsSheetState
    extends State<_NotificationSettingsSheet> {
  bool _newJobs = true;
  bool _deadlines = true;
  bool _admitCards = true;
  bool _results = false;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('Notification Settings', style: TextStyle(
          fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      SwitchListTile(
        title: const Text('New Job Alerts'),
        value: _newJobs,
        onChanged: (v) => setState(() => _newJobs = v),
        activeColor: AppColors.primary,
        contentPadding: EdgeInsets.zero,
      ),
      SwitchListTile(
        title: const Text('Deadline Reminders'),
        value: _deadlines,
        onChanged: (v) => setState(() => _deadlines = v),
        activeColor: AppColors.primary,
        contentPadding: EdgeInsets.zero,
      ),
      SwitchListTile(
        title: const Text('Admit Card Alerts'),
        value: _admitCards,
        onChanged: (v) => setState(() => _admitCards = v),
        activeColor: AppColors.primary,
        contentPadding: EdgeInsets.zero,
      ),
      SwitchListTile(
        title: const Text('Result Notifications'),
        value: _results,
        onChanged: (v) => setState(() => _results = v),
        activeColor: AppColors.primary,
        contentPadding: EdgeInsets.zero,
      ),
      const SizedBox(height: 12),
      SizedBox(width: double.infinity, child: ElevatedButton(
        onPressed: () async {
          final uid = FirebaseAuth.instance.currentUser?.uid;
          if (uid != null) {
            await FirebaseFirestore.instance
                .collection('users').doc(uid)
                .update({
              'preferences.deadlineReminders': _deadlines,
              'preferences.pushEnabled': _newJobs,
            });
          }
          if (context.mounted) Navigator.pop(context);
        },
        child: const Text('Save'),
      )),
    ]),
  );
}
