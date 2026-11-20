# AlignApps Flutter Example

Minimal Flutter application that exercises the AlignApps plugin.

## Run

From the repository root, publish the native Android SDK first:

```bash
./gradlew :alignapps-sdk:publishToMavenLocal
```

Then run:

```bash
cd flutter_plugin/alignapps_flutter/example
flutter pub get
flutter run
```

The example uses a placeholder App Key and server URL. Replace them in `lib/main.dart` with a development backend that implements `openapi.yaml`.
