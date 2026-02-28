/**
 * RozgarX AI — Firebase Cloud Functions
 * Production-grade automation pipeline
 * ============================================================
 * Modules:
 *  1. Job Ingestion (Scheduled Cron)
 *  2. AI Analysis Trigger (Firestore onCreate)
 *  3. Job Archival (Scheduled Cron)
 *  4. AI Usage Rate Limiter
 *  5. Resume Analyzer Trigger
 *  6. Razorpay Webhook Handler
 *  7. Notification Dispatcher
 *  8. Leaderboard Updater
 *  9. Admin Analytics Aggregator
 * 10. AI Query Handler (HTTPS callable)
 * ============================================================
 */

const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { setGlobalOptions } = require("firebase-functions/v2");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");
const { getMessaging } = require("firebase-admin/messaging");
const crypto = require("crypto");
const logger = require("firebase-functions/logger");

initializeApp();
const db = getFirestore();
const storage = getStorage();

// Set global region (Mumbai for low-latency in India)
setGlobalOptions({ region: "asia-south1", maxInstances: 10 });


// ────────────────────────────────────────────────────────────
// HELPER: Log error to Firestore
// ────────────────────────────────────────────────────────────

async function logError(module, severity, message, context = {}, error = null) {
  try {
    await db.collection("errorLogs").add({
      module,
      severity,
      message,
      stack: error?.stack || null,
      context,
      resolvedAt: null,
      resolvedBy: null,
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (e) {
    logger.error("Failed to write error log:", e);
  }
}


// ────────────────────────────────────────────────────────────
// HELPER: Validate AI response JSON
// ────────────────────────────────────────────────────────────

function validateJobJSON(parsed) {
  const required = ["jobTitle", "organization", "category"];
  for (const field of required) {
    if (!parsed[field]) return false;
  }
  // Reject extra fields (prevent prompt injection)
  const allowed = [
    "jobTitle", "organization", "vacancies", "eligibility",
    "ageLimit", "applicationFee", "importantDates", "selectionProcess",
    "salary", "officialWebsite", "category", "state", "subCategory",
  ];
  for (const key of Object.keys(parsed)) {
    if (!allowed.includes(key)) return false;
  }
  return true;
}


// ────────────────────────────────────────────────────────────
// HELPER: Call OpenAI / Gemini AI
// ────────────────────────────────────────────────────────────

async function callAI(prompt, systemPrompt, maxTokens = 800) {
  const apiKey = process.env.OPENAI_API_KEY;
  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: "gpt-4o-mini",
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: prompt },
      ],
      max_tokens: maxTokens,
      temperature: 0.2, // Low temp for factual extraction
    }),
  });

  if (!response.ok) {
    throw new Error(`AI API error: ${response.status} ${response.statusText}`);
  }

  const data = await response.json();
  return data.choices[0].message.content;
}


// ────────────────────────────────────────────────────────────
// 1. SCHEDULED JOB INGESTION (every 6 hours)
// ────────────────────────────────────────────────────────────

exports.jobIngestionCron = onSchedule(
  {
    schedule: "0 */6 * * *",  // every 6 hours
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    const runId = `run_${Date.now()}`;
    logger.info(`[JobIngestion] Starting run: ${runId}`);

    // Fetch all active sources
    const sourcesSnap = await db
      .collection("sources")
      .where("status", "==", "active")
      .get();

    if (sourcesSnap.empty) {
      logger.warn("[JobIngestion] No active sources found.");
      return;
    }

    // Process each source independently (fail-safe)
    const tasks = sourcesSnap.docs.map((doc) =>
      processSource(doc.data(), runId).catch(async (err) => {
        logger.error(`[JobIngestion] Source failed: ${doc.id}`, err);
        await logError("scraper", "error", `Source processing failed: ${doc.id}`, { sourceId: doc.id, runId }, err);

        // Increment failure counter
        await db.collection("sources").doc(doc.id).update({
          consecutiveFailures: FieldValue.increment(1),
          lastCheckedAt: FieldValue.serverTimestamp(),
        });

        // If 3 consecutive failures → mark as failing, alert admin
        const sourceData = doc.data();
        if ((sourceData.consecutiveFailures || 0) >= 2) {
          await db.collection("sources").doc(doc.id).update({ status: "failing" });
          await logError("scraper", "critical", `Source failing after 3 attempts: ${doc.id}`, { sourceId: doc.id }, null);
        }
      })
    );

    await Promise.allSettled(tasks);
    logger.info(`[JobIngestion] Run complete: ${runId}`);
  }
);


async function processSource(source, runId) {
  const startTime = Date.now();
  let jobsFound = 0;
  let newJobsAdded = 0;
  let duplicatesSkipped = 0;
  let parsingFailed = 0;

  try {
    // Step 1: Fetch notifications page
    const { default: fetch } = await import("node-fetch");
    const userAgents = [
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
      "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36",
    ];
    const randomUA = userAgents[Math.floor(Math.random() * userAgents.length)];

    // Random delay 3-10 seconds to avoid detection
    const delay = 3000 + Math.random() * 7000;
    await new Promise((r) => setTimeout(r, delay));

    // Check robots.txt compliance
    if (source.disallowedPaths?.some((path) => source.notificationsUrl.includes(path))) {
      logger.warn(`[processSource] Skipping ${source.name} — robots.txt disallows path`);
      return;
    }

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 30000); // 30s timeout

    const response = await fetch(source.notificationsUrl, {
      headers: { "User-Agent": randomUA },
      signal: controller.signal,
    });
    clearTimeout(timeout);

    if (!response.ok) {
      // Detect blocking
      if (response.status === 403 || response.status === 429) {
        await db.collection("sources").doc(source.sourceId).update({
          status: "blocked",
          lastCheckedAt: FieldValue.serverTimestamp(),
        });
        throw new Error(`Source blocked: HTTP ${response.status}`);
      }
      throw new Error(`HTTP error: ${response.status}`);
    }

    const html = await response.text();

    // Step 2: Extract notifications using configured selectors
    // In production, use cheerio for HTML parsing
    // const $ = cheerio.load(html);
    // const notifications = extractNotifications($, source.scraperConfig.selectors);
    // For this scaffold, we mock the extraction logic:
    const notifications = extractNotifications(html, source);
    jobsFound = notifications.length;

    // Step 3: Process each notification
    for (const notif of notifications) {
      try {
        // Duplicate detection
        const urlHash = crypto.createHash("sha256").update(notif.url).digest("hex");
        const titleNormalized = notif.title.toLowerCase().replace(/\s+/g, " ").trim();

        const existing = await db.collection("jobs")
          .where("urlHash", "==", urlHash)
          .limit(1)
          .get();

        if (!existing.empty) {
          duplicatesSkipped++;
          continue;
        }

        // Step 4: Download and process PDF
        let extractedText = null;
        if (notif.pdfUrl) {
          extractedText = await downloadAndExtractPDF(notif.pdfUrl, source.sourceId);
        }

        // Step 5: AI parsing
        let parsedJob = null;
        if (extractedText) {
          parsedJob = await parseJobWithAI(extractedText, source.category);
        }

        if (!parsedJob) {
          parsingFailed++;
          // Store as needs_review for admin
          await storeRawJob(notif, source, urlHash, runId);
          continue;
        }

        // Step 6: Store structured job
        await storeJob(parsedJob, notif, source, urlHash, runId);
        newJobsAdded++;

      } catch (err) {
        parsingFailed++;
        logger.error(`[processSource] Notification failed: ${notif.title}`, err);
      }
    }

    // Log successful run
    await db.collection("scraperLogs").add({
      sourceId: source.sourceId,
      runId,
      status: "success",
      jobsFound,
      newJobsAdded,
      duplicatesSkipped,
      parsingFailed,
      durationMs: Date.now() - startTime,
      errorMessage: null,
      errorType: null,
      runAt: FieldValue.serverTimestamp(),
    });

    // Reset failure counter on success
    await db.collection("sources").doc(source.sourceId).update({
      consecutiveFailures: 0,
      lastSuccessAt: FieldValue.serverTimestamp(),
      lastCheckedAt: FieldValue.serverTimestamp(),
      avgResponseTimeMs: Date.now() - startTime,
    });

  } catch (err) {
    await db.collection("scraperLogs").add({
      sourceId: source.sourceId,
      runId,
      status: "failed",
      jobsFound,
      newJobsAdded,
      duplicatesSkipped,
      parsingFailed,
      durationMs: Date.now() - startTime,
      errorMessage: err.message,
      errorType: classifyError(err),
      runAt: FieldValue.serverTimestamp(),
    });
    throw err;
  }
}


function classifyError(err) {
  if (err.message.includes("blocked")) return "blocked";
  if (err.message.includes("timeout") || err.name === "AbortError") return "timeout";
  if (err.message.includes("structure")) return "structure_changed";
  if (err.message.includes("pdf")) return "pdf_error";
  return "unknown";
}


// Scaffold — replace with cheerio-based extraction in production
function extractNotifications(html, source) {
  // Placeholder: real implementation uses cheerio selectors from source.scraperConfig
  return [];
}


async function downloadAndExtractPDF(pdfUrl, sourceId) {
  try {
    const { default: fetch } = await import("node-fetch");
    const response = await fetch(pdfUrl, { timeout: 30000 });
    if (!response.ok) throw new Error(`PDF download failed: ${response.status}`);

    const buffer = await response.buffer();

    // Store temporarily in Firebase Storage
    const tempPath = `temp/${sourceId}/${Date.now()}.pdf`;
    const file = storage.bucket().file(tempPath);
    await file.save(buffer, { contentType: "application/pdf" });

    // Extract text — in production use pdfplumber via a Python Cloud Function
    // or pdf-parse npm package:
    // const pdfParse = require("pdf-parse");
    // const data = await pdfParse(buffer);
    // return data.text;

    // Clean up temp file after 24 hours (set lifecycle rule in storage)
    return null; // Replace with actual extracted text

  } catch (err) {
    logger.error("[downloadAndExtractPDF] Failed:", err);
    return null;
  }
}


async function parseJobWithAI(text, category) {
  const systemPrompt = `
You are a precise data extraction assistant for Indian government job notifications.
Extract structured job information and return ONLY valid JSON.
Do not add any explanation, markdown, or extra text.
If a field is not found, return null for that field.
Never hallucinate or assume data not present in the text.
`;

  const prompt = `
Extract the following fields from this government job notification text and return as JSON:
{
  "jobTitle": string | null,
  "organization": string | null,
  "vacancies": number | null,
  "eligibility": string | null,
  "ageLimit": string | null,
  "applicationFee": string | null,
  "importantDates": {
    "startDate": "YYYY-MM-DD" | null,
    "lastDate": "YYYY-MM-DD" | null,
    "examDate": "YYYY-MM-DD" | null
  },
  "selectionProcess": string | null,
  "salary": string | null,
  "officialWebsite": string | null,
  "category": "${category}",
  "state": string | null,
  "subCategory": string | null
}

Notification text:
${text.slice(0, 4000)}
`;

  let aiResponse = null;

  // Retry once on failure
  for (let attempt = 1; attempt <= 2; attempt++) {
    try {
      aiResponse = await callAI(prompt, systemPrompt);
      const cleaned = aiResponse.replace(/```json|```/g, "").trim();
      const parsed = JSON.parse(cleaned);

      if (!validateJobJSON(parsed)) {
        throw new Error("Invalid JSON structure from AI");
      }

      return parsed;

    } catch (err) {
      logger.warn(`[parseJobWithAI] Attempt ${attempt} failed:`, err.message);
      if (attempt === 2) {
        await logError("ai_parser", "error", "AI parsing failed after 2 attempts", { aiResponse }, err);
        return null;
      }
    }
  }
}


async function storeJob(parsed, notif, source, urlHash, runId) {
  const jobRef = db.collection("jobs").doc();

  await jobRef.set({
    jobId: jobRef.id,
    urlHash,
    titleHash: crypto.createHash("sha256")
      .update((parsed.jobTitle || "").toLowerCase().replace(/\s+/g, " "))
      .digest("hex"),

    basicInfo: {
      title: parsed.jobTitle || notif.title,
      organization: parsed.organization || source.name,
      department: null,
      category: parsed.category || source.category,
      subCategory: parsed.subCategory || null,
      state: parsed.state || null,
      zone: null,
      vacancies: parsed.vacancies || null,
      salary: parsed.salary || null,
      jobType: "permanent",
    },

    eligibility: {
      educationRequired: parsed.eligibility ? [parsed.eligibility] : [],
      ageMin: null,
      ageMax: null,
      ageRelaxation: parsed.ageLimit || null,
      physicalCriteria: null,
      experienceRequired: null,
      nationality: "Indian",
    },

    importantDates: {
      notificationDate: notif.publishDate ? Timestamp.fromDate(new Date(notif.publishDate)) : null,
      applicationStartDate: parsed.importantDates?.startDate
        ? Timestamp.fromDate(new Date(parsed.importantDates.startDate)) : null,
      lastDate: parsed.importantDates?.lastDate
        ? Timestamp.fromDate(new Date(parsed.importantDates.lastDate)) : null,
      examDate: parsed.importantDates?.examDate
        ? Timestamp.fromDate(new Date(parsed.importantDates.examDate)) : null,
      admitCardDate: null,
      resultDate: null,
    },

    applicationDetails: {
      applicationFee: parsed.applicationFee || null,
      applicationLink: notif.url || null,
      officialWebsite: parsed.officialWebsite || source.baseUrl,
      officialNotificationPDF: notif.pdfUrl || null,
      selectionProcess: parsed.selectionProcess ? [parsed.selectionProcess] : [],
      applicationMode: "online",
    },

    metadata: {
      status: "pending",        // Admin must approve
      needsReview: false,
      source: source.sourceId,
      sourceUrl: notif.url,
      scrapedAt: FieldValue.serverTimestamp(),
      approvedAt: null,
      approvedBy: null,
      lastVerifiedAt: FieldValue.serverTimestamp(),
      parsingStatus: "success",
      rawTextRef: null,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },

    analytics: {
      competitionLevel: null,
      competitionScore: null,
      estimatedApplicants: null,
      predictedCutoffMin: null,
      predictedCutoffMax: null,
      difficultyScore: null,
      difficultyTag: null,
      vacancyTrend: null,
      analyticsGeneratedAt: null,
      coldStart: null,
    },
  });
}


async function storeRawJob(notif, source, urlHash, runId) {
  const jobRef = db.collection("jobs").doc();
  await jobRef.set({
    jobId: jobRef.id,
    urlHash,
    basicInfo: { title: notif.title, organization: source.name, category: source.category },
    metadata: {
      status: "needs_review",
      needsReview: true,
      source: source.sourceId,
      sourceUrl: notif.url,
      scrapedAt: FieldValue.serverTimestamp(),
      parsingStatus: "failed",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
  });
}


// ────────────────────────────────────────────────────────────
// 2. AI ANALYTICS TRIGGER (on new approved job)
// ────────────────────────────────────────────────────────────

exports.onJobApproved = onDocumentCreated("jobs/{jobId}", async (event) => {
  const job = event.data.data();
  const jobId = event.params.jobId;

  // Only analyze approved jobs
  if (job.metadata?.status !== "approved") return;

  try {
    await runJobAnalytics(jobId, job);
  } catch (err) {
    logger.error(`[onJobApproved] Analytics failed for job: ${jobId}`, err);
    await logError("analytics", "error", "Job analytics failed", { jobId }, err);
  }
});


async function runJobAnalytics(jobId, job) {
  const category = job.basicInfo?.category;
  const vacancies = job.basicInfo?.vacancies;

  // Fetch historical data for this category
  const historicalSnap = await db.collection("jobAnalytics")
    .where("category", "==", category)
    .orderBy("generatedAt", "desc")
    .limit(10)
    .get();

  const coldStart = historicalSnap.size < 3;

  let defaults = null;
  if (coldStart) {
    const defaultsSnap = await db.collection("categoryDefaults").doc(category).get();
    defaults = defaultsSnap.exists ? defaultsSnap.data() : null;
  }

  const historicalData = historicalSnap.docs.map((d) => d.data());

  const systemPrompt = `
You are a data analyst for Indian government job recruitment.
Analyze competition and difficulty based on provided data.
Return ONLY valid JSON with these exact fields. No markdown.
`;

  const prompt = `
Analyze this government job and estimate competition metrics.

Job Details:
- Title: ${job.basicInfo?.title}
- Organization: ${job.basicInfo?.organization}
- Category: ${category}
- Vacancies: ${vacancies || "unknown"}

Historical data for this category (last 10 similar jobs):
${JSON.stringify(historicalData.slice(0, 5), null, 2)}

${coldStart ? "NOTE: Limited historical data. Use conservative category-level estimates." : ""}

Return JSON:
{
  "competitionLevel": "low" | "medium" | "high" | "extreme",
  "competitionScore": number (0-100),
  "estimatedApplicants": number | null,
  "predictedCutoffMin": number | null,
  "predictedCutoffMax": number | null,
  "difficultyScore": number (0-100),
  "difficultyTag": string,
  "vacancyTrend": "increasing" | "stable" | "decreasing" | null
}
`;

  const response = await callAI(prompt, systemPrompt);
  const cleaned = response.replace(/```json|```/g, "").trim();
  const analytics = JSON.parse(cleaned);

  // Write to jobAnalytics collection (never to client-writable paths)
  await db.collection("jobAnalytics").doc(jobId).set({
    jobId,
    category,
    ...analytics,
    coldStart,
    generatedAt: FieldValue.serverTimestamp(),
    modelVersion: "gpt-4o-mini-v1",
  });

  // Also update the analytics subfield in the jobs doc
  await db.collection("jobs").doc(jobId).update({
    "analytics.competitionLevel": analytics.competitionLevel,
    "analytics.competitionScore": analytics.competitionScore,
    "analytics.estimatedApplicants": analytics.estimatedApplicants,
    "analytics.predictedCutoffMin": analytics.predictedCutoffMin,
    "analytics.predictedCutoffMax": analytics.predictedCutoffMax,
    "analytics.difficultyScore": analytics.difficultyScore,
    "analytics.difficultyTag": analytics.difficultyTag,
    "analytics.vacancyTrend": analytics.vacancyTrend,
    "analytics.analyticsGeneratedAt": FieldValue.serverTimestamp(),
    "analytics.coldStart": coldStart,
  });

  // Trigger notification for relevant users
  await notifyRelevantUsers(jobId, job);
}


// ────────────────────────────────────────────────────────────
// 3. JOB ARCHIVAL CRON (daily at midnight)
// ────────────────────────────────────────────────────────────

exports.archiveExpiredJobs = onSchedule(
  { schedule: "0 0 * * *", timeoutSeconds: 300 },
  async () => {
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - 7); // lastDate + 7 days

    const expiredSnap = await db.collection("jobs")
      .where("metadata.status", "==", "approved")
      .where("importantDates.lastDate", "<", Timestamp.fromDate(cutoffDate))
      .limit(100) // batch
      .get();

    if (expiredSnap.empty) return;

    const batch = db.batch();

    for (const doc of expiredSnap.docs) {
      const data = doc.data();

      // Copy to archivedJobs
      const archiveRef = db.collection("archivedJobs").doc(doc.id);
      batch.set(archiveRef, {
        ...data,
        archivedAt: FieldValue.serverTimestamp(),
        archivedReason: "expired",
      });

      // Remove from active jobs
      batch.delete(doc.ref);
    }

    await batch.commit();
    logger.info(`[archiveExpiredJobs] Archived ${expiredSnap.size} jobs`);
  }
);


// ────────────────────────────────────────────────────────────
// 4. AI USAGE RATE LIMITER + DAILY RESET
// ────────────────────────────────────────────────────────────

exports.resetAIUsage = onSchedule(
  { schedule: "0 0 * * *" },
  async () => {
    // Reset daily AI query counts
    const snap = await db.collection("aiUsage").get();
    const batch = db.batch();
    const today = new Date().toISOString().split("T")[0];

    for (const doc of snap.docs) {
      batch.update(doc.ref, {
        queriesUsed: 0,
        date: today,
      });
    }

    await batch.commit();
    logger.info("[resetAIUsage] AI usage counters reset");
  }
);


// ────────────────────────────────────────────────────────────
// 5. AI QUERY HANDLER (HTTPS Callable — rate-limited)
// ────────────────────────────────────────────────────────────

exports.handleAIQuery = onCall(
  { timeoutSeconds: 60, memory: "256MiB" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }

    const userId = request.auth.uid;
    const { queryType, payload } = request.data;

    // Check rate limit
    const usageRef = db.collection("aiUsage").doc(userId);
    const usageDoc = await usageRef.get();

    const today = new Date().toISOString().split("T")[0];
    const usage = usageDoc.exists ? usageDoc.data() : { queriesUsed: 0, queryLimit: 5, date: today };

    if (usage.date !== today) {
      // New day — reset counter
      await usageRef.set({ userId, queriesUsed: 0, queryLimit: usage.queryLimit, date: today, lastQueryAt: null });
      usage.queriesUsed = 0;
    }

    if (usage.queriesUsed >= usage.queryLimit) {
      throw new HttpsError("resource-exhausted", "Daily AI query limit reached. Upgrade to Premium for unlimited access.");
    }

    // Process query
    let result = null;
    try {
      if (queryType === "study_plan") {
        result = await generateStudyPlan(payload);
      } else if (queryType === "exam_recommendation") {
        result = await generateExamRecommendations(payload);
      } else if (queryType === "competition_analysis") {
        result = await getCompetitionAnalysis(payload.jobId, userId);
      } else {
        throw new HttpsError("invalid-argument", "Unknown query type");
      }

      // Increment usage counter
      await usageRef.update({
        queriesUsed: FieldValue.increment(1),
        lastQueryAt: FieldValue.serverTimestamp(),
      });

      return { success: true, data: result };

    } catch (err) {
      if (err instanceof HttpsError) throw err;
      logger.error("[handleAIQuery] Error:", err);
      throw new HttpsError("internal", "AI query failed. Please try again.");
    }
  }
);


async function generateStudyPlan(payload) {
  const { examTarget, planType, strengthSubjects, weakSubjects, dailyHours } = payload;

  const prompt = `
Generate a ${planType} study plan for ${examTarget} exam.
Student profile:
- Daily study hours: ${dailyHours}
- Strong subjects: ${strengthSubjects.join(", ")}
- Weak subjects: ${weakSubjects.join(", ")}

Return a structured JSON study plan with:
{
  "planType": "${planType}",
  "examTarget": "${examTarget}",
  "weeklyBreakdown": [
    {
      "week": number,
      "focus": string,
      "topics": string[],
      "mockTestDay": "Saturday" | "Sunday" | null,
      "revisionDay": string
    }
  ],
  "dailyHours": number,
  "totalTopics": number
}
`;

  const systemPrompt = "You are an expert Indian competitive exam coach. Return only valid JSON.";
  const response = await callAI(prompt, systemPrompt, 1200);
  return JSON.parse(response.replace(/```json|```/g, "").trim());
}


async function generateExamRecommendations(payload) {
  const { educationLevel, state, dailyHours, preparationStage } = payload;

  const prompt = `
Recommend the best government exams for this Indian job aspirant:
- Education: ${educationLevel}
- State: ${state}
- Daily study hours: ${dailyHours}
- Stage: ${preparationStage}

Return JSON:
{
  "recommendedExams": [
    {
      "examName": string,
      "category": string,
      "successProbability": number (0-100),
      "reason": string,
      "preparationMonths": number
    }
  ]
}
`;

  const systemPrompt = "You are an Indian career counselor. Return only valid JSON.";
  const response = await callAI(prompt, systemPrompt, 800);
  return JSON.parse(response.replace(/```json|```/g, "").trim());
}


async function getCompetitionAnalysis(jobId, userId) {
  const [jobDoc, analyticsDoc] = await Promise.all([
    db.collection("jobs").doc(jobId).get(),
    db.collection("jobAnalytics").doc(jobId).get(),
  ]);

  if (!jobDoc.exists) throw new HttpsError("not-found", "Job not found");

  return {
    job: jobDoc.data()?.basicInfo,
    analytics: analyticsDoc.exists ? analyticsDoc.data() : null,
  };
}


// ────────────────────────────────────────────────────────────
// 6. RAZORPAY WEBHOOK HANDLER
// ────────────────────────────────────────────────────────────

exports.razorpayWebhook = onRequest(
  { timeoutSeconds: 30 },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method not allowed");
      return;
    }

    // Verify webhook signature
    const secret = process.env.RAZORPAY_WEBHOOK_SECRET;
    const signature = req.headers["x-razorpay-signature"];
    const body = JSON.stringify(req.body);

    const expectedSig = crypto
      .createHmac("sha256", secret)
      .update(body)
      .digest("hex");

    if (signature !== expectedSig) {
      logger.warn("[razorpayWebhook] Invalid signature");
      res.status(401).send("Invalid signature");
      return;
    }

    const event = req.body;

    try {
      if (event.event === "subscription.activated" || event.event === "payment.captured") {
        await handleSubscriptionActivated(event);
      } else if (event.event === "subscription.cancelled" || event.event === "subscription.expired") {
        await handleSubscriptionCancelled(event);
      }

      res.status(200).json({ received: true });

    } catch (err) {
      logger.error("[razorpayWebhook] Error:", err);
      await logError("subscription", "error", "Webhook processing failed", { event: event.event }, err);
      res.status(500).send("Webhook processing failed");
    }
  }
);


async function handleSubscriptionActivated(event) {
  const subscription = event.payload.subscription?.entity;
  if (!subscription) return;

  const userId = subscription.notes?.userId;
  if (!userId) {
    logger.error("[handleSubscriptionActivated] No userId in notes");
    return;
  }

  const endDate = new Date(subscription.current_end * 1000);

  // Atomic update using batch
  const batch = db.batch();

  // Update user role and subscription status
  batch.update(db.collection("users").doc(userId), {
    role: "premium",
    subscriptionStatus: "active",
    subscriptionExpiry: Timestamp.fromDate(endDate),
    subscriptionId: subscription.id,
    subscriptionPlan: subscription.plan_id,
    "aiProfile.aiQueryLimit": 9999,
  });

  // Store subscription record
  const subRef = db.collection("subscriptions").doc(subscription.id);
  batch.set(subRef, {
    subscriptionId: subscription.id,
    userId,
    plan: subscription.plan_id,
    status: "active",
    amount: subscription.quantity || 0,
    currency: "INR",
    startDate: Timestamp.fromMillis(subscription.current_start * 1000),
    endDate: Timestamp.fromDate(endDate),
    autoRenew: true,
    webhookValidated: true,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });

  // Update AI usage limit
  batch.set(db.collection("aiUsage").doc(userId), {
    queryLimit: 9999,
  }, { merge: true });

  await batch.commit();
  logger.info(`[handleSubscriptionActivated] User ${userId} upgraded to premium`);
}


async function handleSubscriptionCancelled(event) {
  const subscription = event.payload.subscription?.entity;
  const userId = subscription?.notes?.userId;
  if (!userId) return;

  await db.collection("users").doc(userId).update({
    role: "user",
    subscriptionStatus: "cancelled",
    subscriptionExpiry: null,
    "aiProfile.aiQueryLimit": 5,
  });

  await db.collection("subscriptions").doc(subscription.id).update({
    status: "cancelled",
    updatedAt: FieldValue.serverTimestamp(),
  });
}


// ────────────────────────────────────────────────────────────
// 7. NOTIFICATION DISPATCHER
// ────────────────────────────────────────────────────────────

async function notifyRelevantUsers(jobId, job) {
  const category = job.basicInfo?.category;

  // Find users who have this category in targetExams
  const usersSnap = await db.collection("users")
    .where("profile.targetExams", "array-contains", category)
    .where("isActive", "==", true)
    .limit(500) // Process in batches for scale
    .get();

  if (usersSnap.empty) return;

  const tokens = [];
  const notifications = [];

  for (const userDoc of usersSnap.docs) {
    const userData = userDoc.data();

    // Store in-app notification
    notifications.push(
      db.collection("users").doc(userDoc.id)
        .collection("notifications").add({
          type: "new_job",
          title: `New Job: ${job.basicInfo?.title}`,
          body: `${job.basicInfo?.organization} | Last Date: ${job.importantDates?.lastDate?.toDate().toLocaleDateString("en-IN") || "TBD"}`,
          jobId,
          read: false,
          createdAt: FieldValue.serverTimestamp(),
        })
    );

    // Collect FCM token for push notification
    const tokenDoc = await db.collection("fcmTokens").doc(userDoc.id).get();
    if (tokenDoc.exists && tokenDoc.data()?.tokens?.length > 0) {
      tokens.push(...tokenDoc.data().tokens);
    }
  }

  await Promise.allSettled(notifications);

  // Send FCM push notifications in batches of 500
  if (tokens.length > 0) {
    const messaging = getMessaging();
    const batches = [];
    for (let i = 0; i < tokens.length; i += 500) {
      batches.push(
        messaging.sendEachForMulticast({
          tokens: tokens.slice(i, i + 500),
          notification: {
            title: `🔔 New Job Alert: ${job.basicInfo?.title}`,
            body: `${job.basicInfo?.organization}`,
          },
          data: { jobId, type: "new_job" },
          android: { priority: "normal" }, // Battery-friendly for low-end devices
        })
      );
    }
    await Promise.allSettled(batches);
  }
}


// ────────────────────────────────────────────────────────────
// 8. AD UNLOCK HANDLER (server-side, abuse-prevention)
// ────────────────────────────────────────────────────────────

exports.processAdUnlock = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Must be signed in");

  const userId = request.auth.uid;
  const { jobId } = request.data;

  if (!jobId) throw new HttpsError("invalid-argument", "jobId required");

  // Check if already unlocked in last 24 hours
  const unlockRef = db.collection("users").doc(userId).collection("adUnlocks").doc(jobId);
  const existingUnlock = await unlockRef.get();

  if (existingUnlock.exists) {
    const expiresAt = existingUnlock.data().expiresAt.toDate();
    if (expiresAt > new Date()) {
      return { success: true, alreadyUnlocked: true, expiresAt: expiresAt.toISOString() };
    }
  }

  const now = new Date();
  const expiresAt = new Date(now.getTime() + 24 * 60 * 60 * 1000);

  await unlockRef.set({
    jobId,
    userId,
    unlockedAt: Timestamp.fromDate(now),
    expiresAt: Timestamp.fromDate(expiresAt),
  });

  return { success: true, alreadyUnlocked: false, expiresAt: expiresAt.toISOString() };
});


// ────────────────────────────────────────────────────────────
// 9. ADMIN ANALYTICS AGGREGATOR (daily)
// ────────────────────────────────────────────────────────────

exports.aggregateAdminAnalytics = onSchedule(
  { schedule: "0 1 * * *" }, // 1 AM daily
  async () => {
    const [usersSnap, jobsSnap, subsSnap] = await Promise.all([
      db.collection("users").count().get(),
      db.collection("jobs").where("metadata.status", "==", "approved").count().get(),
      db.collection("subscriptions").where("status", "==", "active").count().get(),
    ]);

    const premiumSnap = await db.collection("users")
      .where("role", "==", "premium").count().get();

    await db.collection("adminAnalytics").doc("overview").set({
      totalUsers: usersSnap.data().count,
      premiumUsers: premiumSnap.data().count,
      activeSubscriptions: subsSnap.data().count,
      totalJobs: jobsSnap.data().count,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });

    logger.info("[aggregateAdminAnalytics] Done");
  }
);


// ────────────────────────────────────────────────────────────
// 10. RESUME ANALYSIS TRIGGER
// ────────────────────────────────────────────────────────────

exports.onResumeUploaded = onDocumentCreated(
  "resumeAnalysis/{userId}/reports/{reportId}",
  async (event) => {
    const report = event.data.data();
    const { userId, reportId } = event.params;

    try {
      // In production: download PDF from Storage, extract text, call AI
      // const fileRef = storage.bucket().file(report.storageRef);
      // const [buffer] = await fileRef.download();
      // const text = await extractPDFText(buffer);
      // const analysis = await analyzeResumeWithAI(text);

      // Placeholder analysis
      const analysis = {
        atsScore: 72,
        skillMatchPercent: 65,
        missingKeywords: ["Node.js", "REST API", "Agile"],
        formattingIssues: ["Missing LinkedIn URL", "No quantified achievements"],
        suggestions: [
          "Add measurable outcomes to work experience",
          "Include a skills section with keywords",
          "Keep resume to 1 page for fresher profile",
        ],
      };

      await db.collection("resumeAnalysis").doc(userId)
        .collection("reports").doc(reportId).update({
          ...analysis,
          status: "complete",
          processedAt: FieldValue.serverTimestamp(),
        });

    } catch (err) {
      await db.collection("resumeAnalysis").doc(userId)
        .collection("reports").doc(reportId).update({
          status: "failed",
          processedAt: FieldValue.serverTimestamp(),
        });
      await logError("ai_parser", "error", "Resume analysis failed", { userId, reportId }, err);
    }
  }
);
