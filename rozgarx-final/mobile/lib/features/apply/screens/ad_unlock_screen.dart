import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AdUnlockScreen extends StatelessWidget {
  final String feature;

  const AdUnlockScreen({
    super.key,
    required this.feature,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF202124)),
          onPressed: () => context.pop(),
        ),
        title: const Text('Unlock Access',
            style: TextStyle(
                color: Color(0xFF202124),
                fontSize: 16,
                fontWeight: FontWeight.w700)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🔓', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            const Text('Unlock Access',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF202124))),
            const SizedBox(height: 8),
            Text(
              'Watch a short ad to unlock $feature for 24 hours.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 14, color: Color(0xFF5F6368), height: 1.5),
            ),
            const SizedBox(height: 32),

            // Info card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F0FE),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFF1A73E8).withOpacity(0.2)),
              ),
              child: const Row(
                children: [
                  Text('⏱️', style: TextStyle(fontSize: 20)),
                  SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('24-hour free access',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A73E8))),
                      Text('Watch once, access all day',
                          style: TextStyle(
                              fontSize: 11, color: Color(0xFF5F6368))),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Watch Ad Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  // TODO: Show rewarded ad
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('AdMob not configured yet')),
                  );
                },
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('Watch Short Ad to Unlock',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A73E8),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

            const SizedBox(height: 12),
            const Text('— or —',
                style:
                    TextStyle(fontSize: 12, color: Color(0xFF9AA0A6))),
            const SizedBox(height: 12),

            // Upgrade Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.push('/premium'),
                icon: const Icon(Icons.star_outline,
                    color: Color(0xFFF9AB00)),
                label: const Text('Upgrade to Premium — No Ads Ever',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFF9AB00))),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  side: const BorderSide(
                      color: Color(0xFFF9AB00), width: 1.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

            const SizedBox(height: 20),
            const Text('You have 3 free unlocks remaining today',
                style:
                    TextStyle(fontSize: 11, color: Color(0xFF9AA0A6))),
          ],
        ),
      ),
    );
  }
}
