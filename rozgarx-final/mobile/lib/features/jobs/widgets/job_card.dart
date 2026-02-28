// lib/features/jobs/widgets/job_card.dart
// ============================================================
// RozgarX AI — Job Card Widget
// Adaptive rendering: full animations on high-end,
// static lightweight version on low-end devices.
// Uses shimmer loading for perceived performance.
// ============================================================

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import '../../../shared/models/job_model.dart';
import '../../../core/cache/cache_service.dart';
import '../../../core/theme/app_theme.dart';

class JobCard extends StatelessWidget {
  final JobModel job;
  final VoidCallback? onTap;
  final VoidCallback? onSave;
  final bool isLowEnd;

  const JobCard({
    super.key,
    required this.job,
    this.onTap,
    this.onSave,
    this.isLowEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? AppColors.cardDark : AppColors.cardLight,
          borderRadius: BorderRadius.circular(12),
          // Low-end: no shadow (GPU intensive)
          boxShadow: isLowEnd ? null : [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── Row 1: Organization badge + Save button
              Row(
                children: [
                  _OrganizationBadge(
                    category: job.basicInfo.category,
                    organization: job.basicInfo.organization,
                  ),
                  const Spacer(),
                  _SaveButton(
                    isSaved: job.isSaved,
                    onTap: onSave,
                    isLowEnd: isLowEnd,
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // ── Row 2: Job title
              Text(
                job.basicInfo.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              const SizedBox(height: 6),

              // ── Row 3: Vacancies + Salary
              Row(
                children: [
                  if (job.basicInfo.vacancies != null) ...[
                    _InfoChip(
                      icon: Icons.people_outline,
                      label: '${_formatNumber(job.basicInfo.vacancies!)} Posts',
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (job.basicInfo.salaryMin != null) ...[
                    _InfoChip(
                      icon: Icons.currency_rupee,
                      label: job.salaryDisplay,
                      color: AppColors.success,
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 8),

              // ── Row 4: Competition badge + Difficulty
              Row(
                children: [
                  _CompetitionBadge(
                    level: job.analytics.competitionLevel,
                  ),
                  const SizedBox(width: 8),
                  if (job.analytics.difficultyScore != null)
                    _DifficultyBar(
                      score: job.analytics.difficultyScore!,
                      isLowEnd: isLowEnd,
                    ),
                ],
              ),

              const SizedBox(height: 10),

              // ── Row 5: Deadline indicator
              _DeadlineRow(job: job),

            ],
          ),
        ),
      ),
    );
  }

  String _formatNumber(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }
}


// ── Organization Badge
class _OrganizationBadge extends StatelessWidget {
  final String category;
  final String organization;

  const _OrganizationBadge({
    required this.category,
    required this.organization,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _categoryColor(category).withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        category,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _categoryColor(category),
        ),
      ),
    );
  }

  Color _categoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'ssc':     return const Color(0xFF1A73E8);
      case 'railway': return const Color(0xFF34A853);
      case 'banking': return const Color(0xFFFBBC04);
      case 'defence': return const Color(0xFFEA4335);
      case 'police':  return const Color(0xFF9C27B0);
      default:        return AppColors.primary;
    }
  }
}


// ── Save Button (animated on high-end, static on low-end)
class _SaveButton extends StatelessWidget {
  final bool isSaved;
  final VoidCallback? onTap;
  final bool isLowEnd;

  const _SaveButton({
    required this.isSaved,
    this.onTap,
    required this.isLowEnd,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: isLowEnd
          ? Icon(
              isSaved ? Icons.bookmark : Icons.bookmark_border,
              color: isSaved ? AppColors.primary : Colors.grey,
              size: 22,
            )
          : AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                isSaved ? Icons.bookmark : Icons.bookmark_border,
                key: ValueKey(isSaved),
                color: isSaved ? AppColors.primary : Colors.grey,
                size: 22,
              ),
            ),
    );
  }
}


// ── Info Chip
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}


// ── Competition Badge
class _CompetitionBadge extends StatelessWidget {
  final String? level;

  const _CompetitionBadge({this.level});

  @override
  Widget build(BuildContext context) {
    if (level == null) return const SizedBox.shrink();

    final config = _getConfig(level!.toLowerCase());
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            color: config['color'] as Color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '${config["label"]} Competition',
          style: TextStyle(
            fontSize: 11,
            color: (config['color'] as Color).withOpacity(0.85),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Map<String, dynamic> _getConfig(String level) {
    switch (level) {
      case 'low':     return {'color': AppColors.success, 'label': 'Low'};
      case 'medium':  return {'color': AppColors.warning, 'label': 'Medium'};
      case 'high':    return {'color': AppColors.error, 'label': 'High'};
      case 'extreme': return {'color': const Color(0xFF9C27B0), 'label': 'Extreme'};
      default:        return {'color': Colors.grey, 'label': 'Unknown'};
    }
  }
}


// ── Difficulty Bar (animated on high-end, static on low-end)
class _DifficultyBar extends StatelessWidget {
  final int score;
  final bool isLowEnd;

  const _DifficultyBar({required this.score, required this.isLowEnd});

  @override
  Widget build(BuildContext context) {
    final fraction = score / 10.0;
    final color = score <= 3
        ? AppColors.success
        : score <= 6 ? AppColors.warning : AppColors.error;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Difficulty: ',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        SizedBox(
          width: 60,
          height: 4,
          child: isLowEnd
              ? _StaticBar(fraction: fraction, color: color)
              : _AnimatedBar(fraction: fraction, color: color),
        ),
        const SizedBox(width: 4),
        Text(
          '$score/10',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _StaticBar extends StatelessWidget {
  final double fraction;
  final Color color;

  const _StaticBar({required this.fraction, required this.color});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: fraction,
        backgroundColor: Colors.grey.shade200,
        color: color,
        minHeight: 4,
      ),
    );
  }
}

class _AnimatedBar extends StatelessWidget {
  final double fraction;
  final Color color;

  const _AnimatedBar({required this.fraction, required this.color});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: fraction),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
      builder: (_, value, __) => ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: value,
          backgroundColor: Colors.grey.shade200,
          color: color,
          minHeight: 4,
        ),
      ),
    );
  }
}


// ── Deadline Row
class _DeadlineRow extends StatelessWidget {
  final JobModel job;

  const _DeadlineRow({required this.job});

  @override
  Widget build(BuildContext context) {
    final lastDate = job.importantDates.lastDate;
    if (lastDate == null) {
      return const SizedBox.shrink();
    }

    final days = job.daysRemaining;
    final formatted = DateFormat('dd MMM yyyy').format(lastDate);

    Color color;
    String label;

    if (days < 0) {
      color = Colors.grey;
      label = 'Expired';
    } else if (days == 0) {
      color = AppColors.error;
      label = 'Last Day!';
    } else if (days <= 3) {
      color = AppColors.error;
      label = '$days days left';
    } else if (days <= 7) {
      color = AppColors.warning;
      label = '$days days left';
    } else {
      color = Colors.grey.shade600;
      label = 'Apply by $formatted';
    }

    return Row(
      children: [
        Icon(
          days <= 7 && days >= 0
              ? Icons.timer_outlined
              : Icons.calendar_today_outlined,
          size: 13,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          days <= 7 && days >= 0 ? label : 'Apply by $formatted',
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: days <= 3 && days >= 0
                ? FontWeight.w600
                : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}


// ─────────────────────────────────────────────────────────────
// SHIMMER LOADING CARD (shown while jobs load)
// ─────────────────────────────────────────────────────────────

class JobCardShimmer extends StatelessWidget {
  const JobCardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Shimmer.fromColors(
      baseColor: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE0E0E0),
      highlightColor: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF5F5F5),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.cardDark : AppColors.cardLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Badge + save
            Row(
              children: [
                _shimmerBox(width: 60, height: 20, radius: 6),
                const Spacer(),
                _shimmerBox(width: 22, height: 22, radius: 4),
              ],
            ),
            const SizedBox(height: 10),
            _shimmerBox(width: double.infinity, height: 16, radius: 4),
            const SizedBox(height: 6),
            _shimmerBox(width: 200, height: 14, radius: 4),
            const SizedBox(height: 10),
            Row(
              children: [
                _shimmerBox(width: 90, height: 12, radius: 4),
                const SizedBox(width: 12),
                _shimmerBox(width: 110, height: 12, radius: 4),
              ],
            ),
            const SizedBox(height: 10),
            _shimmerBox(width: 150, height: 12, radius: 4),
          ],
        ),
      ),
    );
  }

  Widget _shimmerBox({
    required double width,
    required double height,
    required double radius,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
