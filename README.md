# PandaBoat App

A simple mobile app built with Flutter to track boat workouts, with primary readouts being speed and strokes per minute. Meant to be a no-frills, offline app, not requiring creation or access to any accounts.

This app lets you see your past history, and makes it easy to save your progress.

## Features

To come... 

## Screenshots
To come... 

## Getting Started

### Prerequisites

- **Flutter** is required to build the app for both Android and iOS. To install Flutter, follow the instructions on the official Flutter website: [Flutter Installation Guide](https://flutter.dev/docs/get-started/install).
- **Android SDK** is needed to develop and run the app on Android devices. The Android SDK is included with Android Studio. Download and install **Android Studio**: [Download Android Studio](https://developer.android.com/studio).
- Once you have Flutter and the required SDKs installed, run `flutter doctor` to check for any missing dependencies and verify your environment setup.

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/AMWen/pandaboat.git
   cd pandacore
    ```

2. Install dependencies:
```bash
flutter pub get
```

3. Once you're ready to release the app, you can generate a release APK using the following commands:

For android:
```bash
flutter build apk --release
```

See instructions for [Signing the App for Flutter](https://docs.flutter.dev/deployment/android#sign-the-app) and [Uploading Native Debug Symbols](https://stackoverflow.com/questions/62568757/playstore-error-app-bundle-contains-native-code-and-youve-not-uploaded-debug)

You may also need to remove some files from the bundle if using a MacOS.
```bash
zip -d Archive.zip "__MACOSX*"
```

For iOS (need to create an an iOS Development Certificate in Apple Developer account):
```bash
flutter build ios --release
```

### Project Structure

```bash
lib/
├── data/
│   └── services/
│   │   ├── gps_service.dart
│   │   ├── location_logger.dart
│   │   └── export_service.dart
│   └── constants.dart
├── tabs/
│   ├── live_tab.dart
│   └── log_tab.dart
├── main.dart
pubspec.yaml
```