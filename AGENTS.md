# NGSL Go

- Android tablet app, package `com.jonlimx.ngsl_go`. Do not modify FCE Go.
- Preserve learning data. Never uninstall or clear app data without explicit permission.
- Learner IDs scope progress, daily plans, settings, and stories. Capture learner IDs before async work; never save into whichever learner is active when a request finishes.
- GPT authorization belongs to the tablet, with a separate secure-storage namespace. Never copy credentials from other apps.
- Validate generated learning material before saving.
- Build APKs before installing; use `adb install -r`, never `flutter run` on user devices.
- Run `flutter analyze` and `flutter test` after meaningful changes.
