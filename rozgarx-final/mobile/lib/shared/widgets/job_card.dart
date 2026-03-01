import 'package:flutter/material.dart';
import '../../shared/models/job_model.dart';

class JobCard extends StatelessWidget {
  final JobModel job;
  final VoidCallback onTap;

  const JobCard({
    super.key,
    required this.job,
    required this.onTap,
  });

  Color get _categoryColor {
    switch (job.category.toLowerCase()) {
      case 'ssc': return const Color(0xFF1A73E8);
      case 'railway': return const Color(0xFF34A853);
      case 'banking': return const Color(0xFFF9AB00);
      case 'upsc': return const Color(0xFFEA4335);
      case 'police': return const Color(0xFF9C27B0);
      default: return const Color(0xFF1A73E8);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE8EAED)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _categoryColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        job.category.length > 4
                            ? job.category.substring(0, 4)
                            : job.category,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 8,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          job.title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF202124),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          job.organization,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF5F6368),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _Pill(
                    '👥 ${job.totalVacancies} posts',
                    Colors.blue.shade50,
                    const Color(0xFF1A73E8),
                  ),
                  if (job.salaryMax.isNotEmpty)
                    _Pill(
                      '₹ ${job.salaryMax}',
                      Colors.green.shade50,
                      const Color(0xFF34A853),
                    ),
                  _Pill(
                    '🌍 ${job.state}',
                    Colors.orange.shade50,
                    const Color(0xFFE65100),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _DeadlineBadge(job: job),
                  _CompetitionBadge(level: job.competitionLevel),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;

  const _Pill(this.text, this.bg, this.fg);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 9, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

class _DeadlineBadge extends StatelessWidget {
  final JobModel job;

  const _DeadlineBadge({required this.job});

  @override
  Widget build(BuildContext context) {
    if (job.applicationEnd == null) {
      return const Text('📅 No deadline',
          style: TextStyle(fontSize: 10, color: Color(0xFF9AA0A6)));
    }

    final days = job.daysRemaining;
    Color color;
    String text;
    String dot;

    if (days <= 3) {
      color = const Color(0xFFEA4335);
      dot = '🔴';
      text = days <= 0 ? 'Expired' : '$days days left!';
    } else if (days <= 7) {
      color = const Color(0xFFF9AB00);
      dot = '🟡';
      text = '$days days left';
    } else {
      color = const Color(0xFF9AA0A6);
      dot = '📅';
      text =
          '${job.applicationEnd!.day}/${job.applicationEnd!.month}/${job.applicationEnd!.year}';
    }

    return Text('$dot $text',
        style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w600, color: color));
  }
}

class _CompetitionBadge extends StatelessWidget {
  final String level;

  const _CompetitionBadge({required this.level});

  @override
  Widget build(BuildContext context) {
    Color color;
    String dot;

    switch (level.toLowerCase()) {
      case 'extreme':
        color = const Color(0xFFEA4335);
        dot = '🔴';
        break;
      case 'high':
        color = const Color(0xFFF9AB00);
        dot = '🟡';
        break;
      default:
        color = const Color(0xFF34A853);
        dot = '🟢';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$dot $level',
          style: TextStyle(
              fontSize: 9, fontWeight: FontWeight.w600, color: color)),
    );
  }
}
