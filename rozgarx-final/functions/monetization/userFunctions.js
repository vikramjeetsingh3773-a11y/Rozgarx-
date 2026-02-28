/**
 * RozgarX AI — User System Cloud Functions
 * ============================================================
 * Handles:
 *   - Auto user document creation on first login
 *   - Role assignment via Custom Claims
 *   - AI eligibility check for job + user profile
 *   - Suspension/ban system
 *   - Admin user management
 *   - Applied jobs tracking
 * ============================================================
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { beforeUserSignedIn, beforeUserCreated } = require("firebase-functions/v2/identity");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");
const logger = require("firebase-functions/logger");

const db = getFirestore();


// ─────────────────────────────────────────────────────────────
// 1. AUTO USER DOCUMENT CREATION ON FIRST LOGIN
// ─────────────────────────────────────────────────────────────

// Triggered by Firebase Auth when new user is created
exports.onUserCreated = onDocumentCreated(
  // This runs when users/{userId} is first set — triggered by onAuthStateChanged
  // The actual trigger is via the beforeUserCreated blocking function below
  "userCreationQueue/{userId}",
  async (event) => {
    const { userId, email, displayName, provider } = event.data.data();

    const batch = db.batch();

    // ── Create user document
    const userRef = db.collection("users").doc(userId);
    batch.set(userRef, {
      uid: userId,
      email: email || null,
      displayName: displayName || null,
      photoURL: null,
      phoneNumber: null,
      createdAt: FieldValue.serverTimestamp(),
      lastLoginAt: FieldValue.serverTimestamp(),

      role: "user",

      profile: {
        educationLevel: null,
        targetExams: [],
        state: null,
        preferredLanguage: "en",
        preparationStage: "beginner",
        dailyStudyHours: 2,
        targetSalary: null,
        onboardingComplete: false,
        preferredStates: [],
      },

      preferences: {
        pushEnabled: true,
        notificationCategories: [],
        themeMode: "system",
        deadlineReminders: true,
      },

      subscription: {
        plan: "free",
        status: "free",
        startDate: null,
        expiryDate: null,
        platform: null,
        transactionId: null,
        purchaseToken: null,
        autoRenew: false,
        restoredAt: null,
      },

      usage: {
        aiRequestsToday: 0,
        adUnlocksToday: 0,
        lastResetDate: new Date().toISOString().split("T")[0],
        totalJobsViewed: 0,
        studyStreak: 0,
        lastStudyDate: null,
      },

      aiUsage: {
        aiLimit: 5, // Free tier
        queriesUsed: 0,
        lastQueryAt: null,
      },

      deviceInfo: {
        bandwidthCategory: "medium",
        platform: "android",
        detectedAt: null,
      },

      engagement: {
        studyStreak: 0,
        lastStudyDate: null,
        totalMockTestsTaken: 0,
        averageScore: 0,
      },

      isActive: true,
      isBanned: false,
      isSuspended: false,
      banReason: null,
      suspensionEnd: null,
      updatedAt: FieldValue.serverTimestamp(),
    });

    // ── Create AI usage document
    const aiUsageRef = db.collection("aiUsage").doc(userId);
    batch.set(aiUsageRef, {
      userId,
      date: new Date().toISOString().split("T")[0],
      queriesUsed: 0,
      queryLimit: 5,
      lastQueryAt: null,
    });

    await batch.commit();

    // Set default custom claims
    await getAuth().setCustomUserClaims(userId, { role: "user" });

    logger.info(`[UserCreated] New user: ${userId}`);
  }
);


// ─────────────────────────────────────────────────────────────
// 2. BLOCKING FUNCTION: Check suspension before sign-in
// ─────────────────────────────────────────────────────────────

exports.beforeSignIn = beforeUserSignedIn(async (event) => {
  const user = event.data;

  try {
    const userDoc = await db.collection("users").doc(user.uid).get();

    if (!userDoc.exists) {
      // New user — create their document
      await db.collection("userCreationQueue").doc(user.uid).set({
        userId: user.uid,
        email: user.email || null,
        displayName: user.displayName || null,
        provider: event.credential?.providerId || "password",
        createdAt: FieldValue.serverTimestamp(),
      });
      return; // Allow sign-in
    }

    const data = userDoc.data();

    // Block banned users
    if (data.isBanned) {
      throw new HttpsError("permission-denied",
        `Account permanently suspended. Reason: ${data.banReason || "Policy violation"}`);
    }

    // Check temporary suspension
    if (data.isSuspended) {
      const suspendEnd = data.suspensionEnd?.toDate();
      if (suspendEnd && suspendEnd > new Date()) {
        throw new HttpsError("permission-denied",
          `Account suspended until ${suspendEnd.toLocaleDateString("en-IN")}. ` +
          `Contact support if you believe this is an error.`);
      }
    }

    // Update last login
    await userDoc.ref.update({ lastLoginAt: FieldValue.serverTimestamp() });

    // Sync Custom Claims from Firestore (in case they drifted)
    const claims = {
      role: data.role || "user",
    };
    if (data.subscription?.status === "active" && data.subscription?.expiryDate?.toDate() > new Date()) {
      claims.subscriptionExpiry = data.subscription.expiryDate.toDate().getTime();
    }
    await getAuth().setCustomUserClaims(user.uid, claims);

  } catch (err) {
    if (err instanceof HttpsError) throw err;
    logger.error("[beforeSignIn] Error:", err);
    // Don't block sign-in for non-permission errors
  }
});


// ─────────────────────────────────────────────────────────────
// 3. UPDATE USER PROFILE
// ─────────────────────────────────────────────────────────────

exports.updateUserProfile = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Must be signed in");

  const userId = request.auth.uid;
  const { profile, preferences } = request.data;

  // Whitelist updatable fields (prevent injection)
  const allowedProfileFields = [
    "educationLevel", "targetExams", "state", "preferredLanguage",
    "preparationStage", "dailyStudyHours", "targetSalary",
    "onboardingComplete", "preferredStates", "strengthSubjects", "weakSubjects",
  ];

  const allowedPrefFields = [
    "pushEnabled", "notificationCategories", "themeMode",
    "deadlineReminders",
  ];

  const updates = {};

  if (profile) {
    for (const key of allowedProfileFields) {
      if (key in profile) {
        updates[`profile.${key}`] = profile[key];
      }
    }
  }

  if (preferences) {
    for (const key of allowedPrefFields) {
      if (key in preferences) {
        updates[`preferences.${key}`] = preferences[key];
      }
    }
  }

  if (Object.keys(updates).length === 0) {
    throw new HttpsError("invalid-argument", "No valid fields to update");
  }

  updates.updatedAt = FieldValue.serverTimestamp();

  await db.collection("users").doc(userId).update(updates);
  return { success: true };
});


// ─────────────────────────────────────────────────────────────
// 4. AI ELIGIBILITY CHECK
// ─────────────────────────────────────────────────────────────

exports.checkJobEligibility = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Must be signed in");

  const userId = request.auth.uid;
  const { jobId } = request.data;

  if (!jobId) throw new HttpsError("invalid-argument", "jobId required");

  // Fetch user profile + job details in parallel
  const [userDoc, jobDoc] = await Promise.all([
    db.collection("users").doc(userId).get(),
    db.collection("jobs").doc(jobId).get(),
  ]);

  if (!jobDoc.exists) throw new HttpsError("not-found", "Job not found");

  const user = userDoc.data() || {};
  const job = jobDoc.data();

  const profile = user.profile || {};
  const eligibility = job.eligibility || {};
  const ageCriteria = eligibility;

  const checks = [];
  let overallEligible = true;

  // ── Age check
  if (ageCriteria.ageMin || ageCriteria.ageMax) {
    // We don't store user age directly — prompt them if not set
    if (profile.age) {
      const ageOk = (!ageCriteria.ageMin || profile.age >= ageCriteria.ageMin) &&
                    (!ageCriteria.ageMax || profile.age <= ageCriteria.ageMax);
      checks.push({
        label: "Age Requirement",
        value: `${ageCriteria.ageMin || 18}–${ageCriteria.ageMax || 35} years`,
        passed: ageOk,
        note: ageOk ? null : "Age relaxation may apply for reserved categories",
      });
      if (!ageOk) overallEligible = false;
    } else {
      checks.push({
        label: "Age Requirement",
        value: `${ageCriteria.ageMin || 18}–${ageCriteria.ageMax || 35} years`,
        passed: null,
        note: "Update your profile with date of birth for accurate check",
      });
    }
  }

  // ── Education check
  const userEdu = profile.educationLevel;
  const requiredEdu = eligibility.educationRequired || [];
  if (requiredEdu.length > 0 && userEdu) {
    const eduLevels = ["10th", "12th", "graduate", "postgraduate"];
    const userEduIndex = eduLevels.indexOf(userEdu);
    const requiredEduLower = requiredEdu.map(e => e.toLowerCase());

    let eduOk = false;
    if (userEduIndex >= 3 && requiredEduLower.some(e => e.includes("graduate"))) eduOk = true;
    if (userEduIndex >= 2 && requiredEduLower.some(e => e.includes("graduate") && !e.includes("post"))) eduOk = true;
    if (userEduIndex >= 1 && requiredEduLower.some(e => e.includes("12") || e.includes("intermediate"))) eduOk = true;
    if (userEduIndex >= 0 && requiredEduLower.some(e => e.includes("10"))) eduOk = true;

    checks.push({
      label: "Educational Qualification",
      value: requiredEdu.join(" / "),
      passed: eduOk,
      note: null,
    });
    if (!eduOk) overallEligible = false;
  }

  // ── State check (for state-level jobs)
  if (job.basicInfo?.state && !job.basicInfo?.isNational) {
    const stateMatch = profile.state === job.basicInfo.state ||
        (profile.preferredStates || []).includes(job.basicInfo.state);
    checks.push({
      label: "State Domicile",
      value: job.basicInfo.state,
      passed: stateMatch,
      note: stateMatch ? null : "This job may require state domicile certificate",
    });
    // State mismatch is a warning, not a hard block
  }

  // ── Exam category interest
  const examCategory = job.basicInfo?.category;
  const userTargetExams = profile.targetExams || [];
  checks.push({
    label: "Category Match",
    value: examCategory,
    passed: userTargetExams.length === 0 || userTargetExams.includes(examCategory),
    note: null,
  });

  // ── Competition context
  const analytics = job.analytics || {};

  let verdict;
  if (overallEligible && checks.every(c => c.passed !== false)) {
    verdict = "✅ You appear eligible for this position";
  } else if (checks.some(c => c.passed === false)) {
    verdict = "⚠️ You may not meet all eligibility criteria";
  } else {
    verdict = "ℹ️ Verify eligibility criteria in the official notification";
  }

  return {
    isEligible: overallEligible,
    verdict,
    checks,
    competitionContext: {
      level: analytics.competitionLevel,
      score: analytics.competitionScore,
      difficultyTag: analytics.difficultyTag,
      estimatedApplicants: analytics.estimatedApplicants,
    },
    disclaimer: "This is an AI-powered estimate. Please verify all criteria in the official notification.",
  };
});


// ─────────────────────────────────────────────────────────────
// 5. TRACK APPLIED JOB (user-initiated)
// ─────────────────────────────────────────────────────────────

exports.trackAppliedJob = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Must be signed in");

  const userId = request.auth.uid;
  const { jobId, applicationId, setReminder } = request.data;

  if (!jobId) throw new HttpsError("invalid-argument", "jobId required");

  // Get job details for denormalization
  const jobDoc = await db.collection("jobs").doc(jobId).get();
  const job = jobDoc.exists ? jobDoc.data() : {};

  await db.collection("users").doc(userId)
    .collection("appliedJobs")
    .doc(jobId)
    .set({
      jobId,
      jobTitle: job.basicInfo?.title || "Unknown",
      organization: job.basicInfo?.organization || "Unknown",
      category: job.basicInfo?.category || "Unknown",
      appliedDate: FieldValue.serverTimestamp(),
      applicationId: applicationId || null,
      applicationStatus: "submitted",
      reminderSet: setReminder || false,
      examDate: job.importantDates?.examDate || null,
      admitCardDate: job.importantDates?.admitCardDate || null,
      updatedAt: FieldValue.serverTimestamp(),
    });

  return { success: true };
});


// ─────────────────────────────────────────────────────────────
// 6. ADMIN: SUSPEND USER
// ─────────────────────────────────────────────────────────────

exports.adminSuspendUser = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Must be signed in");

  const adminClaims = request.auth.token;
  if (!["admin", "superadmin"].includes(adminClaims.role)) {
    throw new HttpsError("permission-denied", "Admin access required");
  }

  const { targetUserId, suspensionDays, reason, permanent } = request.data;

  if (!targetUserId) throw new HttpsError("invalid-argument", "targetUserId required");

  const batch = db.batch();

  const suspendUntil = permanent ? null : new Date(Date.now() + suspensionDays * 86400000);

  batch.update(db.collection("users").doc(targetUserId), {
    isBanned: permanent || false,
    isSuspended: !permanent,
    suspensionEnd: suspendUntil ? Timestamp.fromDate(suspendUntil) : null,
    banReason: reason || null,
    updatedAt: FieldValue.serverTimestamp(),
  });

  // Audit log
  batch.set(db.collection("adminActions").doc(), {
    action: permanent ? "ban_user" : "suspend_user",
    adminId: request.auth.uid,
    targetUserId,
    reason: reason || null,
    suspensionDays: suspensionDays || null,
    permanent: permanent || false,
    timestamp: FieldValue.serverTimestamp(),
  });

  await batch.commit();

  // Revoke existing tokens (force logout)
  await getAuth().revokeRefreshTokens(targetUserId);

  logger.info(`[AdminSuspend] ${request.auth.uid} suspended ${targetUserId}`);
  return { success: true };
});


// ─────────────────────────────────────────────────────────────
// 7. ADMIN: UNSUSPEND USER
// ─────────────────────────────────────────────────────────────

exports.adminUnsuspendUser = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Must be signed in");

  const adminClaims = request.auth.token;
  if (!["admin", "superadmin"].includes(adminClaims.role)) {
    throw new HttpsError("permission-denied", "Admin access required");
  }

  const { targetUserId } = request.data;

  await db.collection("users").doc(targetUserId).update({
    isBanned: false,
    isSuspended: false,
    suspensionEnd: null,
    banReason: null,
    updatedAt: FieldValue.serverTimestamp(),
  });

  await db.collection("adminActions").add({
    action: "unsuspend_user",
    adminId: request.auth.uid,
    targetUserId,
    timestamp: FieldValue.serverTimestamp(),
  });

  return { success: true };
});


// ─────────────────────────────────────────────────────────────
// 8. DELETE ACCOUNT (GDPR compliance)
// ─────────────────────────────────────────────────────────────

exports.deleteAccount = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Must be signed in");

  const userId = request.auth.uid;

  // Queue for deletion (don't delete immediately — 30-day grace period)
  await db.collection("deletionQueue").doc(userId).set({
    userId,
    requestedAt: FieldValue.serverTimestamp(),
    executeAfter: Timestamp.fromDate(
      new Date(Date.now() + 30 * 86400000) // 30 days
    ),
    reason: "user_requested",
    status: "pending",
  });

  // Immediately revoke tokens
  await getAuth().revokeRefreshTokens(userId);

  return {
    success: true,
    message: "Your account has been queued for deletion. Data will be permanently deleted after 30 days. You can cancel by logging in again.",
    executeAfter: new Date(Date.now() + 30 * 86400000).toISOString(),
  };
});
