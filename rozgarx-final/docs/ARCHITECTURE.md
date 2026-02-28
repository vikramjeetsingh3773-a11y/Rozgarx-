# RozgarX AI — Architecture & Deployment Guide
================================================================
Version: 1.0 | Production-Grade | India-Optimized
================================================================


## FILE STRUCTURE

rozgarx-ai/
├── firebase.json              # Firebase hosting + emulator config
├── storage.rules              # Firebase Storage security rules
├── .env.example               # Environment variables template
│
├── firestore/
│   ├── firestore.rules        # Firestore security rules (role-based)
│   ├── firestore.indexes.json # All composite indexes
│   └── schema.yaml            # Complete data model documentation
│
├── functions/
│   ├── index.js               # All Cloud Functions
│   └── package.json           # (to be created)
│
└── frontend/
    └── src/                   # Next.js app (next prompt)


================================================================
## ARCHITECTURE DECISION RECORD
================================================================

DECISION: Firebase-only backend (no separate FastAPI server)
REASON: Eliminates VPS management, auto-scales, cost-efficient at 1M users.
TRADE-OFF: Heavy ML tasks (if added later) require separate Cloud Run service.

DECISION: Cloud Functions region = asia-south1 (Mumbai)
REASON: Lowest latency for Indian users (Tier 2/Tier 3 cities).

DECISION: Scraping as attempt-first, admin queue as fallback
REASON: Government sites are unreliable. System never blocks on scraper failure.

DECISION: AI analytics written by Cloud Functions only (never client)
REASON: Security rules enforce this. Prevents manipulation of competition scores.

DECISION: Firestore offline persistence enabled
REASON: Critical for slow 3G networks in Tier 2/Tier 3 India.

DECISION: Cold-start rule for AI analytics
REASON: On Day 1, no historical data exists. Prevents hallucination.
RULE: If category historical records < 3 → use categoryDefaults, set coldStart: true.


================================================================
## STACK DECISION: FIREBASE vs FASTAPI
================================================================

The system architecture prompt suggested FastAPI + PostgreSQL.
After analysis, Firebase-only is recommended because:

  Firebase Cloud Functions    vs    FastAPI on VPS
  ─────────────────────────────────────────────────
  Auto-scales to 1M users         Manual scaling needed
  No server management            DevOps overhead
  Pay per execution               Fixed monthly cost
  Native Firebase integration     Extra API layer
  Cold starts (manageable)        Always-on (costs more)

EXCEPTION: If ML cutoff prediction model is built later,
deploy as a separate Cloud Run (Python) service and call
from Cloud Functions. Do not run ML models in Node.js functions.


================================================================
## DEPLOYMENT CHECKLIST
================================================================

### Phase 1: Firebase Setup
[ ] Create Firebase project (Blaze plan required for Cloud Functions)
[ ] Enable Authentication (Email/Password + Google)
[ ] Enable Firestore (production mode)
[ ] Enable Storage
[ ] Enable Cloud Messaging (FCM)
[ ] Set region to asia-south1

### Phase 2: Security
[ ] Deploy firestore.rules
[ ] Deploy storage.rules
[ ] Deploy firestore.indexes.json
[ ] Set all secrets via firebase functions:secrets:set
[ ] Verify NO API keys in client-side code
[ ] Enable Firebase App Check (bot protection)

### Phase 3: Functions
[ ] Deploy Cloud Functions
[ ] Verify jobIngestionCron triggers correctly
[ ] Verify archiveExpiredJobs runs at midnight IST
[ ] Verify razorpayWebhook signature validation works
[ ] Test handleAIQuery rate limiting

### Phase 4: Data Initialization
[ ] Seed sources/{sourceId} collection with official job sites
[ ] Seed categoryDefaults/{category} with initial competition estimates
[ ] Create first admin user manually in Firestore
[ ] Set admin user role = "superadmin"

### Phase 5: Monitoring
[ ] Set up Firebase Alerts for function errors
[ ] Set up Cloud Function failure notifications
[ ] Verify scraperLogs are populating
[ ] Verify errorLogs collection works

### Phase 6: Frontend
[ ] Deploy Next.js to Firebase Hosting
[ ] Enable PWA (service worker)
[ ] Verify offline mode works
[ ] Test on low-end Android device (Chrome)
[ ] Test on slow 3G network (Chrome DevTools throttling)
[ ] Lighthouse score > 90 ✓
[ ] Verify dark/light mode toggle

### Phase 7: Payments
[ ] Create Razorpay account
[ ] Set up subscription plans in Razorpay dashboard
[ ] Configure webhook URL: https://[region]-[project].cloudfunctions.net/razorpayWebhook
[ ] Test webhook signature validation
[ ] Test full payment → subscription activation flow

### Phase 8: Pre-launch
[ ] Verify Firebase rules prevent direct analytics writes
[ ] Verify admin routes protected by role check
[ ] Test all user roles (guest, user, premium, admin)
[ ] Run security rules simulator in Firebase Console
[ ] Enable Firebase Performance Monitoring
[ ] Add Google Analytics (GDPR-light mode for India)


================================================================
## SCRAPER COLD-START SEQUENCE
================================================================

Day 1 deployment:
1. Seed sources/ collection with 5-10 official sites
2. Cloud Scheduler triggers jobIngestionCron
3. Scraper fetches notifications pages
4. New jobs stored with status: "pending"
5. Admin approves jobs via Admin Panel
6. onJobApproved Cloud Function triggers analytics
7. Cold-start rule applies (coldStart: true) since no history
8. categoryDefaults used for initial competition estimates
9. As more jobs accumulate, analytics become data-driven


================================================================
## SCALE PLAN
================================================================

0 – 10,000 users:    Spark plan may work for testing.
                     Switch to Blaze before any public launch.

10K – 100K users:    Monitor Firestore reads/writes in console.
                     Increase Cloud Function maxInstances if needed.

100K – 1M users:     Add Firestore connection pooling.
                     Enable Firebase Extensions for heavy lifting.
                     Consider Cloud Memorystore (Redis) for hot caches.
                     Split notification dispatch into sub-tasks (Pub/Sub).

1M+ users:           Add Cloud Run for scraping (more memory/CPU).
                     Use BigQuery for analytics aggregation.
                     CDN for static job data (Firebase Hosting CDN built-in).


================================================================
## AI USAGE LIMITS
================================================================

Free Users:          5 AI queries per day (reset at midnight IST)
Premium Users:       9999 queries (effectively unlimited)
Rate limit:          Enforced server-side in handleAIQuery Cloud Function
Abuse prevention:    Daily counter in aiUsage/{userId} — reset by cron


================================================================
## AD UNLOCK FLOW
================================================================

1. Free user views job analytics
2. Sees "Watch ad to unlock 24-hour access" button
3. Client shows rewarded ad (AdMob / Google Ads)
4. On ad completion, client calls processAdUnlock Cloud Function
5. Server validates (never client-side) and creates adUnlocks record
6. User gets 24-hour access to premium analytics for that job
7. Abuse prevention: one unlock per job per user per 24 hours (server-enforced)


================================================================
## ROBOTS.TXT COMPLIANCE
================================================================

On adding any new source to sources/ collection:
1. Cloud Function auto-fetches robots.txt for that domain
2. Parses Disallow directives
3. Stores in source.disallowedPaths[]
4. Scraper checks disallowedPaths before each request
5. If path disallowed → skip, log, continue to next source


================================================================
## NEXT PROMPTS TO GENERATE
================================================================

Prompt 5: Complete Next.js frontend architecture
Prompt 6: Admin panel components
Prompt 7: Onboarding flow UI
Prompt 8: Mock test system
Prompt 9: Performance optimization (PWA, service worker, offline)
Prompt 10: Deployment automation (CI/CD)
