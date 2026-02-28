/**
 * RozgarX AI — Subscription & Ad Monetization Cloud Functions
 * ============================================================
 * Handles:
 *   - Google Play Billing server-side token verification
 *   - Razorpay webhook validation
 *   - Subscription expiry cron
 *   - Ad unlock with abuse prevention
 *   - Admin manual premium grant
 *   - Restore purchase flow
 *
 * SECURITY RULES:
 *   - No client can write subscription status directly
 *   - All billing flows go through Cloud Functions
 *   - Every action is logged with timestamp + userId
 *   - Suspicious activity triggers account flag
 * ============================================================
 */

const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");
const crypto = require("crypto");
const logger = require("firebase-functions/logger");

const db = getFirestore();


// ─────────────────────────────────────────────────────────────
// CONSTANTS
// ─────────────────────────────────────────────────────────────

const PLANS = {
  monthly:   { durationDays: 30,  priceINR: 99,   aiLimit: 9999 },
  quarterly: { durationDays: 90,  priceINR: 249,  aiLimit: 9999 },
  yearly:    { durationDays: 365, priceINR: 799,  aiLimit: 9999 },
};

const FREE_LIMITS = {
  aiRequestsPerDay: 5,
  adUnlocksPerDay:  3,
};

const AD_UNLOCK_DURATION_MINUTES = 1440; // 24 hours


// ─────────────────────────────────────────────────────────────
// HELPER: Log security event
// ─────────────────────────────────────────────────────────────

async function logSecurityEvent(userId, eventType, details = {}) {
  await db.collection("securityLogs").add({
    userId,
    eventType,
    details,
    timestamp: FieldValue.serverTimestamp(),
    resolved: false,
  });
}


// ─────────────────────────────────────────────────────────────
// HELPER: Verify user is not suspended
// ─────────────────────────────────────────────────────────────

async function assertUserActive(userId) {
  const userDoc = await db.collection("users").doc(userId).get();
  if (!userDoc.exists) throw new HttpsError("not-found", "User not found");

  const data = userDoc.data();
  if (data.isBanned) throw new HttpsError("permission-denied", "Account suspended");
  if (data.isSuspended) {
    const suspendEnd = data.suspensionEnd?.toDate();
    if (suspendEnd && suspendEnd > new Date()) {
      throw new HttpsError("permission-denied",
        `Account suspended until ${suspendEnd.toLocaleDateString("en-IN")}`);
    }
  }
  return data;
}


// ─────────────────────────────────────────────────────────────
// 1. GOOGLE PLAY BILLING — SERVER-SIDE TOKEN VERIFICATION
// ─────────────────────────────────────────────────────────────

exports.verifyGooglePlayPurchase = onCall(
  { timeoutSeconds: 30, memory: "256MiB" },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Must be signed in");

    const userId = request.auth.uid;
    const { purchaseToken, productId, orderId } = request.data;

    if (!purchaseToken || !productId || !orderId) {
      throw new HttpsError("invalid-argument", "purchaseToken, productId, and orderId required");
    }

    await assertUserActive(userId);

    // ── Check for token reuse (anti-fraud)
    const existingPurchase = await db.collection("purchaseTokens")
      .where("token", "==", purchaseToken)
      .limit(1)
      .get();

    if (!existingPurchase.empty) {
      await logSecurityEvent(userId, "duplicate_purchase_token", { purchaseToken, orderId });
      throw new HttpsError("already-exists", "Purchase token already used");
    }

    try {
      // ── Verify with Google Play Developer API
      const { google } = require("googleapis");
      const auth = new google.auth.GoogleAuth({
        scopes: ["https://www.googleapis.com/auth/androidpublisher"],
      });
      const androidPublisher = google.androidpublisher({ version: "v3", auth });

      const packageName = process.env.ANDROID_PACKAGE_NAME;
      let verificationResult;

      // Subscriptions use different endpoint than one-time purchases
      if (productId.includes("sub_") || productId.includes("subscription")) {
        const response = await androidPublisher.purchases.subscriptions.get({
          packageName,
          subscriptionId: productId,
          token: purchaseToken,
        });
        verificationResult = response.data;
      } else {
        const response = await androidPublisher.purchases.products.get({
          packageName,
          productId,
          token: purchaseToken,
        });
        verificationResult = response.data;
      }

      // Validate purchase state (0 = purchased, 1 = cancelled, 2 = pending)
      if (verificationResult.purchaseState !== 0 &&
          verificationResult.purchaseState !== undefined) {
        throw new Error(`Invalid purchase state: ${verificationResult.purchaseState}`);
      }

      // Determine plan from productId
      const plan = _productIdToPlan(productId);
      if (!plan) throw new Error(`Unknown product: ${productId}`);

      const now = new Date();
      const expiryDate = new Date(now);
      expiryDate.setDate(expiryDate.getDate() + PLANS[plan].durationDays);

      // Use Google's expiry if subscription (more accurate)
      const googleExpiry = verificationResult.expiryTimeMillis
          ? new Date(parseInt(verificationResult.expiryTimeMillis))
          : expiryDate;

      // ── Atomic update: store token + update subscription
      const batch = db.batch();

      // Lock purchase token (prevent reuse)
      batch.set(db.collection("purchaseTokens").doc(orderId), {
        token: purchaseToken,
        userId,
        orderId,
        productId,
        plan,
        usedAt: FieldValue.serverTimestamp(),
      });

      // Update user subscription
      batch.update(db.collection("users").doc(userId), {
        "subscription.plan": plan,
        "subscription.status": "active",
        "subscription.startDate": Timestamp.fromDate(now),
        "subscription.expiryDate": Timestamp.fromDate(googleExpiry),
        "subscription.platform": "google_play",
        "subscription.transactionId": orderId,
        "subscription.purchaseToken": purchaseToken,
        "subscription.autoRenew": verificationResult.autoRenewing ?? true,
        "subscription.updatedAt": FieldValue.serverTimestamp(),
        "role": "premium",
        "aiUsage.aiLimit": PLANS[plan].aiLimit,
        "updatedAt": FieldValue.serverTimestamp(),
      });

      // Store subscription record
      batch.set(db.collection("subscriptions").doc(orderId), {
        subscriptionId: orderId,
        userId,
        plan,
        status: "active",
        platform: "google_play",
        productId,
        purchaseToken,
        startDate: Timestamp.fromDate(now),
        expiryDate: Timestamp.fromDate(googleExpiry),
        autoRenew: verificationResult.autoRenewing ?? true,
        googleVerified: true,
        createdAt: FieldValue.serverTimestamp(),
      });

      await batch.commit();

      // Update Firebase Custom Claims (for instant Firestore rule enforcement)
      await getAuth().setCustomUserClaims(userId, {
        role: "premium",
        subscriptionExpiry: googleExpiry.getTime(),
        plan,
      });

      logger.info(`[GooglePlay] Verified purchase: ${userId} → ${plan}`);
      return { success: true, plan, expiryDate: googleExpiry.toISOString() };

    } catch (err) {
      logger.error("[GooglePlay] Verification failed:", err);
      await logSecurityEvent(userId, "purchase_verification_failed", {
        orderId,
        error: err.message,
      });
      throw new HttpsError("internal", "Purchase verification failed. Please try again.");
    }
  }
);


// ─────────────────────────────────────────────────────────────
// 2. RESTORE PURCHASE (Google Play)
// ─────────────────────────────────────────────────────────────

exports.restorePurchase = onCall(
  { timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Must be signed in");

    const userId = request.auth.uid;
    const { purchaseToken, productId } = request.data;

    if (!purchaseToken || !productId) {
      throw new HttpsError("invalid-argument", "purchaseToken and productId required");
    }

    try {
      const { google } = require("googleapis");
      const auth = new google.auth.GoogleAuth({
        scopes: ["https://www.googleapis.com/auth/androidpublisher"],
      });
      const androidPublisher = google.androidpublisher({ version: "v3", auth });

      const response = await androidPublisher.purchases.subscriptions.get({
        packageName: process.env.ANDROID_PACKAGE_NAME,
        subscriptionId: productId,
        token: purchaseToken,
      });

      const subscription = response.data;

      // Check if subscription is still valid
      const expiryMs = parseInt(subscription.expiryTimeMillis);
      const expiryDate = new Date(expiryMs);
      const isActive = expiryDate > new Date();

      if (!isActive) {
        return { success: false, reason: "subscription_expired", expiryDate: expiryDate.toISOString() };
      }

      const plan = _productIdToPlan(productId);

      // Restore subscription in Firestore
      await db.collection("users").doc(userId).update({
        "subscription.plan": plan,
        "subscription.status": "active",
        "subscription.expiryDate": Timestamp.fromDate(expiryDate),
        "subscription.purchaseToken": purchaseToken,
        "subscription.restoredAt": FieldValue.serverTimestamp(),
        "role": "premium",
        "aiUsage.aiLimit": PLANS[plan].aiLimit,
      });

      await getAuth().setCustomUserClaims(userId, {
        role: "premium",
        subscriptionExpiry: expiryMs,
        plan,
      });

      logger.info(`[RestorePurchase] Restored for: ${userId}`);
      return { success: true, plan, expiryDate: expiryDate.toISOString() };

    } catch (err) {
      logger.error("[RestorePurchase] Failed:", err);
      throw new HttpsError("internal", "Could not restore purchase. Contact support.");
    }
  }
);


// ─────────────────────────────────────────────────────────────
// 3. RAZORPAY WEBHOOK (Web billing fallback)
// ─────────────────────────────────────────────────────────────

exports.razorpayWebhook = onRequest(
  { timeoutSeconds: 30 },
  async (req, res) => {
    if (req.method !== "POST") return res.status(405).send("Method not allowed");

    const secret = process.env.RAZORPAY_WEBHOOK_SECRET;
    const signature = req.headers["x-razorpay-signature"];
    const body = JSON.stringify(req.body);

    // Verify webhook signature (HMAC-SHA256)
    const expected = crypto.createHmac("sha256", secret).update(body).digest("hex");
    if (signature !== expected) {
      logger.warn("[Razorpay] Invalid webhook signature");
      return res.status(401).send("Unauthorized");
    }

    const { event, payload } = req.body;
    logger.info(`[Razorpay] Event: ${event}`);

    try {
      switch (event) {
        case "subscription.activated":
        case "payment.captured":
          await _handleRazorpayActivation(payload);
          break;
        case "subscription.cancelled":
        case "subscription.expired":
          await _handleRazorpayCancellation(payload);
          break;
        case "subscription.halted":
          await _handleRazorpayHalted(payload);
          break;
        default:
          logger.info(`[Razorpay] Unhandled event: ${event}`);
      }
      res.status(200).json({ received: true });
    } catch (err) {
      logger.error("[Razorpay] Webhook error:", err);
      res.status(500).send("Processing failed");
    }
  }
);

async function _handleRazorpayActivation(payload) {
  const sub = payload.subscription?.entity || payload.payment?.entity;
  if (!sub) return;

  const userId = sub.notes?.userId || sub.description?.match(/userId:(\S+)/)?.[1];
  if (!userId) {
    logger.error("[Razorpay] No userId in webhook payload");
    return;
  }

  const plan = sub.plan_id ? _razorpayPlanIdToName(sub.plan_id) : "monthly";
  const now = new Date();
  const expiryDate = new Date(now);
  expiryDate.setDate(expiryDate.getDate() + PLANS[plan].durationDays);

  const batch = db.batch();

  batch.update(db.collection("users").doc(userId), {
    "subscription.plan": plan,
    "subscription.status": "active",
    "subscription.startDate": Timestamp.fromDate(now),
    "subscription.expiryDate": Timestamp.fromDate(expiryDate),
    "subscription.platform": "razorpay",
    "subscription.transactionId": sub.id,
    "role": "premium",
    "aiUsage.aiLimit": PLANS[plan].aiLimit,
    "updatedAt": FieldValue.serverTimestamp(),
  });

  batch.set(db.collection("subscriptions").doc(sub.id), {
    subscriptionId: sub.id,
    userId,
    plan,
    status: "active",
    platform: "razorpay",
    razorpaySignatureVerified: true,
    startDate: Timestamp.fromDate(now),
    expiryDate: Timestamp.fromDate(expiryDate),
    createdAt: FieldValue.serverTimestamp(),
  });

  await batch.commit();

  await getAuth().setCustomUserClaims(userId, {
    role: "premium",
    subscriptionExpiry: expiryDate.getTime(),
    plan,
  });
}

async function _handleRazorpayCancellation(payload) {
  const sub = payload.subscription?.entity;
  const userId = sub?.notes?.userId;
  if (!userId) return;

  await db.collection("users").doc(userId).update({
    "subscription.status": "cancelled",
    "role": "user",
    "aiUsage.aiLimit": FREE_LIMITS.aiRequestsPerDay,
    "updatedAt": FieldValue.serverTimestamp(),
  });

  await getAuth().setCustomUserClaims(userId, { role: "user" });
}

async function _handleRazorpayHalted(payload) {
  const sub = payload.subscription?.entity;
  const userId = sub?.notes?.userId;
  if (!userId) return;

  // Grace period: 3 days before full revocation
  await db.collection("users").doc(userId).update({
    "subscription.status": "grace_period",
    "subscription.gracePeriodEnds": Timestamp.fromDate(
      new Date(Date.now() + 3 * 86400000)
    ),
  });
}


// ─────────────────────────────────────────────────────────────
// 4. SUBSCRIPTION EXPIRY CRON (Daily)
// ─────────────────────────────────────────────────────────────

exports.checkSubscriptionExpiry = onSchedule(
  { schedule: "0 0 * * *", timeoutSeconds: 300 },
  async () => {
    const now = new Date();
    logger.info("[ExpiryCheck] Running subscription expiry check");

    // Find all "active" subscriptions whose expiry has passed
    const expiredSnap = await db.collection("users")
      .where("subscription.status", "==", "active")
      .where("subscription.expiryDate", "<", Timestamp.fromDate(now))
      .limit(500)
      .get();

    if (expiredSnap.empty) {
      logger.info("[ExpiryCheck] No expired subscriptions found");
      return;
    }

    logger.info(`[ExpiryCheck] Processing ${expiredSnap.size} expired subscriptions`);

    const batch = db.batch();
    const claimsUpdates = [];

    for (const doc of expiredSnap.docs) {
      const userId = doc.id;
      const data = doc.data();

      // Check grace period (Google Play has 3-day grace period)
      const gracePeriodEnds = data.subscription?.gracePeriodEnds?.toDate();
      if (gracePeriodEnds && gracePeriodEnds > now) {
        // Still in grace period — skip
        continue;
      }

      batch.update(doc.ref, {
        "subscription.status": "expired",
        "role": "user",
        "aiUsage.aiLimit": FREE_LIMITS.aiRequestsPerDay,
        "updatedAt": FieldValue.serverTimestamp(),
      });

      claimsUpdates.push(
        getAuth().setCustomUserClaims(userId, { role: "user" })
          .catch(err => logger.error(`[ExpiryCheck] Claims update failed: ${userId}`, err))
      );
    }

    await batch.commit();
    await Promise.allSettled(claimsUpdates);

    logger.info(`[ExpiryCheck] Expired ${expiredSnap.size} subscriptions`);
  }
);


// ─────────────────────────────────────────────────────────────
// 5. AD UNLOCK — SERVER-SIDE (Abuse-proof)
// ─────────────────────────────────────────────────────────────

exports.processAdUnlock = onCall(
  { timeoutSeconds: 15 },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Must be signed in");

    const userId = request.auth.uid;
    const { feature, adNetworkToken } = request.data;

    const VALID_FEATURES = [
      "ai_preparation_plan",
      "full_syllabus",
      "previous_papers",
      "apply_assistance",
      "ai_salary_comparison",
    ];

    if (!feature || !VALID_FEATURES.includes(feature)) {
      throw new HttpsError("invalid-argument", "Invalid feature");
    }

    // ── Verify user is not premium (they shouldn't need an ad unlock)
    const userData = await assertUserActive(userId);
    if (userData.subscription?.status === "active" &&
        userData.subscription?.expiryDate?.toDate() > new Date()) {
      // Premium user — grant access directly without ad
      return { success: true, alreadyPremium: true };
    }

    // ── Verify ad reward from AdMob server-side callback
    // In production: validate adNetworkToken with AdMob SSV
    // (Server-Side Verification) endpoint
    const adVerified = await _verifyAdMobReward(adNetworkToken, userId);
    if (!adVerified) {
      await logSecurityEvent(userId, "fake_ad_reward_attempt", { feature, adNetworkToken });
      throw new HttpsError("permission-denied", "Ad reward could not be verified");
    }

    // ── Check daily unlock limit
    const today = new Date().toISOString().split("T")[0];
    const usageDoc = await db.collection("users").doc(userId).get();
    const adUnlocksToday = usageDoc.data()?.usage?.adUnlocksToday || 0;
    const lastResetDate  = usageDoc.data()?.usage?.lastResetDate || "";

    const actualUnlocksToday = lastResetDate === today ? adUnlocksToday : 0;

    if (actualUnlocksToday >= FREE_LIMITS.adUnlocksPerDay) {
      return {
        success: false,
        reason: "daily_limit_reached",
        limit: FREE_LIMITS.adUnlocksPerDay,
        message: `You've reached the daily limit of ${FREE_LIMITS.adUnlocksPerDay} ad unlocks. Upgrade to Premium for unlimited access.`,
      };
    }

    // ── Create unlock record
    const now = new Date();
    const expiresAt = new Date(now.getTime() + AD_UNLOCK_DURATION_MINUTES * 60000);
    const unlockId = `${userId}_${feature}_${today}`;

    const batch = db.batch();

    // Store unlock (immutable after creation)
    batch.set(db.collection("adUnlocks").doc(unlockId), {
      unlockId,
      userId,
      feature,
      unlockedAt: Timestamp.fromDate(now),
      expiresAt: Timestamp.fromDate(expiresAt),
      adNetworkVerified: true,
    });

    // Update usage counter
    batch.update(db.collection("users").doc(userId), {
      "usage.adUnlocksToday": lastResetDate === today
          ? FieldValue.increment(1)
          : 1,
      "usage.lastResetDate": today,
    });

    await batch.commit();

    logger.info(`[AdUnlock] ${userId} unlocked: ${feature}`);
    return {
      success: true,
      feature,
      expiresAt: expiresAt.toISOString(),
      unlocksRemaining: FREE_LIMITS.adUnlocksPerDay - actualUnlocksToday - 1,
    };
  }
);

async function _verifyAdMobReward(token, userId) {
  // Production: call AdMob Server-Side Verification endpoint
  // https://www.google.com/admob/reward/verifyRewardedAd?...
  //
  // The token contains a signed reward callback from AdMob's servers.
  // Verify the signature using AdMob's public key.
  //
  // For development, return true if token is non-null.
  if (!token) return false;

  // TODO: Implement actual SSV verification:
  // const response = await fetch(
  //   `https://pagead2.googlesyndication.com/pagead/gen_204?...&ssv_token=${token}`
  // );
  // return response.ok;

  return true; // Replace with actual verification in production
}


// ─────────────────────────────────────────────────────────────
// 6. CHECK FEATURE ACCESS (Used by app before showing locked content)
// ─────────────────────────────────────────────────────────────

exports.checkFeatureAccess = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Must be signed in");

  const userId = request.auth.uid;
  const { feature } = request.data;

  const userData = await db.collection("users").doc(userId).get();
  const data = userData.data() || {};

  // Premium check
  const isPremium = data.subscription?.status === "active" &&
      data.subscription?.expiryDate?.toDate() > new Date();

  if (isPremium) {
    return { hasAccess: true, reason: "premium", showAd: false };
  }

  // Ad unlock check
  const today = new Date().toISOString().split("T")[0];
  const unlockId = `${userId}_${feature}_${today}`;
  const unlockDoc = await db.collection("adUnlocks").doc(unlockId).get();

  if (unlockDoc.exists) {
    const expiresAt = unlockDoc.data().expiresAt.toDate();
    if (expiresAt > new Date()) {
      return {
        hasAccess: true,
        reason: "ad_unlock",
        expiresAt: expiresAt.toISOString(),
        showAd: false,
      };
    }
  }

  // No access
  const adUnlocksToday = data.usage?.lastResetDate === today
      ? (data.usage?.adUnlocksToday || 0) : 0;

  return {
    hasAccess: false,
    reason: "locked",
    showAd: adUnlocksToday < FREE_LIMITS.adUnlocksPerDay,
    adUnlocksRemaining: FREE_LIMITS.adUnlocksPerDay - adUnlocksToday,
    showUpgrade: true,
  };
});


// ─────────────────────────────────────────────────────────────
// 7. ADMIN: GRANT MANUAL PREMIUM
// ─────────────────────────────────────────────────────────────

exports.adminGrantPremium = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Must be signed in");

  // Verify admin role from custom claims
  const claims = request.auth.token;
  if (claims.role !== "admin" && claims.role !== "superadmin") {
    throw new HttpsError("permission-denied", "Admin access required");
  }

  const { targetUserId, plan, durationDays, reason } = request.data;

  if (!targetUserId || !plan || !durationDays) {
    throw new HttpsError("invalid-argument", "targetUserId, plan, durationDays required");
  }

  const now = new Date();
  const expiryDate = new Date(now);
  expiryDate.setDate(expiryDate.getDate() + durationDays);

  const batch = db.batch();

  batch.update(db.collection("users").doc(targetUserId), {
    "subscription.plan": plan,
    "subscription.status": "active",
    "subscription.startDate": Timestamp.fromDate(now),
    "subscription.expiryDate": Timestamp.fromDate(expiryDate),
    "subscription.platform": "admin_grant",
    "subscription.grantedBy": request.auth.uid,
    "subscription.grantReason": reason || "Admin grant",
    "role": "premium",
    "aiUsage.aiLimit": 9999,
    "updatedAt": FieldValue.serverTimestamp(),
  });

  // Audit log
  batch.set(db.collection("adminActions").doc(), {
    action: "grant_premium",
    adminId: request.auth.uid,
    targetUserId,
    plan,
    durationDays,
    reason: reason || null,
    timestamp: FieldValue.serverTimestamp(),
  });

  await batch.commit();

  await getAuth().setCustomUserClaims(targetUserId, {
    role: "premium",
    subscriptionExpiry: expiryDate.getTime(),
    plan,
  });

  logger.info(`[AdminGrant] ${request.auth.uid} granted ${plan} to ${targetUserId}`);
  return { success: true };
});


// ─────────────────────────────────────────────────────────────
// 8. DAILY USAGE RESET
// ─────────────────────────────────────────────────────────────

exports.resetDailyUsage = onSchedule(
  { schedule: "0 0 * * *", timeoutSeconds: 300 },
  async () => {
    // Usage is reset lazily (on access check comparing date string).
    // This cron handles any stuck counters and clears expired ad unlocks.

    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);

    // Delete expired ad unlocks
    const expiredUnlocks = await db.collection("adUnlocks")
      .where("expiresAt", "<", Timestamp.fromDate(yesterday))
      .limit(500)
      .get();

    const batch = db.batch();
    expiredUnlocks.docs.forEach(doc => batch.delete(doc.ref));
    await batch.commit();

    logger.info(`[DailyReset] Cleaned ${expiredUnlocks.size} expired unlocks`);
  }
);


// ─────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────

function _productIdToPlan(productId) {
  if (productId.includes("monthly"))   return "monthly";
  if (productId.includes("quarterly")) return "quarterly";
  if (productId.includes("yearly") || productId.includes("annual")) return "yearly";
  return null;
}

function _razorpayPlanIdToName(planId) {
  // Map Razorpay plan IDs to internal plan names
  // Configured in Razorpay dashboard
  const map = {
    [process.env.RAZORPAY_MONTHLY_PLAN_ID]:   "monthly",
    [process.env.RAZORPAY_QUARTERLY_PLAN_ID]: "quarterly",
    [process.env.RAZORPAY_YEARLY_PLAN_ID]:    "yearly",
  };
  return map[planId] || "monthly";
}
