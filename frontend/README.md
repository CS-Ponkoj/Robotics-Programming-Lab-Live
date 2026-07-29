# IUSE Flutter frontend

## Install

```powershell
flutter pub get
```

## Run for web

Start the Flask backend first, then run:

```powershell
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:5000
```

`API_BASE_URL` must be reachable from the target device. For example, an Android emulator normally needs the host address rather than `127.0.0.1`.

## Verify

```powershell
flutter analyze
flutter test
flutter build web --dart-define=API_BASE_URL=http://127.0.0.1:5000
```
