# RozgarX AI 🇮🇳

**Career Intelligence Platform for Indian Government Job Aspirants**

AI-powered job tracking, eligibility checking, and preparation guidance for SSC, Railway, Banking, UPSC and all central/state government exams.

---

## 📱 Build APK via GitHub Actions

### One-time setup:
1. Add GitHub Secret: `GOOGLE_SERVICES_JSON` ← paste your Firebase `google-services.json` content
2. Push code to `main` branch

### Every build:
- Push any change → APK builds automatically in ~10 minutes
- Go to **Actions** tab → Latest run → **Artifacts** section → Download APK

---

## 🏗️ Project Structure

```
rozgarx-ai/
├── .github/workflows/build-apk.yml   ← GitHub Actions (auto builds APK)
├── mobile/                            ← Flutter Android App
│   ├── lib/                           ← All Dart source code (23 files)
│   ├── android/                       ← Android native config
│   └── pubspec.yaml                   ← Dependencies
├── functions/                         ← Firebase Cloud Functions
├── firestore/                         ← Security rules & indexes
└── firebase.json                      ← Firebase project config
```

---

## ⚙️ Tech Stack

- **Frontend**: Flutter 3.19 (Dart)
- **Backend**: Firebase (Auth, Firestore, Functions, Storage, FCM)
- **AI**: GPT-4o-mini via OpenAI API
- **Monetization**: Google Play Billing + AdMob
- **Min Android**: 6.0 (API 23)

---

## 🔐 Required Secrets

| Secret | Description |
|---|---|
| `GOOGLE_SERVICES_JSON` | Firebase Android config (required) |
| `KEYSTORE_BASE64` | Signing keystore in base64 (optional — for signed release) |
| `KEY_ALIAS` | Keystore alias (optional) |
| `KEY_PASSWORD` | Key password (optional) |
| `STORE_PASSWORD` | Store password (optional) |

> **Note**: `google-services.json` is never committed to this repo. It is injected during CI build via GitHub Secrets.
