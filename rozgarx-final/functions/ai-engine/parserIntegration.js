/**
 * RozgarX AI — Cloud Functions Index (Updated)
 * 
 * This file integrates the AI Job Parsing Engine (jobParser.js)
 * into the main scraping pipeline.
 * 
 * Changed from previous version:
 *   - parseJobWithAI() now calls jobParser.parseJobNotification()
 *   - Full validation pipeline runs before any Firestore write
 *   - parsingLogs collection receives detailed parse records
 *   - Multiple posts handled automatically
 */

// Previous functions/index.js content remains — only the
// parseJobWithAI() function is replaced with this integration:

const { parseJobNotification } = require("./ai-engine/jobParser");

/**
 * REPLACE the existing parseJobWithAI() in functions/index.js with:
 */
async function parseJobWithAI(extractedText, sourceCategory, jobId, sourceId) {
  const result = await parseJobNotification(
    extractedText,
    sourceId,
    jobId,
    { category: sourceCategory }
  );

  if (!result.success) {
    return null; // Will be handled as manual_review
  }

  return result.data;
}


/**
 * REPLACE the existing storeJob() call in processSource() with:
 */
async function processAndStoreNotification(notif, source, urlHash, runId) {
  const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
  const db = getFirestore();

  // Create job document first to get jobId
  const jobRef = db.collection("jobs").doc();
  const jobId = jobRef.id;

  // Run AI parsing
  const parsed = await parseJobNotification(
    notif.extractedText || notif.title,
    source.sourceId,
    jobId,
    { sourceUrl: notif.url, category: source.category }
  );

  if (!parsed.success) {
    // Store as needs_review (already done inside parseJobNotification)
    return { stored: false, reason: "parsing_failed" };
  }

  const data = parsed.data;

  // Map parsed data to Firestore schema
  await jobRef.set({
    jobId,
    urlHash,
    titleHash: require("crypto").createHash("sha256")
      .update((data.jobInfo?.title || notif.title || "").toLowerCase())
      .digest("hex"),

    basicInfo: {
      title: data.jobInfo?.title || notif.title,
      organization: data.jobInfo?.organization || source.name,
      department: data.jobInfo?.department || null,
      category: data.jobInfo?.category || source.category,
      subCategory: data.jobInfo?.subCategory || null,
      state: data.jobInfo?.state || null,
      zone: null,
      vacancies: data.vacancies?.total || null,
      salary: data.salary?.rawText || null,
      jobType: "permanent",
      isNational: data.jobInfo?.isNational ?? true,
    },

    eligibility: {
      educationRequired: data.eligibility?.qualificationRequired
        ? [data.eligibility.qualificationRequired] : [],
      streamOrDiscipline: data.eligibility?.streamOrDiscipline || null,
      ageMin: data.ageCriteria?.minimumAge || null,
      ageMax: data.ageCriteria?.maximumAge || null,
      ageRelaxation: data.ageCriteria?.relaxation || null,
      physicalCriteria: null,
      experienceRequired: data.eligibility?.experienceRequired || null,
      minimumPercentage: data.eligibility?.minimumPercentage || null,
      nationality: "Indian",
    },

    importantDates: {
      notificationDate: data.jobInfo?.notificationDate
        ? Timestamp.fromDate(new Date(data.jobInfo.notificationDate)) : null,
      applicationStartDate: data.importantDates?.applicationStartDate
        ? Timestamp.fromDate(new Date(data.importantDates.applicationStartDate)) : null,
      lastDate: data.importantDates?.applicationLastDate
        ? Timestamp.fromDate(new Date(data.importantDates.applicationLastDate)) : null,
      examDate: data.importantDates?.examDate
        ? Timestamp.fromDate(new Date(data.importantDates.examDate)) : null,
      admitCardDate: data.importantDates?.admitCardDate
        ? Timestamp.fromDate(new Date(data.importantDates.admitCardDate)) : null,
      resultDate: data.importantDates?.resultDate
        ? Timestamp.fromDate(new Date(data.importantDates.resultDate)) : null,
    },

    applicationDetails: {
      applicationFee: buildFeeString(data.applicationFees),
      fees: data.applicationFees,
      applicationLink: data.jobInfo?.officialPDFLink || notif.url || null,
      officialWebsite: data.jobInfo?.officialWebsite || source.baseUrl,
      officialNotificationPDF: notif.pdfUrl || data.jobInfo?.officialPDFLink || null,
      selectionProcess: data.selectionProcess || [],
      applicationMode: data.jobInfo?.applicationMode || "Online",
    },

    vacancies: data.vacancies || {},
    syllabus: data.syllabus || [],
    examPattern: data.examPattern || {},
    requiredDocuments: data.requiredDocuments || [],

    // AI Insights (stored directly for performance)
    aiSummary: data.aiInsights?.shortSummary || null,

    metadata: {
      status: "pending",  // Admin must approve
      needsReview: false,
      isCorrigendum: data._meta?.isCorrigendum || false,
      hasMultiplePosts: data.multipleJobs || false,
      multiplePostsData: data._meta?.multipleJobsData || null,
      source: source.sourceId,
      sourceUrl: notif.url,
      advertisementNumber: data.jobInfo?.advertisementNumber || null,
      scrapedAt: FieldValue.serverTimestamp(),
      approvedAt: null,
      approvedBy: null,
      lastVerifiedAt: FieldValue.serverTimestamp(),
      parsingStatus: "success",
      parsingRunId: data._meta?.parsingRunId || null,
      tokensUsed: data._meta?.tokensUsed || null,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },

    // Analytics placeholder (filled by onJobApproved trigger)
    analytics: {
      competitionLevel: data.aiInsights?.competitionLevel || null,
      competitionScore: null,
      difficultyScore: data.aiInsights?.difficultyScore || null,
      difficultyTag: null,
      estimatedApplicants: null,
      predictedCutoffMin: null,
      predictedCutoffMax: null,
      analyticsGeneratedAt: null,
      coldStart: null,
    },
  });

  return { stored: true, jobId };
}


function buildFeeString(fees) {
  if (!fees) return null;
  const parts = [];
  if (fees.general) parts.push(`General: ₹${fees.general}`);
  if (fees.obc) parts.push(`OBC: ₹${fees.obc}`);
  if (fees.scSt) parts.push(`SC/ST: ₹${fees.scSt}`);
  if (fees.female) parts.push(`Female: ₹${fees.female}`);
  return parts.length > 0 ? parts.join(" | ") : null;
}

module.exports = { processAndStoreNotification };
