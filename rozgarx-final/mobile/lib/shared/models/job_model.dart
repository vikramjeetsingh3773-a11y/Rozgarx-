import 'package:cloud_firestore/cloud_firestore.dart';

class JobModel {
  final String id;
  final String title;
  final String organization;
  final String category;
  final int totalVacancies;
  final String salaryMin;
  final String salaryMax;
  final DateTime? applicationStart;
  final DateTime? applicationEnd;
  final String? examDate;
  final String eligibility;
  final String ageLimit;
  final double applicationFee;
  final String officialUrl;
  final String? pdfUrl;
  final String state;
  final String competitionLevel;
  final double difficultyScore;
  final bool isActive;
  final bool isSaved;
  final DateTime? lastViewedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const JobModel({
    required this.id,
    required this.title,
    required this.organization,
    required this.category,
    required this.totalVacancies,
    required this.salaryMin,
    required this.salaryMax,
    this.applicationStart,
    this.applicationEnd,
    this.examDate,
    required this.eligibility,
    required this.ageLimit,
    required this.applicationFee,
    required this.officialUrl,
    this.pdfUrl,
    required this.state,
    required this.competitionLevel,
    required this.difficultyScore,
    required this.isActive,
    this.isSaved = false,
    this.lastViewedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory JobModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return JobModel(
      id: doc.id,
      title: data['title'] ?? '',
      organization: data['organization'] ?? '',
      category: data['category'] ?? '',
      totalVacancies: data['totalVacancies'] ?? 0,
      salaryMin: data['salaryMin'] ?? '',
      salaryMax: data['salaryMax'] ?? '',
      applicationStart: (data['applicationStart'] as Timestamp?)?.toDate(),
      applicationEnd: (data['applicationEnd'] as Timestamp?)?.toDate(),
      examDate: data['examDate'],
      eligibility: data['eligibility'] ?? '',
      ageLimit: data['ageLimit'] ?? '',
      applicationFee: (data['applicationFee'] ?? 0).toDouble(),
      officialUrl: data['officialUrl'] ?? '',
      pdfUrl: data['pdfUrl'],
      state: data['state'] ?? 'All India',
      competitionLevel: data['competitionLevel'] ?? 'Medium',
      difficultyScore: (data['difficultyScore'] ?? 5.0).toDouble(),
      isActive: data['isActive'] ?? true,
      isSaved: data['isSaved'] ?? false,
      lastViewedAt: (data['lastViewedAt'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'organization': organization,
      'category': category,
      'totalVacancies': totalVacancies,
      'salaryMin': salaryMin,
      'salaryMax': salaryMax,
      'applicationStart': applicationStart != null
          ? Timestamp.fromDate(applicationStart!)
          : null,
      'applicationEnd': applicationEnd != null
          ? Timestamp.fromDate(applicationEnd!)
          : null,
      'examDate': examDate,
      'eligibility': eligibility,
      'ageLimit': ageLimit,
      'applicationFee': applicationFee,
      'officialUrl': officialUrl,
      'pdfUrl': pdfUrl,
      'state': state,
      'competitionLevel': competitionLevel,
      'difficultyScore': difficultyScore,
      'isActive': isActive,
      'isSaved': isSaved,
      'lastViewedAt': lastViewedAt != null
          ? Timestamp.fromDate(lastViewedAt!)
          : null,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  JobModel copyWith({
    String? id,
    String? title,
    String? organization,
    String? category,
    int? totalVacancies,
    String? salaryMin,
    String? salaryMax,
    DateTime? applicationStart,
    DateTime? applicationEnd,
    String? examDate,
    String? eligibility,
    String? ageLimit,
    double? applicationFee,
    String? officialUrl,
    String? pdfUrl,
    String? state,
    String? competitionLevel,
    double? difficultyScore,
    bool? isActive,
    bool? isSaved,
    DateTime? lastViewedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return JobModel(
      id: id ?? this.id,
      title: title ?? this.title,
      organization: organization ?? this.organization,
      category: category ?? this.category,
      totalVacancies: totalVacancies ?? this.totalVacancies,
      salaryMin: salaryMin ?? this.salaryMin,
      salaryMax: salaryMax ?? this.salaryMax,
      applicationStart: applicationStart ?? this.applicationStart,
      applicationEnd: applicationEnd ?? this.applicationEnd,
      examDate: examDate ?? this.examDate,
      eligibility: eligibility ?? this.eligibility,
      ageLimit: ageLimit ?? this.ageLimit,
      applicationFee: applicationFee ?? this.applicationFee,
      officialUrl: officialUrl ?? this.officialUrl,
      pdfUrl: pdfUrl ?? this.pdfUrl,
      state: state ?? this.state,
      competitionLevel: competitionLevel ?? this.competitionLevel,
      difficultyScore: difficultyScore ?? this.difficultyScore,
      isActive: isActive ?? this.isActive,
      isSaved: isSaved ?? this.isSaved,
      lastViewedAt: lastViewedAt ?? this.lastViewedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isClosingSoon {
    if (applicationEnd == null) return false;
    final daysLeft = applicationEnd!.difference(DateTime.now()).inDays;
    return daysLeft <= 3 && daysLeft >= 0;
  }

  bool get isExpired {
    if (applicationEnd == null) return false;
    return DateTime.now().isAfter(applicationEnd!);
  }

  int get daysRemaining {
    if (applicationEnd == null) return 0;
    return applicationEnd!.difference(DateTime.now()).inDays;
  }
}
