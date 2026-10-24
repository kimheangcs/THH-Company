# THH Workflow mobile app

Flutter workspace for Android phones, with responsive tablet and desktop layouts.
The interface uses the bundled THH logo, a purple (`#7045FF`) and lavender palette,
soft illustrated headers, gradient actions, and rounded cards. Poppins Regular,
Medium, SemiBold, Bold, and ExtraBold are bundled locally under `assets/fonts/`
with the SIL Open Font License; no runtime font download is needed.
Phone navigation keeps Home, Tasks, and Requests within reach; More opens the
role-specific menu. The application displays live API data, not demo statistics.

Login, OTP and password setup follow the supplied mobile design references.
The profile card shows the actual name, email, account status and role badge
(admin in gold, manager in purple, employee in blue). Admins can open their edit
and password controls; other roles receive their supported admin-managed profile
and password-help flows. Language and theme rows describe the current English
and lavender interface. Google login and public signup are not advertised because
the backend does not provide them. The login Remember me control saves an access
session in secure storage only when selected; otherwise it stays in process memory.

## Run on Android

Validated with Flutter 3.47.8 / Dart 3.13.7, JDK 21, Android SDK 36 and the
repository's Gradle wrapper. Start the backend using `backend/README.md` first.

```sh
cd frontend
flutter pub get --enforce-lockfile
# Android emulator: 10.0.2.2 addresses the development host.
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

For a USB-connected Android phone, keep the backend running on your computer and
forward the phone's loopback port through ADB:

```sh
adb reverse tcp:3000 tcp:3000
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:3000
```

The API address is a build-time setting. Debug builds allow HTTP for local
Android development. Release builds keep Android's default cleartext restriction;
provide your deployed HTTPS API address:

```sh
flutter build apk --release --dart-define=API_BASE_URL=https://your-api.example.com
```

Configure your own application ID and release signing before distributing the
app. This repository currently uses the Flutter template's debug signing for
release builds. No signing keys or credentials belong in version control.

## Connected workflows

| Area | Screens and actions |
| --- | --- |
| Account | Sign in, email OTP send/resend/verification, required personal password setup, session restoration, profile, sign out and expired-session recovery |
| Overview | Role-scoped project/task totals, progress counts, recent tasks and activity |
| Projects | Paginated search, details, create/edit, status changes, related tasks |
| Tasks | Paginated search and status filters, create/edit, assignments, progress, submit for review, approve/request changes and review history |
| Collaboration | Add/edit/delete comments and checklist items, complete checklist items |
| Files | Pick and upload PDF/JPG/PNG/TXT up to 10 MB, authenticated download and deletion for tasks and requests; Android downloads use the native Save dialog |
| Requests | Create/edit drafts, submit/cancel, status filters, attachments and approval history; title search operates on the current page |
| Approvals | Assigned approval queue, approve and reject with a required reason |
| People | Create/view/edit teammates, account status, admin password reset and admin approval permission |
| Departments | List/details, admin create/edit/delete, assign/remove manager |
| Inbox | Unread badge, read/unread filters, mark one/all read, delete one/clear read and related-item links |
| Activity | Personal activity for every role; admins additionally have company audit details and entity history |

Admins have company management controls. Managers have department and authorized
project controls. Employees focus on assigned work and personal requests. Editing,
assignment and review controls follow backend permissions, including independent
review and no self-approval; the backend remains the authority for every action.

Campaigns, calendar events and reports are not exposed by the current backend
routers and therefore are not presented as working frontend features.

Selecting an owning department in a project form automatically fills its assigned,
active, verified manager as project lead. Switching departments updates that lead;
if no eligible manager exists, the old selection is cleared and the form explains
that a lead must be chosen. Existing projects keep their current lead until the
owning department changes. Manager users remain limited to their own department
and themselves as lead, matching backend permissions.

Access tokens use platform secure storage. Email verification and password-change
tokens stay in memory and never become stored access credentials. Server errors
are shown inline or in feedback messages; lists include retry, refresh, loading
and empty states. Destructive and workflow-changing actions require confirmation.

## Validation

```sh
flutter analyze
flutter test
flutter build apk --debug --target-platform android-arm64
```

Tests cover onboarding token separation, password setup recovery, response parsing,
role permissions, small-screen/large-text layouts, task submission, rejection
validation and notification routing. The live API workflow test is opt-in and
skips unless `THH_API_FIXTURE` points to a local JSON fixture. It must use a
disposable database, never production. The fixture shape is:

```json
{
  "url": "http://127.0.0.1:3001",
  "departmentId": 1,
  "users": {
    "ADMIN": { "id": 1, "token": "synthetic-test-session" },
    "MANAGER": { "id": 2, "token": "synthetic-test-session" },
    "EMPLOYEE": { "id": 3, "token": "synthetic-test-session" }
  }
}
```

Use active, verified fixtures with completed password setup, a manager assigned to
the fixture department, one eligible admin approver, valid stored sessions, and a
configured `DEFAULT_USER_PASSWORD`. The live test creates records and logs out the
employee, so create fresh fixtures before each run. Keep fixture credentials
outside the checkout. It exercises the real backend across all workspace modules,
including multipart file transfers and forbidden role actions:

```sh
THH_API_FIXTURE=/path/outside/checkout/fixture.json flutter test
```

Optional screenshot capture in layout tests uses `THH_SCREENSHOTS` for the output
directory and `THH_FONT_DIRECTORY` for Flutter's material font cache. These renders
are widget-test previews, not screenshots from physical Android hardware.
