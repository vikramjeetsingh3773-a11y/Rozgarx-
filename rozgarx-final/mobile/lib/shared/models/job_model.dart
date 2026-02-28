// lib/shared/models/job_model.dart
// ============================================================
// RozgarX AI — Job Model
// Firestore ↔ Flutter data model with offline Hive caching
// All fields use camelCase to match Firestore schema
// ============================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

part 'job_model.g.dart';

@HiveType(typeId: 0)
class JobModel extends HiveObject {

  @HiveField(0)
  final String jobId;

  @HiveField(1)
  final JobBasicInfo basicInfo;

  @HiveField(2)
  final JobEligibility eligibility;

  @HiveField(3)
  final JobImportantDates importantDates;

  @HiveField(4)
  final JobApplicationDetails applicationDetails;

  @HiveField(5)
  final JobAnalytics analytics;

  @HiveField(6)
  final JobMetadata metadata;

  @HiveField(7)
  final JobVacancies vacancies;

  @HiveField(8)
  final List<String> requiredDocuments;

  @HiveField(9)
  final List<SyllabusItem> syllabus;

  @HiveField(10)
  final ExamPattern? examPattern;

  @HiveField(11)
  final String? aiSummary;

  // Local-only fields (not in Firestore)
  @HiveField(12)
  bool isSaved;

  @HiveField(13)
  DateTime? lastViewedAt;

  const JobModel({
    required this.jobId,
    required this.basicInfo,
    required this.eligibility,
    required this.importantDates,
    required this.applicationDetails,
    required this.analytics,
    required this.metadata,
    required this.vacancies,
    this.requiredDocuments = const [],
    this.syllabus = const [],
    this.examPattern,
    this.aiSummary,
    this.isSaved = false,
    this.lastViewedAt,
  });

  // ── FROM FIRESTORE
  factory JobModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return JobModel(
      jobId: doc.id,
      basicInfo: JobBasicInfo.fromMap(data['basicInfo'] ?? {}),
      eligibility: JobEligibility.fromMap(data['eligibility'] ?? {}),
      importantDates: JobImportantDates.fromMap(data['importantDates'] ?? {}),
      applicationDetails: JobApplicationDetails.fromMap(data['applicationDetails'] ?? {}),
      analytics: JobAnalytics.fromMap(data['analytics'] ?? {}),
      metadata: JobMetadata.fromMap(data['metadata'] ?? {}),
      vacancies: JobVacancies.fromMap(data['vacancies'] ?? {}),
      requiredDocuments: List<String>.from(data['requiredDocuments'] ?? []),
      syllabus: (data['syllabus'] as List<dynamic>? ?? [])
          .map((e) => SyllabusItem.fromMap(e as Map<String, dynamic>))
          .toList(),
      examPattern: data['examPattern'] != null
          ? ExamPattern.fromMap(data['examPattern'])
          : null,
      aiSummary: data['aiSummary'],
    );
  }

  // ── COMPUTED PROPERTIES

  bool get isExpired {
    final lastDate = importantDates.lastDate;
    if (lastDate == null) return false;
    return lastDate.isBefore(DateTime.now());
  }

  int get daysRemaining {
    final lastDate = importantDates.lastDate;
    if (lastDate == null) return -1;
    return lastDate.difference(DateTime.now()).inDays;
  }

  bool get isDeadlineSoon => daysRemaining >= 0 && daysRemaining <= 7;

  String get salaryDisplay {
    final min = basicInfo.salaryMin;
    final max = basicInfo.salaryMax;
    if (min != null && max != null) {
      return '₹${_formatSalary(min)} – ₹${_formatSalary(max)}';
    }
    return basicInfo.salary ?? 'Not specified';
  }

  String _formatSalary(int amount) {
    if (amount >= 100000) {
      return '${(amount / 100000).toStringAsFixed(1)}L';
    } else if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(1)}K';
    }
    return amount.toString();
  }

  String get competitionBadge {
    switch (analytics.competitionLevel?.toLowerCase()) {
      case 'low':    return '🟢 Low Competition';
      case 'medium': return '🟡 Medium Competition';
      case 'high':   return '🔴 High Competition';
      case 'extreme':return '🔴 Extreme Competition';
      default:       return '⚪ Analyzing...';
    }
  }

  String get difficultyLabel {
    final score = analytics.difficultyScore ?? 0;
    if (score <= 3) return 'Easy';
    if (score <= 5) return 'Moderate';
    if (score <= 7) return 'Hard';
    return 'Very Hard';
  }

  JobModel copyWith({bool? isSaved, DateTime? lastViewedAt}) {
    return JobModel(
      jobId: jobId,
      basicInfo: basicInfo,
      eligibility: eligibility,
      importantDates: importantDates,
      applicationDetails: applicationDetails,
      analytics: analytics,
      metadata: metadata,
      vacancies: vacancies,
      requiredDocuments: requiredDocuments,
      syllabus: syllabus,
      examPattern: examPattern,
      aiSummary: aiSummary,
      isSaved: isSaved ?? this.isSaved,
      lastViewedAt: lastViewedAt ?? this.lastViewedAt,
    );
  }
}


// ─────────────────────────────────────────────────────────────
// SUB-MODELS
// ─────────────────────────────────────────────────────────────

@HiveType(typeId: 1)
class JobBasicInfo extends HiveObject {
  @HiveField(0) final String title;
  @HiveField(1) final String organization;
  @HiveField(2) final String? department;
  @HiveField(3) final String category;
  @HiveField(4) final String? subCategory;
  @HiveField(5) final String? state;
  @HiveField(6) final int? vacancies;
  @HiveField(7) final String? salary;
  @HiveField(8) final int? salaryMin;
  @HiveField(9) final int? salaryMax;
  @HiveField(10) final String? payLevel;
  @HiveField(11) final bool isNational;

  const JobBasicInfo({
    required this.title,
    required this.organization,
    required this.category,
    this.department,
    this.subCategory,
    this.state,
    this.vacancies,
    this.salary,
    this.salaryMin,
    this.salaryMax,
    this.payLevel,
    this.isNational = true,
  });

  factory JobBasicInfo.fromMap(Map<String, dynamic> map) => JobBasicInfo(
    title: map['title'] ?? 'Unknown Position',
    organization: map['organization'] ?? 'Unknown Organization',
    department: map['department'],
    category: map['category'] ?? 'Government',
    subCategory: map['subCategory'],
    state: map['state'],
    vacancies: map['vacancies'],
    salary: map['salary'],
    salaryMin: map['salaryMin'],
    salaryMax: map['salaryMax'],
    payLevel: map['payLevel'],
    isNational: map['isNational'] ?? true,
  );
}


@HiveType(typeId: 2)
class JobImportantDates extends HiveObject {
  @HiveField(0) final DateTime? applicationStartDate;
  @HiveField(1) final DateTime? lastDate;
  @HiveField(2) final DateTime? examDate;
  @HiveField(3) final DateTime? admitCardDate;
  @HiveField(4) final DateTime? resultDate;

  const JobImportantDates({
    this.applicationStartDate,
    this.lastDate,
    this.examDate,
    this.admitCardDate,
    this.resultDate,
  });

  factory JobImportantDates.fromMap(Map<String, dynamic> map) => JobImportantDates(
    applicationStartDate: _toDateTime(map['applicationStartDate']),
    lastDate: _toDateTime(map['lastDate']),
    examDate: _toDateTime(map['examDate']),
    admitCardDate: _toDateTime(map['admitCardDate']),
    resultDate: _toDateTime(map['resultDate']),
  );

  static DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}


@HiveType(typeId: 3)
class JobEligibility extends HiveObject {
  @HiveField(0) final List<String> educationRequired;
  @HiveField(1) final String? streamOrDiscipline;
  @HiveField(2) final int? ageMin;
  @HiveField(3) final int? ageMax;
  @HiveField(4) final Map<String, int?> ageRelaxation;
  @HiveField(5) final String? experienceRequired;

  const JobEligibility({
    this.educationRequired = const [],
    this.streamOrDiscipline,
    this.ageMin,
    this.ageMax,
    this.ageRelaxation = const {},
    this.experienceRequired,
  });

  factory JobEligibility.fromMap(Map<String, dynamic> map) {
    final relaxation = map['ageRelaxation'] as Map<String, dynamic>? ?? {};
    return JobEligibility(
      educationRequired: List<String>.from(map['educationRequired'] ?? []),
      streamOrDiscipline: map['streamOrDiscipline'],
      ageMin: map['ageMin'],
      ageMax: map['ageMax'],
      ageRelaxation: relaxation.map((k, v) => MapEntry(k, v as int?)),
      experienceRequired: map['experienceRequired'],
    );
  }
}


@HiveType(typeId: 4)
class JobApplicationDetails extends HiveObject {
  @HiveField(0) final String? applicationLink;
  @HiveField(1) final String? officialWebsite;
  @HiveField(2) final String? officialNotificationPDF;
  @HiveField(3) final String applicationMode;
  @HiveField(4) final String? applicationFee;
  @HiveField(5) final List<SelectionStage> selectionProcess;

  const JobApplicationDetails({
    this.applicationLink,
    this.officialWebsite,
    this.officialNotificationPDF,
    this.applicationMode = 'Online',
    this.applicationFee,
    this.selectionProcess = const [],
  });

  factory JobApplicationDetails.fromMap(Map<String, dynamic> map) => JobApplicationDetails(
    applicationLink: map['applicationLink'],
    officialWebsite: map['officialWebsite'],
    officialNotificationPDF: map['officialNotificationPDF'],
    applicationMode: map['applicationMode'] ?? 'Online',
    applicationFee: map['applicationFee'],
    selectionProcess: (map['selectionProcess'] as List<dynamic>? ?? [])
        .map((e) => SelectionStage.fromMap(e as Map<String, dynamic>))
        .toList(),
  );
}


@HiveType(typeId: 5)
class JobAnalytics extends HiveObject {
  @HiveField(0) final String? competitionLevel;
  @HiveField(1) final int? competitionScore;
  @HiveField(2) final int? difficultyScore;
  @HiveField(3) final String? difficultyTag;
  @HiveField(4) final int? estimatedApplicants;
  @HiveField(5) final int? predictedCutoffMin;
  @HiveField(6) final int? predictedCutoffMax;
  @HiveField(7) final bool coldStart;

  const JobAnalytics({
    this.competitionLevel,
    this.competitionScore,
    this.difficultyScore,
    this.difficultyTag,
    this.estimatedApplicants,
    this.predictedCutoffMin,
    this.predictedCutoffMax,
    this.coldStart = false,
  });

  factory JobAnalytics.fromMap(Map<String, dynamic> map) => JobAnalytics(
    competitionLevel: map['competitionLevel'],
    competitionScore: map['competitionScore'],
    difficultyScore: map['difficultyScore'],
    difficultyTag: map['difficultyTag'],
    estimatedApplicants: map['estimatedApplicants'],
    predictedCutoffMin: map['predictedCutoffMin'],
    predictedCutoffMax: map['predictedCutoffMax'],
    coldStart: map['coldStart'] ?? false,
  );
}


@HiveType(typeId: 6)
class JobVacancies extends HiveObject {
  @HiveField(0) final int? total;
  @HiveField(1) final int? general;
  @HiveField(2) final int? obc;
  @HiveField(3) final int? sc;
  @HiveField(4) final int? st;
  @HiveField(5) final int? ews;

  const JobVacancies({
    this.total, this.general, this.obc, this.sc, this.st, this.ews,
  });

  factory JobVacancies.fromMap(Map<String, dynamic> map) => JobVacancies(
    total: map['total'],
    general: map['general'],
    obc: map['obc'],
    sc: map['sc'],
    st: map['st'],
    ews: map['ews'],
  );
}


@HiveType(typeId: 7)
class JobMetadata extends HiveObject {
  @HiveField(0) final String status;
  @HiveField(1) final DateTime? createdAt;
  @HiveField(2) final DateTime? updatedAt;
  @HiveField(3) final String? source;
  @HiveField(4) final bool isCorrigendum;

  const JobMetadata({
    required this.status,
    this.createdAt,
    this.updatedAt,
    this.source,
    this.isCorrigendum = false,
  });

  factory JobMetadata.fromMap(Map<String, dynamic> map) => JobMetadata(
    status: map['status'] ?? 'approved',
    createdAt: _tsToDate(map['createdAt']),
    updatedAt: _tsToDate(map['updatedAt']),
    source: map['source'],
    isCorrigendum: map['isCorrigendum'] ?? false,
  );

  static DateTime? _tsToDate(dynamic v) =>
      v is Timestamp ? v.toDate() : null;
}


@HiveType(typeId: 8)
class SyllabusItem extends HiveObject {
  @HiveField(0) final String subject;
  @HiveField(1) final List<String> topics;

  const SyllabusItem({required this.subject, this.topics = const []});

  factory SyllabusItem.fromMap(Map<String, dynamic> map) => SyllabusItem(
    subject: map['subject'] ?? '',
    topics: List<String>.from(map['topics'] ?? []),
  );
}


@HiveType(typeId: 9)
class SelectionStage extends HiveObject {
  @HiveField(0) final int stage;
  @HiveField(1) final String name;
  @HiveField(2) final String? description;

  const SelectionStage({required this.stage, required this.name, this.description});

  factory SelectionStage.fromMap(Map<String, dynamic> map) => SelectionStage(
    stage: map['stage'] ?? 1,
    name: map['name'] ?? '',
    description: map['description'],
  );
}


@HiveType(typeId: 10)
class ExamPattern extends HiveObject {
  @HiveField(0) final int? totalQuestions;
  @HiveField(1) final int? totalMarks;
  @HiveField(2) final int? durationMinutes;
  @HiveField(3) final double? negativeMarking;
  @HiveField(4) final String? mode;

  const ExamPattern({
    this.totalQuestions,
    this.totalMarks,
    this.durationMinutes,
    this.negativeMarking,
    this.mode,
  });

  factory ExamPattern.fromMap(Map<String, dynamic> map) => ExamPattern(
    totalQuestions: map['totalQuestions'],
    totalMarks: map['totalMarks']?.toDouble().toInt(),
    durationMinutes: map['durationMinutes'],
    negativeMarking: map['negativeMarking']?.toDouble(),
    mode: map['mode'],
  );
}
