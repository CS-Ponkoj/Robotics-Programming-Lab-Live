# IUSE Flutter frontend

## Install

```powershell
flutter pub get
```

## Run for web

Start the FastAPI backend first, then run:

```powershell
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:5000
```

`API_BASE_URL` must be reachable from the target device. For example, an Android emulator normally needs the host address rather than `127.0.0.1`.

The local prototype login accounts are:

```text
Student:    student / student
Instructor: instructor / instructor
```

The signed-in role controls access to instructor assignment and student-account
management. Session tokens are issued by the backend and restored locally
between app refreshes.

## Verify

```powershell
flutter analyze
flutter test
flutter build web --dart-define=API_BASE_URL=http://127.0.0.1:5000
```
