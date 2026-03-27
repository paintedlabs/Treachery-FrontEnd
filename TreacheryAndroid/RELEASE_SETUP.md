# Android Release Pipeline Setup

This guide walks through the one-time setup to enable the automated Android release pipeline.

## Pipeline Overview

```
Push to main (TreacheryAndroid/**)
  → Run unit tests
  → Build signed AAB
  → Upload to Google Play internal test track

Publish GitHub Release
  → Promote internal test → production
```

## Required GitHub Secrets

Add these in **Settings > Secrets and variables > Actions**:

### Signing Secrets

| Secret | Description |
|--------|-------------|
| `ANDROID_KEYSTORE_BASE64` | Base64-encoded release keystore file |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Key alias within the keystore |
| `ANDROID_KEY_PASSWORD` | Key password (often same as keystore password) |

### Google Play Secrets

| Secret | Description |
|--------|-------------|
| `GOOGLE_PLAY_JSON_KEY_BASE64` | Base64-encoded Google Play service account JSON key |

## Step-by-Step Setup

### 1. Create a Release Keystore

If you don't already have one:

```bash
keytool -genkey -v \
  -keystore treachery-release.keystore \
  -alias treachery \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -storepass YOUR_STORE_PASSWORD \
  -keypass YOUR_KEY_PASSWORD
```

**Keep this keystore file safe** — you cannot update an app on the Play Store without it.

### 2. Base64-encode the Keystore

```bash
base64 -i treachery-release.keystore | pbcopy
```

Paste the output as the `ANDROID_KEYSTORE_BASE64` secret.

### 3. Create a Google Play Service Account

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Select the project linked to your Play Console
3. **APIs & Services > Credentials > Create Credentials > Service Account**
4. Name it `play-store-deploy`
5. Grant it no project roles (Play Console permissions are separate)
6. Create a JSON key and download it

### 4. Grant Play Console Access

1. Go to [Google Play Console](https://play.google.com/console)
2. **Users and permissions > Invite new users**
3. Enter the service account email (from step 3)
4. Grant **Release manager** or **Admin** permissions for the Treachery app
5. Click **Invite user**

### 5. Base64-encode the Service Account Key

```bash
base64 -i play-store-deploy.json | pbcopy
```

Paste the output as the `GOOGLE_PLAY_JSON_KEY_BASE64` secret.

### 6. Create the App in Play Console

Before the first automated upload:

1. Go to [Google Play Console](https://play.google.com/console)
2. **Create app** with package name `com.solomon.treachery`
3. Complete the store listing (name, description, screenshots, etc.)
4. Manually upload one AAB to the internal test track to initialize it:
   ```bash
   cd TreacheryAndroid
   ./gradlew bundleRelease
   ```
   Then upload `app/build/outputs/bundle/release/app-release.aab` via the Console

After this initial upload, all subsequent deploys will be automated.

## Environments

The workflows use GitHub Environments for deployment protection:

- **staging** — used by `deploy-internal-test.yml` (auto-deploy on push to main)
- **production** — used by `deploy-playstore.yml` (manual approval recommended)

To add approval gates:
1. Go to **Settings > Environments > production**
2. Enable **Required reviewers**
3. Add yourself as a reviewer

## Local Testing

To test the release build locally:

```bash
cd TreacheryAndroid

# Build debug (no signing needed)
./gradlew assembleDebug

# Build release (requires keystore env vars)
export KEYSTORE_PATH=/path/to/treachery-release.keystore
export KEYSTORE_PASSWORD=your_password
export KEY_ALIAS=treachery
export KEY_PASSWORD=your_password
./gradlew bundleRelease

# Run fastlane lanes locally
export GOOGLE_PLAY_JSON_KEY_PATH=/path/to/google-play-key.json
bundle exec fastlane internal
```

## Secrets Checklist

- [ ] `ANDROID_KEYSTORE_BASE64`
- [ ] `ANDROID_KEYSTORE_PASSWORD`
- [ ] `ANDROID_KEY_ALIAS`
- [ ] `ANDROID_KEY_PASSWORD`
- [ ] `GOOGLE_PLAY_JSON_KEY_BASE64`
- [ ] App created in Google Play Console
- [ ] First AAB manually uploaded to internal test track
- [ ] Service account granted Play Console permissions
- [ ] GitHub Environments configured (staging, production)
