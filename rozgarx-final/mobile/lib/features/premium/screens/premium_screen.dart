// lib/features/premium/screens/premium_screen.dart
// ============================================================
// RozgarX AI — Premium Subscription Screen
//
// Clean, minimal design. Shows plan benefits clearly.
// Google Play Billing for Android purchases.
// Handles: purchase, restore, error states.
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/premium_lock_widget.dart';

// Google Play product IDs — must match Play Console exactly
const kMonthlyProductId   = 'rozgarx_premium_monthly';
const kQuarterlyProductId = 'rozgarx_premium_quarterly';
const kYearlyProductId    = 'rozgarx_premium_yearly';

const kAllProductIds = {
  kMonthlyProductId,
  kQuarterlyProductId,
  kYearlyProductId,
};

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  final _iap = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _purchaseSub;

  List<ProductDetails> _products = [];
  String? _selectedPlanId;
  bool _isLoading = true;
  bool _isPurchasing = false;
  String? _errorMessage;

  // Which plan tab is selected
  int _selectedPlanIndex = 2; // Default to yearly (best value)

  @override
  void initState() {
    super.initState();
    _initBilling();
  }

  @override
  void dispose() {
    _purchaseSub.cancel();
    super.dispose();
  }

  Future<void> _initBilling() async {
    final available = await _iap.isAvailable();
    if (!available) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'In-app purchases are not available on this device.';
      });
      return;
    }

    // Listen for purchase updates
    _purchaseSub = _iap.purchaseStream.listen(
      _handlePurchaseUpdate,
      onError: (err) {
        setState(() => _errorMessage = 'Billing error: ${err.toString()}');
      },
    );

    // Fetch product details from Play Store
    final response = await _iap.queryProductDetails(kAllProductIds);

    if (response.error != null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not load plans. Check your connection.';
      });
      return;
    }

    // Sort: monthly, quarterly, yearly
    final sorted = response.productDetails
      ..sort((a, b) => _planOrder(a.id).compareTo(_planOrder(b.id)));

    setState(() {
      _products = sorted;
      _isLoading = false;
    });
  }

  int _planOrder(String id) {
    if (id == kMonthlyProductId)   return 0;
    if (id == kQuarterlyProductId) return 1;
    if (id == kYearlyProductId)    return 2;
    return 3;
  }

  Future<void> _handlePurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.pending) {
        setState(() => _isPurchasing = true);
        continue;
      }

      if (purchase.status == PurchaseStatus.error) {
        setState(() {
          _isPurchasing = false;
          _errorMessage = purchase.error?.message ?? 'Purchase failed';
        });
        await _iap.completePurchase(purchase);
        continue;
      }

      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {

        // Verify server-side
        final verified = await _verifyPurchaseServerSide(purchase);

        if (verified) {
          await _iap.completePurchase(purchase);
          if (mounted) {
            _showSuccessDialog(purchase.status == PurchaseStatus.restored);
          }
        } else {
          setState(() {
            _isPurchasing = false;
            _errorMessage = 'Purchase verification failed. Contact support.';
          });
        }
      }

      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
    if (mounted) setState(() => _isPurchasing = false);
  }

  Future<bool> _verifyPurchaseServerSide(PurchaseDetails purchase) async {
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'asia-south1');
      final result = await functions
          .httpsCallable('verifyGooglePlayPurchase')
          .call({
        'purchaseToken': purchase.verificationData.serverVerificationData,
        'productId': purchase.productID,
        'orderId': purchase.purchaseID,
      });
      return result.data['success'] == true;
    } catch (e) {
      debugPrint('[Premium] Server verification failed: $e');
      return false;
    }
  }

  Future<void> _startPurchase(ProductDetails product) async {
    if (_isPurchasing) return;

    setState(() {
      _isPurchasing = true;
      _errorMessage = null;
    });

    final purchaseParam = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  Future<void> _restorePurchases() async {
    setState(() => _isPurchasing = true);
    await _iap.restorePurchases();
  }

  void _showSuccessDialog(bool isRestore) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('🎉 Welcome to Premium!'),
        content: Text(
          isRestore
            ? 'Your premium subscription has been restored successfully.'
            : 'Your subscription is now active. Enjoy unlimited AI-powered features!',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop(); // Back to previous screen
            },
            child: const Text('Let\'s Go'),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Go Premium'),
        actions: [
          TextButton(
            onPressed: _restorePurchases,
            child: const Text('Restore'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 24),
          _buildBenefitsList(),
          const SizedBox(height: 24),
          _buildPlanSelector(),
          const SizedBox(height: 20),
          if (_errorMessage != null) _buildError(),
          _buildPurchaseButton(),
          const SizedBox(height: 12),
          _buildDisclaimer(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.warning.withOpacity(0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text(
            '⭐ PREMIUM',
            style: TextStyle(
              color: AppColors.warning,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 1,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Unlock your full\npreparation power',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Join thousands of aspirants preparing smarter with AI.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondaryLight,
          ),
        ),
      ],
    );
  }

  Widget _buildBenefitsList() {
    final benefits = [
      ('🤖', 'Unlimited AI Study Plans',        'Personalized 30/60/90-day plans'),
      ('📊', 'Competition Analytics',            'Predicted cutoffs, difficulty scores'),
      ('🔔', 'Early Job Alerts',                'Get notified before others'),
      ('🎯', 'Advanced Job Filters',            'Filter by salary, difficulty, competition'),
      ('💰', 'AI Salary Comparison Tool',        'Know your market value'),
      ('📄', 'Resume Analyzer',                  'ATS score + improvement tips'),
      ('🚫', 'Zero Ads',                         'Completely ad-free experience'),
      ('🏆', 'Priority Recommendations',         'AI-ranked jobs for your profile'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Everything included', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        ...benefits.map((b) => _BenefitRow(emoji: b.$1, title: b.$2, subtitle: b.$3)),
      ],
    );
  }

  Widget _buildPlanSelector() {
    if (_products.isEmpty) {
      return _buildFallbackPricing();
    }

    final planLabels = ['Monthly', 'Quarterly', 'Yearly'];
    final savings = ['', 'Save 16%', 'Best Value — Save 33%'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Choose your plan', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        ...List.generate(_products.length, (i) {
          final product = _products[i];
          final isSelected = i == _selectedPlanIndex;
          return GestureDetector(
            onTap: () => setState(() => _selectedPlanIndex = i),
            child: _PlanCard(
              label: planLabels[i],
              price: product.price,
              savingsTag: savings[i],
              isSelected: isSelected,
              isPopular: i == 2,
            ),
          );
        }),
      ],
    );
  }

  // Shown when Play Store is unavailable (testing, sideload)
  Widget _buildFallbackPricing() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Choose your plan', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const _PlanCard(label: 'Monthly',   price: '₹99/month',  savingsTag: '',                isSelected: false, isPopular: false),
        const _PlanCard(label: 'Quarterly', price: '₹249/3 months', savingsTag: 'Save 16%',    isSelected: false, isPopular: false),
        const _PlanCard(label: 'Yearly',    price: '₹799/year',  savingsTag: 'Best Value — Save 33%', isSelected: true, isPopular: true),
      ],
    );
  }

  Widget _buildError() {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPurchaseButton() {
    final product = _products.isNotEmpty ? _products[_selectedPlanIndex] : null;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isPurchasing || product == null
            ? null
            : () => _startPurchase(product),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          backgroundColor: AppColors.primary,
        ),
        child: _isPurchasing
            ? const SizedBox(
                height: 20, width: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : Text(
                product != null
                    ? 'Subscribe for ${product.price}'
                    : 'Subscribe Now',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }

  Widget _buildDisclaimer() {
    return Text(
      'Subscription auto-renews. Cancel anytime from Google Play. '
      'Payment processed securely by Google Play.',
      style: Theme.of(context).textTheme.bodySmall,
      textAlign: TextAlign.center,
    );
  }
}


// ─────────────────────────────────────────────────────────────
// SUB-WIDGETS
// ─────────────────────────────────────────────────────────────

class _BenefitRow extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;

  const _BenefitRow({
    required this.emoji,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                Text(subtitle,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


class _PlanCard extends StatelessWidget {
  final String label;
  final String price;
  final String savingsTag;
  final bool isSelected;
  final bool isPopular;

  const _PlanCard({
    required this.label,
    required this.price,
    required this.savingsTag,
    required this.isSelected,
    required this.isPopular,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.primary.withOpacity(0.08)
            : Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? AppColors.primary : Colors.grey.shade200,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Radio<bool>(
            value: true,
            groupValue: isSelected,
            activeColor: AppColors.primary,
            onChanged: (_) {},
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                Text(price,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              ],
            ),
          ),
          if (savingsTag.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isPopular
                    ? AppColors.success.withOpacity(0.12)
                    : AppColors.warning.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                savingsTag,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isPopular ? AppColors.success : AppColors.warning,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
