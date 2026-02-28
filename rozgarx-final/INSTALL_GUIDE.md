# RozgarX AI — Complete Setup & APK Build Guide
# ============================================================
# From zero to working APK on your Android phone
# Estimated time: 2–3 hours (first time setup)
# ============================================================


## ═══════════════════════════════════════════════════
## PART 1 — INSTALL REQUIRED TOOLS ON YOUR COMPUTER
## ═══════════════════════════════════════════════════

### STEP 1.1 — Install Flutter SDK

1. Go to: https://docs.flutter.dev/get-started/install/windows
   (Choose your OS: Windows / Mac / Linux)

2. Download Flutter SDK zip (latest stable)

3. Extract to a folder — example:
   Windows: C:\flutter
   Mac/Linux: ~/flutter

4. Add Flutter to PATH:
   Windows:
     - Open System Properties → Advanced → Environment Variables
     - Edit "Path" → Add: C:\flutter\bin
   
   Mac/Linux (add to ~/.bashrc or ~/.zshrc):
     export PATH="$PATH:$HOME/flutter/bin"
     source ~/.bashrc

5. Verify installation:
   Open terminal/command prompt and run:
   
   flutter --version
   
   You should see: Flutter 3.x.x


### STEP 1.2 — Install Android Studio

1. Download from: https://developer.android.com/studio
2. Run installer with default settings
3. During setup, install:
   - Android SDK
   - Android SDK Platform-Tools
   - Android Virtual Device (optional — for emulator)

4. Accept licenses:
   flutter doctor --android-licenses
   (Press 'y' and Enter for each prompt)


### STEP 1.3 — Install Java (JDK 17)

1. Download JDK 17 from:
   https://www.oracle.com/java/technologies/downloads/#java17

2. Install with default settings

3. Set JAVA_HOME (Windows):
   - Environment Variables → New System Variable
   - Name: JAVA_HOME
   - Value: C:\Program Files\Java\jdk-17

4. Verify:
   java --version
   (Should show: openjdk 17.x.x)


### STEP 1.4 — Install Node.js (for Firebase Functions)

1. Download from: https://nodejs.org (LTS version)
2. Install with default settings
3. Verify: node --version  → should show v18 or higher


### STEP 1.5 — Install Firebase CLI

  npm install -g firebase-tools
  firebase --version   # Verify: 13.x.x


### STEP 1.6 — Verify Everything

Run this command — ALL items should show ✓:

  flutter doctor

Fix any items that show ✗ before continuing.


## ═══════════════════════════════════════════════════
## PART 2 — SET UP FIREBASE PROJECT
## ═══════════════════════════════════════════════════

### STEP 2.1 — Create Firebase Project

1. Go to: https://console.firebase.google.com
2. Click "Add Project"
3. Project name: rozgarx-ai
4. Enable Google Analytics: YES
5. Click "Create Project"


### STEP 2.2 — Enable Firebase Services

In Firebase Console, enable these one by one:

  a) Authentication:
     - Build → Authentication → Get Started
     - Sign-in method → Enable:
       ✓ Email/Password
       ✓ Google

  b) Firestore Database:
     - Build → Firestore Database → Create Database
     - Select: Start in PRODUCTION mode
     - Location: asia-south1 (Mumbai) ← IMPORTANT for India

  c) Storage:
     - Build → Storage → Get Started
     - Rules: Start in production mode
     - Location: asia-south1

  d) Cloud Functions:
     - Build → Functions → Get Started
     - Select Blaze (Pay-as-you-go) plan
       (Required for external API calls — OpenAI)
     - NOTE: Functions are free up to 2M calls/month

  e) Cloud Messaging:
     - Engage → Messaging (auto-enabled)


### STEP 2.3 — Add Android App to Firebase

1. In Firebase Console → Project Settings → Your apps
2. Click "Add app" → Android icon
3. Android package name: com.rozgarx.ai
4. App nickname: RozgarX AI Android
5. Click "Register app"
6. Download google-services.json
7. Copy google-services.json to:
   
   rozgarx-ai/mobile/android/app/google-services.json
   
   ← THIS FILE IS CRITICAL. Without it the app won't compile.


### STEP 2.4 — Set Up Google Sign-In

1. In Firebase Console → Authentication → Sign-in method → Google
2. Enable Google sign-in
3. Support email: your email address
4. Save

5. Get SHA-1 fingerprint for your machine:
   
   Windows:
   keytool -list -v -keystore "%USERPROFILE%\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android
   
   Mac/Linux:
   keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
   
6. Copy the SHA1 value
7. In Firebase Console → Project Settings → Your apps → Android app
8. Add fingerprint → paste SHA1 → Save


## ═══════════════════════════════════════════════════
## PART 3 — CONFIGURE THE FLUTTER APP
## ═══════════════════════════════════════════════════

### STEP 3.1 — Extract the ZIP

Extract rozgarx-ai.zip to a folder, example:
  C:\Projects\rozgarx-ai\    (Windows)
  ~/Projects/rozgarx-ai/     (Mac/Linux)


### STEP 3.2 — Install FlutterFire CLI

  dart pub global activate flutterfire_cli


### STEP 3.3 — Connect Flutter to Firebase

In terminal, navigate to the mobile folder:

  cd rozgarx-ai/mobile

Run FlutterFire configure:

  flutterfire configure

Follow prompts:
  - Select your Firebase project: rozgarx-ai
  - Platforms to configure: android (press Space to select, Enter to confirm)
  - This generates: lib/core/firebase/firebase_options.dart


### STEP 3.4 — Update main.dart Firebase Init

Open: lib/main.dart
Find this comment and uncomment:

  // import 'core/firebase/firebase_options.dart';

Change to:
  import 'core/firebase/firebase_options.dart';

Also find:
  await Firebase.initializeApp(
    // options: DefaultFirebaseOptions.currentPlatform,
  );

Change to:
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );


### STEP 3.5 — Install Flutter Dependencies

In the mobile folder, run:

  flutter pub get

Wait for all packages to download (3–5 minutes first time).


### STEP 3.6 — Create Empty Asset Files

The pubspec.yaml references asset folders. Create placeholder files:

  mkdir -p assets/images assets/animations assets/fonts
  
  # Create a placeholder (Flutter requires at least one file per declared folder)
  echo "" > assets/images/.gitkeep
  echo "" > assets/animations/.gitkeep


## ═══════════════════════════════════════════════════
## PART 4 — SET UP FIREBASE BACKEND
## ═══════════════════════════════════════════════════

### STEP 4.1 — Login to Firebase CLI

  firebase login

This opens a browser for Google login.


### STEP 4.2 — Initialize Firebase in Project Root

Navigate to: rozgarx-ai/ (the root folder, not the mobile folder)

  cd rozgarx-ai
  firebase use --add

Select your project: rozgarx-ai


### STEP 4.3 — Deploy Firestore Security Rules

  firebase deploy --only firestore:rules

Expected output: "Deploy complete!"


### STEP 4.4 — Deploy Firestore Indexes

  firebase deploy --only firestore:indexes

Wait for indexes to build (can take 5–10 minutes in Firebase Console).


### STEP 4.5 — Set Up Cloud Functions

Navigate to functions folder:
  cd functions
  npm install

Set required environment secrets:

  # OpenAI API key (get from: https://platform.openai.com/api-keys)
  firebase functions:secrets:set OPENAI_API_KEY
  # Paste your OpenAI API key when prompted

  # Your Android package name
  firebase functions:config:set app.package_name="com.rozgarx.ai"

  # Razorpay (optional — for web billing fallback)
  # firebase functions:secrets:set RAZORPAY_WEBHOOK_SECRET


### STEP 4.6 — Deploy Cloud Functions

  cd rozgarx-ai/functions
  firebase deploy --only functions

⚠️ This requires Blaze (paid) Firebase plan.
Functions deploy takes 5–10 minutes.
Expected: "Deploy complete! 12 functions deployed."


### STEP 4.7 — Set First Admin User

After deploying:
1. Open your app and sign in with your email
2. In Firebase Console → Firestore → users/{your-uid}
3. Edit the document:
   - role: "superadmin"
4. In Firebase Console → Authentication
   - Note your user UID
5. In terminal:
   firebase functions:shell
   
   Then run:
   setCustomClaims({uid: "YOUR_UID_HERE", claims: {role: "superadmin"}})


## ═══════════════════════════════════════════════════
## PART 5 — BUILD THE APK
## ═══════════════════════════════════════════════════

### STEP 5.1 — Build Debug APK (For Testing)

Navigate to the mobile folder:
  cd rozgarx-ai/mobile

Run:
  flutter build apk --debug

APK location after build:
  build/app/outputs/flutter-apk/app-debug.apk

Build time: 5–10 minutes first time.


### STEP 5.2 — Build Release APK

First, create a signing keystore (one-time setup):

  keytool -genkey -v -keystore rozgarx-release.jks \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -alias rozgarx

  Fill in:
  - First and last name: RozgarX AI
  - Organization: RozgarX
  - Country code: IN
  - Set a strong password (remember it!)


Create key.properties file in android/ folder:

  # android/key.properties
  storePassword=YOUR_STORE_PASSWORD
  keyPassword=YOUR_KEY_PASSWORD
  keyAlias=rozgarx
  storeFile=../rozgarx-release.jks

Update android/app/build.gradle — replace:
  signingConfig signingConfigs.debug
with your keystore config (see Flutter docs for full keystore setup).


Build release APK:

  flutter build apk --release --split-per-abi

This creates 3 smaller APKs (one per CPU architecture):
  build/app/outputs/flutter-apk/app-arm64-v8a-release.apk  ← Use this for most phones
  build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
  build/app/outputs/flutter-apk/app-x86_64-release.apk

⚡ app-arm64-v8a-release.apk works on 95%+ of modern Android phones.


### STEP 5.3 — Build App Bundle (for Play Store)

  flutter build appbundle --release

Output: build/app/outputs/bundle/release/app-release.aab


## ═══════════════════════════════════════════════════
## PART 6 — INSTALL APK ON ANDROID PHONE
## ═══════════════════════════════════════════════════

### METHOD A — USB Cable (Recommended)

1. On your Android phone:
   - Go to Settings → About Phone
   - Tap "Build Number" 7 times rapidly
   - Go back → Developer Options → Enable "USB Debugging"

2. Connect phone via USB cable to computer

3. On phone: allow USB debugging when prompted

4. In terminal, verify phone is detected:
   adb devices
   (Should show your device)

5. Install APK:
   adb install build/app/outputs/flutter-apk/app-arm64-v8a-release.apk

6. App appears in your phone's app drawer as "RozgarX AI"


### METHOD B — Direct Transfer (No USB)

1. Copy the APK file to your phone via:
   - WhatsApp (send to yourself)
   - Google Drive / Dropbox upload → download on phone
   - USB cable file manager
   - Email attachment

2. On Android phone:
   - Go to Settings → Security (or Apps)
   - Enable "Install from Unknown Sources"
   - OR: "Allow from this source" for your file manager

3. Open the APK file from your Downloads folder
4. Tap "Install"
5. Tap "Open"


### METHOD C — ADB over WiFi (No Cable)

1. Connect phone via USB first
2. Enable WiFi debugging:
   adb tcpip 5555
3. Get phone IP: Settings → WiFi → Your network → IP address
4. Disconnect USB cable
5. Connect wirelessly:
   adb connect 192.168.1.X:5555   (replace with your phone's IP)
6. Install:
   adb install app-arm64-v8a-release.apk


## ═══════════════════════════════════════════════════
## PART 7 — CONFIGURE ADMOB (For Ads to Work)
## ═══════════════════════════════════════════════════

1. Create AdMob account: https://admob.google.com
2. Add app → Android → Enter app details
3. Create Rewarded ad unit
4. Copy:
   - App ID: ca-app-pub-XXXXXXXXXXXXXXXX~XXXXXXXXXX
   - Rewarded Ad Unit ID: ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX

5. In AndroidManifest.xml, replace placeholder:
   android:value="ca-app-pub-XXXXXXXXXXXXXXXX~XXXXXXXXXX"
   with your real App ID

6. In lib/features/apply/screens/ad_unlock_screen.dart, replace:
   const _rewardedAdUnitId = 'ca-app-pub-3940256099942544/5224354917';
   with your real Rewarded Ad Unit ID

NOTE: Until you add real IDs, the app uses Google test ads and works fine for testing.


## ═══════════════════════════════════════════════════
## PART 8 — CONFIGURE GOOGLE PLAY BILLING (Optional)
## ═══════════════════════════════════════════════════

This is needed for the Premium subscription to work.
Skip for initial testing — the app works without it.

1. Create Google Play Developer account: 
   https://play.google.com/console ($25 one-time fee)

2. Create app in Play Console

3. Create subscription products:
   - Product ID: rozgarx_premium_monthly  (₹99/month)
   - Product ID: rozgarx_premium_quarterly (₹249/3 months)
   - Product ID: rozgarx_premium_yearly   (₹799/year)

4. Product IDs must match exactly what's in premium_screen.dart


## ═══════════════════════════════════════════════════
## PART 9 — TROUBLESHOOTING
## ═══════════════════════════════════════════════════

### Error: "google-services.json not found"
→ You forgot to place google-services.json in android/app/
→ Download from Firebase Console → Project Settings → Android app

### Error: "Gradle build failed"
→ Run: flutter clean && flutter pub get && flutter build apk --debug
→ Check Java version: java --version (must be 17)

### Error: "SDK location not found"
→ In android/ folder, create local.properties:
   sdk.dir=C:\\Users\\YourName\\AppData\\Local\\Android\\Sdk
   flutter.sdk=C:\\flutter

### Error: "minSdkVersion too low"
→ Already set to 26 in build.gradle. No action needed.

### App crashes on launch
→ Check Logcat in Android Studio
→ Most likely: firebase_options.dart not generated
→ Run: flutterfire configure

### "Cleartext traffic" error
→ Already handled by android:usesCleartextTraffic="false"

### Functions deployment fails
→ Ensure you're on Blaze plan
→ Check: firebase --project rozgarx-ai functions:list

### flutter pub get fails with version conflicts
→ Run: flutter pub upgrade
→ Or manually update conflicting versions in pubspec.yaml


## ═══════════════════════════════════════════════════
## PART 10 — WHAT WORKS WITHOUT FULL BACKEND SETUP
## ═══════════════════════════════════════════════════

✅ WORKS immediately after step 3-5 (Flutter + Firebase Auth + Firestore):
   - Login / Register / Google Sign-In
   - Onboarding flow
   - Dashboard (shows empty — needs jobs in Firestore)
   - Jobs list (empty until jobs added)
   - Profile screen
   - PDF viewer (once you have a PDF URL)
   - Dark/Light mode

⚠️ NEEDS Cloud Functions deployed:
   - AI eligibility check
   - Subscription verification
   - Ad unlock server-side validation
   - Study plan generation

⚠️ NEEDS AdMob configured:
   - Rewarded ads
   - Ad unlock flow (uses test ads until configured)

⚠️ NEEDS Play Console setup:
   - Premium subscriptions (free plan works without this)

⚠️ NEEDS jobs added to Firestore:
   - Run the job scraper (functions/index.js)
   - Or manually add a test job in Firebase Console


## ═══════════════════════════════════════════════════
## QUICK REFERENCE — COMMANDS CHEATSHEET
## ═══════════════════════════════════════════════════

  # Check Flutter setup
  flutter doctor

  # Install dependencies
  flutter pub get

  # Run on connected device (debug)
  flutter run

  # Build debug APK
  flutter build apk --debug

  # Build release APK (split by CPU)
  flutter build apk --release --split-per-abi

  # Build Play Store bundle
  flutter build appbundle --release

  # Install to connected phone
  adb install build/app/outputs/flutter-apk/app-arm64-v8a-release.apk

  # Deploy Firebase rules
  firebase deploy --only firestore:rules

  # Deploy all Firebase
  firebase deploy

  # View function logs
  firebase functions:log

  # Clean build
  flutter clean && flutter pub get


## ═══════════════════════════════════════════════════
## FILE STRUCTURE REFERENCE
## ═══════════════════════════════════════════════════

rozgarx-ai/
├── mobile/                          ← Flutter Android App
│   ├── lib/
│   │   ├── main.dart                ← App entry point
│   │   ├── core/
│   │   │   ├── cache/               ← Offline Hive cache
│   │   │   ├── network/             ← Bandwidth detection
│   │   │   ├── router/              ← Navigation (go_router)
│   │   │   └── theme/               ← Dark/Light theme
│   │   ├── features/
│   │   │   ├── auth/                ← Login, Onboarding, Splash
│   │   │   ├── dashboard/           ← Home screen
│   │   │   ├── jobs/                ← Job list, detail, PDF viewer
│   │   │   ├── preparation/         ← Study plan
│   │   │   ├── profile/             ← User profile, settings
│   │   │   ├── premium/             ← Subscription screen
│   │   │   └── apply/               ← Apply assistance + ad unlock
│   │   └── shared/
│   │       ├── models/              ← Job data model
│   │       └── widgets/             ← Reusable widgets
│   ├── android/                     ← Android native config
│   │   └── app/
│   │       ├── build.gradle         ← Build config (minSDK 26)
│   │       ├── proguard-rules.pro   ← Release obfuscation
│   │       └── src/main/
│   │           ├── AndroidManifest.xml
│   │           └── kotlin/.../MainActivity.kt
│   └── pubspec.yaml                 ← Dependencies
│
├── functions/                       ← Firebase Cloud Functions (Node.js)
│   ├── index.js                     ← All function exports
│   ├── ai-engine/
│   │   ├── jobParser.js             ← AI parsing pipeline (9 stages)
│   │   ├── jobParser.test.js        ← 30 unit tests
│   │   ├── parserIntegration.js     ← Firebase integration
│   │   └── prompts.md               ← 8 engineered AI prompts
│   └── monetization/
│       ├── subscriptionFunctions.js ← Google Play + Razorpay billing
│       └── userFunctions.js         ← User system + eligibility AI
│
├── firestore/
│   ├── firestore.rules              ← Complete security rules
│   ├── firestore.indexes.json       ← All composite indexes
│   └── schema.yaml                  ← Database schema reference
│
├── firebase.json                    ← Firebase project config
└── storage.rules                    ← Storage security rules


## ═══════════════════════════════════════════════════
## SUPPORT & NEXT STEPS
## ═══════════════════════════════════════════════════

After successful APK install:

1. Add test jobs to Firestore manually:
   Firebase Console → Firestore → jobs → Add Document
   Add fields as per schema.yaml

2. Test the complete flow:
   - Sign up → Onboarding → Dashboard → Browse Jobs
   - View Job Detail → View PDF
   - Save Job → Profile → Saved Jobs

3. Configure your scraper sources in Firestore:
   sources/ collection — add SSC, UPSC, RRB etc.

4. Set up automated job ingestion:
   firebase functions:log (watch for jobIngestionCron)

For Play Store submission:
→ Read: https://docs.flutter.dev/deployment/android

For AdMob setup:
→ Read: https://pub.dev/packages/google_mobile_ads

---
RozgarX AI — Built with Flutter + Firebase
Target: 1M+ users across India
