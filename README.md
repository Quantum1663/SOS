# SHIELD

SHIELD is a Flutter-based women safety and emergency response app built to help users act quickly in unsafe situations. It combines fast emergency triggers, discreet alerts, journey monitoring, trusted contacts, private Safety Circles, responder planning, and privacy-focused features such as camouflage mode and app lock.

## Overview

SHIELD is designed around a few core use cases:

- `Full Panic` for immediate danger
- `Alert Family` for discreet help
- `Get Home Safe` for late travel and trip monitoring
- `Safety Circles` for grouped support such as family, hostel, campus, workplace, or neighborhood
- `Responder Overview` for seeing who is expected to call first, back up, and escalate
- `Dry-run testing` so support circles can be rehearsed safely without sending real alerts

## Features

- Central Safety Button with tap, double-tap, and hold flows
- `Full Panic` emergency path
- `Alert Family` discreet help path
- `Get Home Safe` timer with trip details
- Journey updates such as `Running Late`, `Route Update`, and `Changed Vehicle`
- Trusted contacts with priority and preferred-caller roles
- Safety Circles for private grouped routing
- Responder overview with circle-based response order
- Circle dry-run testing with preview and success confirmation
- Incident history stored locally
- Camouflage mode and stealth wording
- App lock with PIN
- Android quick access surfaces:
  - persistent notification actions
  - home-screen widget
  - Quick Settings tile
  - app-icon shortcuts

## Tech Stack

- Flutter
- Dart
- Riverpod
- SQLite (`sqflite`)
- Flutter Secure Storage
- Android native integrations through platform channels

## Project Structure

```text
lib/
  core/
  features/
    sos/
      application/
      data/
      domain/
      presentation/
  services/

android/
ios/
web/
windows/
```

## Main Modules

### Safety

The live emergency screen for:

- Full Panic
- Alert Family
- Get Home Safe
- quick audience and responder visibility

### Prepare

The setup and rehearsal area for:

- device shortcuts
- responder overview
- message previews
- privacy and stealth settings

### Circles

The grouped-support area for:

- creating Safety Circles
- choosing circle members
- deciding whether a circle is used for `Full Panic` and/or `Alert Family`
- reviewing circle coverage

### Contacts

The trusted contacts area for:

- adding contacts
- assigning response order
- marking the preferred caller

### History

The local incident log for:

- emergency actions
- journey events
- dry-run circle tests

## Supported Targets

SHIELD is primarily designed for Android.

Current support expectations:

- `Android`: best-supported platform
- `iOS`: partial support, but some flows are more limited
- `Web/Desktop`: not production-ready yet

Notes:

- Some emergency features depend on Android-specific capabilities.
- Web and desktop builds currently need additional compatibility work, especially around local storage and platform-specific plugins.

## Running the Project

### Prerequisites

- Flutter SDK
- Android Studio or Android SDK
- A connected Android device or emulator

### Install dependencies

```bash
flutter pub get
```

### Run on Android

```bash
flutter run
```

### Analyze

```bash
flutter analyze
```

## Important Notes

- SHIELD is a project/prototype and should not be treated as a certified emergency service.
- Test emergency features carefully.
- Use dry-run flows when rehearsing Safety Circles.
- Avoid triggering real emergency calls or alerts during casual testing.

## Current Limitations

- Windows desktop build may require additional local toolchain support for some plugins.
- Web launch currently needs further database/storage adaptation.
- Safety Circles are local/private today and are not yet a live public community network.
- True offline nearby community alerting is still a future enhancement.

## Future Scope

- live community responder network
- offline nearby beacon support
- background-safe escalation improvements
- wearable integration
- cloud backup and sync
- multilingual support
- stronger web and desktop compatibility

## Screenshots

Add your screenshots here after capturing the app:

- Safety screen
- Prepare screen
- Circles screen
- Contacts screen
- History screen
- Responder overview
- Circle dry-run preview

## Author

Add your name, college, and GitHub profile here.
