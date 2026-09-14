# Google Sign-In — End-to-End Setup Checklist

Google Sign-In is implemented across the Flutter app and the Flask backend.
This page is the manual, one-time Google Cloud configuration checklist. All
code-side wiring is already in place.

## How it works (30-second view)

1. User taps **Continue with Google** on the Login or Register screen.
2. `SocialAuthService` runs the native Google flow:
   - **Android**: the Credential Manager flow mints an ID token for the
     **Web OAuth client ID** audience (`serverClientId`). No
     `google-services.json` is required.
   - **iOS**: mints an ID token for the **iOS OAuth client ID** audience.
   - **Web**: mints an ID token for the **Web OAuth client ID** audience.
3. The ID token is POSTed to `POST /api/auth/google`.
4. The backend verifies it with `google-auth` (signature, issuer, expiry,
   audience) and then:
   - finds the account by `(auth_provider='google', provider_id/<sub>)`, or
   - links an existing email/password account whose email matches the
     verified token claim (only if that account has no different provider), or
   - creates a new social-only account.
   A provider conflict returns `409`; invalid tokens return `401`.
5. A normal JWT session is issued and stored just like email/password login.

## 1. Google Cloud Console setup

Create/reuse a project at <https://console.cloud.google.com>. Enable:

- **OAuth consent screen** (External; add the app name and your email).
- **Google+ API / Identity services** are not separately required; OAuth
  consent screen + OAuth client IDs below cover Google Sign-In.

### 1a. OAuth client IDs (create three)

| Client type              | Where used                           | Notes |
| ------------------------ | ------------------------------------ | ----- |
| **Web application**      | Android `serverClientId`, Web sign-in | Also gives API keys an audience. |
| **Android**              | (reserved for future/google-services.json use) | Package `com.tripora.app`. |
| **iOS**                  | iOS `clientId`                       | Bundle id for the iOS app. |

- For the **Android** client, add the **debug** keystore SHA-1 (below) now,
  and add the **release** keystore SHA-1 before shipping a release build.
- For the **iOS** client, add your iOS `Bundle Identifier`.

### 1b. Current debug-release fingerprints (this machine)

These are the **real fingerprints** of `~/.android/debug.keystore`, so you can
paste them straight into the Android OAuth client:

```
Package name: com.tripora.app
SHA-1:    5D:0C:45:5C:E1:91:68:05:D7:36:CA:8D:BC:39:5F:E6:EE:72:1D:0E
SHA-256:  17:5B:CB:23:9D:DC:5C:2C:4C:E0:B2:57:51:31:2C:B9:5C:79:39:0A:F7:B0:41:40:60:B4:81:E1:65:23:3E:E8
```

For a **release** build the app currently falls back to the debug key because
`frontend/android/key.properties` does not exist. When you generate a real
release signing key, add its SHA-1 here too (see §6).

## 2. Backend environment variables

Add to `backend/.env` (never commit it):

```
GOOGLE_CLIENT_ID_WEB=1234567890-...apps.googleusercontent.com
GOOGLE_CLIENT_ID_IOS=1234567890-...apps.googleusercontent.com
GOOGLE_CLIENT_ID_ANDROID=1234567890-...apps.googleusercontent.com
```

- The backend accepts **any** of these three audiences during verification.
- `GOOGLE_CLIENT_ID_WEB` is the important one: Android ID tokens are minted
  for the Web client ID audience.
- Restart the backend after changing `.env`.

## 3. Frontend build configuration

Pass the client IDs at build/run time (never hard-code secrets):

```bash
flutter run \
  --dart-define=API_BASE_URL=https://tripora-4mt3.onrender.com \
  --dart-define=GOOGLE_WEB_CLIENT_ID=1234567890-...apps.googleusercontent.com \
  --dart-define=GOOGLE_IOS_CLIENT_ID=1234567890-...apps.googleusercontent.com
```

- Android uses `GOOGLE_WEB_CLIENT_ID` as `serverClientId`; iOS uses
  `GOOGLE_IOS_CLIENT_ID`. Read in `frontend/lib/core/config/app_config.dart`.
- **Optional**: you may instead drop `google-services.json` into
  `frontend/android/app/`; `serverClientId` then falls back to its
  `default_web_client_id`. The file is git-ignored.

## 4. What the backend does

Read/focus areas for review:

- `backend/routes/auth.py` — `_social_login`, `_resolve_social_user`,
  `SocialAccountConflictError`, `POST /api/auth/google`, `POST /api/auth/social`
- `backend/services/social_auth_service.py` — `verify_identity_token`,
  `verify_google`, Apple verification with nonce
- `backend/models/user.py` — `auth_provider`, `provider_id`, unique
  `(auth_provider, provider_id)` index for social identities
- Migration `c7d8e9f0a5b6_add_social_provider_identity_unique.py`

Security properties:

- The backend only ever trusts **verified token claims**; the frontend cannot
  steer account resolution by sending an email in the request body.
- Social-only accounts store no password, so account enumeration via the login
  endpoint stays impossible (`/api/auth/login` returns 401 for them).
- One Google identity ⇒ one Tripora row, enforced by a partial unique index at
  the database level (in addition to application logic).

## 5. Local testing

Backend (from repo root):

```bash
backend\venv\Scripts\python.exe -m pytest -q
```

Frontend:

```bash
cd frontend
flutter analyze
flutter test
```

Manual smoke test on Android emulator/physical device:

1. Fresh user → Google → account created, lands on Home.
2. Sign out → Google again → **same** account reused (no duplicate).
3. Backend up: register an email/password account with the same address, then
   Google sign-in → that account gets linked (password still works).
4. Cancel the Google sheet → no error toast.
5. Kill backend / use a forged token → friendly error, no crash.

## 6. Before shipping (production)

- Create a **release** signing key and `frontend/android/key.properties`
  (git-ignored), then add the release key SHA-1 to the Android OAuth client.
- Confirm `GOOGLE_CLIENT_ID_*` in `backend/.env` on the production host.
- Confirm the OAuth consent screen states are set to **In production** and list
  the required scopes (default `.../auth/userinfo.email` and profile).
- iOS: set the URL scheme (`[[GDTAudio]]` legacy) — not needed with the
  credential-manager/plugin approach; verify on a physical device because
  Sign in with Apple / Google require it.