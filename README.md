# Scenario — mobile

Flutter client for Scenario, the omni-channel customer conversation platform.
Talks to the same Django backend as the web app, over the same session-cookie
auth, and shows the same conversations under the same visibility rules.

## Navigation

The web client has a permanent dark sidebar; a phone does not have the width, so
the same slab is a **drawer** — opened from the app bar's menu button or an edge
swipe, with the same brand header, the same organization name, and the same
sections in the same order:

| Section | Needs | Notes |
| --- | --- | --- |
| Dashboard | — | Queue and intelligence metrics, scoped to what you can see |
| Inbox | — | The conversation list; carries the unread badge |
| Customers | `customer.view` | Directory, and a customer's history |
| Employees | `employee.view` | Read-only directory with presence |
| Teams | `team.view` | Read-only; who routes what |
| Analytics | `analytics.view` | **Not** an agent — channel volume and lead pipeline |
| Settings | — | Profile · Security, plus Channels with `channel.view` |

`lib/app/navigation.dart` is the only place that decides this. The drawer and
the router guard both read it, so a link is never offered for a screen the role
cannot open, and a deep link to one refuses explicitly rather than rendering a
page whose every request 403s. It mirrors
`frontend/src/features/auth/access.ts` section for section.

None of it is a security boundary: the backend re-checks every capability, and a
client that got this wrong would produce a clean 403 rather than an
unauthorised read. See `docs/ARCHITECTURE.md` in the repo root.

## Running

```bash
flutter pub get
flutter run --dart-define=SCENARIO_ENV=development
```

The backend must be reachable at the URL in `lib/core/config/environment.dart`.
On an Android emulator that is `10.0.2.2`, not `localhost`.

## Tests

```bash
flutter analyze
flutter test
```

`test/navigation_access_test.dart` asserts the drawer and the route guard agree
for every role, against the permission sets `apps/core/permissions.py` actually
grants. `test/live_backend_test.dart` needs a running backend and is skipped
otherwise.
