---
name: mobile-store-upload-cli
description: Manual CLI workflows for uploading iOS builds to TestFlight and Android builds to Google Play. Use when you need step-by-step terminal commands to build, archive, validate, and upload IPA/AAB artifacts, configure App Store Connect or Play Console credentials, or handle release metadata without CI/CD or GUI-only flows.
---

# Mobile Store Upload CLI

## Overview

Provide terminal-first, manual release workflows for iOS TestFlight and Google Play Console uploads. Keep commands concrete, minimize assumptions, and call out required credentials and prerequisites.

## Workflow

1. Confirm target platform(s) and artifact format (IPA for iOS, AAB for Android).
2. Verify credentials and access are ready.
   - iOS: App Store Connect API key or Apple ID + app-specific password.
   - Android: Play Developer API enabled + service account JSON with Play Console access.
3. Build and package the release artifact.
4. Upload and validate the artifact from CLI.
5. Confirm processing status in store consoles and share next steps.

## iOS TestFlight (CLI)

Follow the iOS reference for commands and required inputs.
- Read `references/ios.md` for archive/export and upload commands.

## Android Play Store (CLI)

Follow the Android reference for commands and required inputs.
- Read `references/android.md` for AAB build and upload commands.

## Guardrails

- Never commit secrets (API keys, app-specific passwords, service account JSON).
- Prefer placeholders and environment variables in commands.
- If a required tool is missing, suggest the minimal install step for that tool.
