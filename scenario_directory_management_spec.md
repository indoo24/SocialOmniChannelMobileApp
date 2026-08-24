# Scenario Mobile — Directory Management API Implementation Spec

## Purpose

Implement the following five features in the Flutter mobile application using the existing architecture and conventions:

1. Edit Customer
2. Add Employee — **ADMIN ONLY**
3. Edit Employee — **ADMIN ONLY**
4. Deactivate Employee — **ADMIN ONLY**
5. Add Team — **ADMIN ONLY**

The backend APIs below are the source of truth. Do not invent, rename, or reinterpret endpoints, request fields, response fields, permissions, or status codes.

---

# 1. Global Requirements

## Architecture

Follow the existing project patterns already used by the app:

- Existing `ApiClient`
- Existing repository layer
- Existing model layer
- Existing Riverpod providers
- Existing permission/capability system
- Existing localization (`app_en.arb`, `app_ar.arb` + generated localization)
- Existing loading/error/success UI components
- Existing `JsonSafe` parsing conventions
- Existing test conventions

Do not introduce a new state-management architecture.

Prefer reusing existing models where their response shape already matches. Create a new model only when the existing model cannot safely represent the API response.

## Authorization rules

### Customer editing

Customer editing requires:

`customer.manage`

This is **not specified as ADMIN-only by the backend contract**. Respect the existing capability system.

### Employee management

The following three operations are **ADMIN ONLY**:

- Add employee
- Edit employee
- Deactivate employee

Backend capability:

`employee.manage`

The backend explicitly documents employee writes as ADMIN only.

The Flutter UI must also hide/disable these actions for non-admin users. Do not rely only on the backend 403.

Employees can still be read by non-admin employees through the existing `employee.view` capability.

### Team creation

Add team is **ADMIN ONLY**.

Backend capability:

`team.manage`

The Flutter UI must also hide/disable team creation for non-admin users.

Do not expose an Add Team action to agents/supervisors merely because they can view teams.

---

# 2. Feature: Edit Customer

## Endpoint

```http
PATCH /api/customers/{id}/
```

## Permission

```text
customer.manage
```

## Path parameter

```text
id: integer
```

Customer ID.

## Request body

All fields are optional because this is a PATCH:

```json
{
  "display_name": "string",
  "email": "string",
  "phone": "string",
  "preferred_language": "string",
  "country": "string",
  "city": "string",
  "lifecycle_stage": "UNKNOWN",
  "tags": "string",
  "notes": "string"
}
```

Only send fields that are actually being edited when practical. Do not send unrelated fields or read-only detail fields.

## Success

```http
200 OK
```

The response is the **full customer detail representation**.

Important response fields include:

```json
{
  "id": 0,
  "public_id": "uuid",
  "display_name": "string",
  "email": "string",
  "phone": "string",
  "avatar_url": "string",
  "preferred_language": "string",
  "country": "string",
  "city": "string",
  "lifecycle_stage": "UNKNOWN",
  "lifecycle_confirmed_by_employee": true,
  "tags": "string",
  "identities": [],
  "conversation_count": 0,
  "first_seen_at": "2026-08-23T19:01:27.879Z",
  "last_seen_at": "2026-08-23T19:01:27.879Z",
  "notes": "string",
  "facts": [],
  "confirmed_purchase_count": 0,
  "created_at": "2026-08-23T19:01:27.879Z",
  "updated_at": "2026-08-23T19:01:27.879Z"
}
```

## Errors

### 400

Validation error.

Expected generic shape:

```json
{
  "error": {
    "code": "string",
    "message": "string",
    "details": {}
  }
}
```

### 403

Authenticated user lacks `customer.manage`.

### 404

Customer does not exist inside the caller's organization.

Cross-tenant resources are intentionally reported as 404.

## UI requirements

Provide an Edit Customer action from the existing customer detail/profile surface.

The form should be prefilled with the current editable values.

On save:

1. Validate locally where appropriate.
2. Show a loading state.
3. Call PATCH.
4. Parse the returned full `CustomerDetail`.
5. Update/invalidate the relevant customer detail provider.
6. Refresh any customer list state that may contain the edited customer.
7. Close the form only after successful save.
8. Show the server error message on failure using the existing error UX.
9. Do not lose unsaved form state on a failed request.

---

# 3. Feature: Add Employee

## ADMIN ONLY

This operation must not be visible/actionable for non-admin users.

## Endpoint

```http
POST /api/employees/
```

## Permission

```text
employee.manage
```

Backend documentation explicitly states employee writes require `employee.manage` and are ADMIN only.

## Request body

```json
{
  "email": "user@example.com",
  "first_name": "string",
  "last_name": "string",
  "role": "ADMIN",
  "availability": "ONLINE",
  "avatar_url": "string",
  "phone": "string",
  "title": "string",
  "is_active": true,
  "password": "string",
  "team_ids": [0],
  "max_open_chats": 200,
  "working_hours": ["string"],
  "work_schedule_id": 0
}
```

Do not assume every field is required unless the backend validation or existing UI establishes that.

## Success

```http
201 Created
```

The backend returns the full employee read representation:

```json
{
  "id": 0,
  "public_id": "uuid",
  "email": "user@example.com",
  "first_name": "string",
  "last_name": "string",
  "full_name": "string",
  "initials": "string",
  "role": "ADMIN",
  "role_display": "string",
  "availability": "ONLINE",
  "avatar_url": "string",
  "phone": "string",
  "title": "string",
  "is_active": true,
  "teams": [
    {
      "id": 0,
      "name": "string",
      "color": "string"
    }
  ],
  "last_seen_at": "2026-08-23T19:05:35.637Z",
  "max_open_chats": 32767,
  "effective_capacity": 0,
  "routing_blocker": "string",
  "is_routing_ready": true,
  "working_hours": [
    {
      "weekday": 0,
      "start_time": "string",
      "end_time": "string",
      "crosses_midnight": true
    }
  ],
  "work_schedule": {
    "id": 0,
    "name": "string",
    "is_personal": true,
    "timezone": "string"
  },
  "created_at": "2026-08-23T19:05:35.637Z",
  "updated_at": "2026-08-23T19:05:35.637Z"
}
```

## 400 cases

Backend documentation explicitly mentions validation failures such as:

- duplicate email
- weak password
- unknown role

Use the backend's error message/details rather than inventing client-side error text.

## 403

Non-authorized user / non-admin.

## UI requirements

Create an Add Employee form in the existing Employees/Directory management surface.

At minimum support the API's meaningful editable fields:

- email
- first name
- last name
- role
- availability
- avatar URL if the existing app supports it
- phone
- title
- password
- teams
- max open chats
- working hours
- work schedule

Do not build a fake or incomplete backend contract.

After success:

- invalidate/refresh employee directory provider
- refresh online employee state if relevant
- refresh team/member-related state if relevant
- show success feedback
- return to the employee list/detail as appropriate

---

# 4. Feature: Edit Employee

## ADMIN ONLY

Non-admin users must not see or use this action.

## Endpoint

```http
PATCH /api/employees/{id}/
```

## Permission

```text
employee.manage
```

Backend explicitly states:

- reads require `employee.view`
- writes require `employee.manage`
- employee writes are ADMIN only

## Path parameter

```text
id: integer
```

## Request body

PATCH supports:

```json
{
  "email": "user@example.com",
  "first_name": "string",
  "last_name": "string",
  "role": "ADMIN",
  "availability": "ONLINE",
  "avatar_url": "string",
  "phone": "string",
  "title": "string",
  "is_active": true,
  "password": "string",
  "team_ids": [0],
  "max_open_chats": 200,
  "working_hours": ["string"],
  "work_schedule_id": 0
}
```

Only send changed/editable values.

Do not blindly send a password if the administrator did not change it.

## Success

```http
200 OK
```

Returns the full employee representation including:

- identity fields
- role
- availability
- teams
- active state
- routing/capacity fields
- working hours
- work schedule
- timestamps

Use the returned employee as the source of truth.

## Errors

- `400` validation failure
- `403` insufficient capability
- `404` employee not found inside caller organization

## UI requirements

Provide an Edit Employee action only for admins.

Prefill the form from the current employee.

After save:

1. Parse returned employee.
2. Update/invalidate employee detail state.
3. Refresh employee directory.
4. Refresh online employees if availability changed.
5. Refresh team-related state if team assignments changed.
6. Show success feedback.
7. Handle 400/403/404 through the existing API error UX.

---

# 5. Feature: Deactivate Employee

## ADMIN ONLY

This is an administrative destructive-looking action and must only be visible/actionable to admins.

## Endpoint

```http
DELETE /api/employees/{id}/
```

Important: despite using HTTP DELETE, this endpoint **does not delete the database row**.

It deactivates the employee.

The backend keeps the employee because employees are referenced by:

- messages
- assignments
- audit events

Removing the row would damage historical references.

## Permission

```text
employee.manage
```

## Path parameter

```text
id: integer
```

## Success

```http
200 OK
```

The response is the employee representation.

The employee becomes inactive and access is revoked on the next request.

## Critical restriction

The backend refuses self-deactivation.

```http
400 Bad Request
```

with the semantic error:

```text
You cannot deactivate your own account.
```

Do not attempt to bypass this restriction in the client.

## UI requirements

Before calling the endpoint:

- show a confirmation dialog
- clearly state that this deactivates the employee
- clearly identify the employee
- warn that the action affects access

Do not describe it as permanent deletion.

After success:

- remove the employee from active employee lists
- refresh employee directory
- refresh online employee state
- invalidate any employee detail provider
- show success feedback

For self-deactivation:

- backend 400 must be surfaced as a normal business error
- do not crash
- do not log the user out manually unless the backend actually reports success for the current user (it should not)

---

# 6. Feature: Add Team

## ADMIN ONLY

Only admins can create teams.

## Endpoint

```http
POST /api/teams/
```

## Permission

```text
team.manage
```

The API contract states that `member_ids` and `leader_ids` are filtered to the caller's organization. IDs belonging to another tenant are silently dropped by the backend rather than attached.

## Request body

```json
{
  "name": "string",
  "description": "string",
  "language": "string",
  "color": "string",
  "is_active": true,
  "member_ids": [0],
  "leader_ids": [0]
}
```

## Success

```http
201 Created
```

Response:

```json
{
  "id": 0,
  "public_id": "uuid",
  "name": "string",
  "description": "string",
  "language": "string",
  "color": "string",
  "is_active": true,
  "members": [
    {
      "id": 0,
      "full_name": "string",
      "email": "user@example.com",
      "role": "string",
      "availability": "string",
      "avatar_url": "string",
      "initials": "string"
    }
  ],
  "leaders": [
    {
      "id": 0,
      "full_name": "string",
      "email": "user@example.com",
      "role": "string",
      "availability": "string",
      "avatar_url": "string",
      "initials": "string"
    }
  ],
  "member_count": 0,
  "created_at": "2026-08-23T19:00:14.430Z",
  "updated_at": "2026-08-23T19:00:14.430Z"
}
```

## Errors

- `400` validation error
- `403` insufficient capability

Use the backend error contract.

## UI requirements

Create an Add Team form supporting:

- name
- description
- language
- color
- active/inactive state
- members
- leaders

Member/leader selectors should use the existing employee directory data rather than inventing a new employee source.

After successful creation:

- invalidate/refresh team list
- refresh employee/team-related state where necessary
- show success feedback
- close/navigate back from the form

---

# 7. Permission Matrix

| Feature | HTTP | Endpoint | Required capability | UI access |
|---|---|---|---|---|
| Edit Customer | PATCH | `/api/customers/{id}/` | `customer.manage` | Capability-based |
| Add Employee | POST | `/api/employees/` | `employee.manage` | **ADMIN ONLY** |
| Edit Employee | PATCH | `/api/employees/{id}/` | `employee.manage` | **ADMIN ONLY** |
| Deactivate Employee | DELETE | `/api/employees/{id}/` | `employee.manage` | **ADMIN ONLY** |
| Add Team | POST | `/api/teams/` | `team.manage` | **ADMIN ONLY** |

Important:

**Do not treat the capability gate as a substitute for the explicit ADMIN-only UI requirement.**

For the four admin-only operations, the UI must check the application's current authenticated employee role/permission state and only expose the actions to admins.

The backend remains the final security boundary.

---

# 8. Data / State Synchronization

Do not leave stale provider data after a mutation.

After every successful mutation, identify all affected providers and invalidate/refetch them.

Minimum expectations:

### Customer edit

Refresh:

- customer detail
- customer directory/list if currently visible

### Employee add/edit/deactivate

Refresh:

- employee directory
- online employees
- employee detail if open
- team-related data when team membership changed

### Team add

Refresh:

- team directory/list
- employee/team state if applicable

Prefer targeted invalidation over a global application refresh.

---

# 9. Error Handling

Follow the project's existing API exception handling.

Important:

- `400` is a backend validation/business response, not an app crash.
- `403` is an authorization result, not an app crash.
- `404` is a resource-not-found result, not an app crash.
- Parse backend error messages safely.
- Never assume an error body has a particular nested field unless the existing `ApiClient` guarantees it.
- Never use unchecked null assertions on API-derived values.
- Do not swallow errors silently.
- Do not convert normal backend business responses into fatal errors.

Use the existing `ApiException` / error-state patterns already present in the codebase.

---

# 10. UX Requirements

All five features must have:

- loading state
- disabled submit button while request is running
- validation feedback
- backend error feedback
- success feedback
- safe cancellation
- protection against double-submit
- correct keyboard/focus behavior
- responsive layout
- Arabic + English localization
- no hard-coded user-facing strings

For destructive-looking employee deactivation:

- confirmation required
- explicit employee name
- clear "Deactivate" wording
- no "Delete permanently" wording

---

# 11. Testing Requirements

Add repository/model/provider/widget tests following existing project conventions.

## Customer

Test:

- PATCH request path
- request body
- successful 200 parsing
- malformed response resilience
- 400 handling
- 403 handling
- 404 handling
- provider refresh/invalidation

## Add Employee

Test:

- POST path
- complete request body
- 201 response parsing
- duplicate-email/validation 400
- 403 handling
- admin-only UI visibility

## Edit Employee

Test:

- PATCH path
- changed fields only where applicable
- 200 response parsing
- 400/403/404 handling
- admin-only UI visibility
- provider refresh

## Deactivate Employee

Test:

- DELETE path
- 200 response parsing
- `is_active == false`
- self-deactivation 400
- 403 handling
- admin-only UI visibility
- list refresh

## Add Team

Test:

- POST path
- request body including member_ids/leader_ids
- 201 response parsing
- 400 handling
- 403 handling
- admin-only UI visibility
- team list refresh

---

# 12. Regression / Safety Audit

Before implementation:

1. Inspect the existing directory screens and repositories.
2. Inspect the existing employee/team/customer models.
3. Inspect existing permission helpers.
4. Inspect existing admin-role detection.
5. Reuse existing forms/widgets where appropriate.
6. Check all affected providers and cache invalidation paths.

After implementation:

1. Run `flutter analyze`.
2. Run the full test suite.
3. Run formatting.
4. Verify all five endpoints against the documented contract.
5. Verify non-admin users cannot see admin-only actions.
6. Verify backend 400/403/404 responses do not crash the app.
7. Verify no stale list/detail data remains after mutation.
8. Verify no duplicate navigation/sheet/global-key issues are introduced.
9. Audit all touched files for unsafe `!` null assertions.
10. Audit async lifecycle: no `setState`/provider update after disposal.
11. Audit double-submit behavior.
12. Audit localization completeness.
13. Audit Arabic/English generated localization files.
14. Audit that no existing Group 1–9 functionality regresses.

---

# 13. Important Implementation Constraints

Do NOT:

- invent endpoints
- change backend contracts
- add unnecessary CRUD endpoints
- implement team edit/delete unless requested
- implement employee reactivation unless requested
- make admin-only actions available to supervisors/agents
- rely only on hiding a button for security
- use hard-coded permission strings throughout the UI if the app already has `Perm.*`
- create duplicate models when existing models can safely be reused
- perform a full app refresh after every mutation
- introduce a new state-management pattern
- suppress exceptions just to make tests green
- weaken existing error handling
- introduce `GlobalKey`s unless absolutely necessary
- add unnecessary global state

---

# 14. Expected Deliverables

Implement the feature end-to-end:

- models where required
- repository methods
- providers
- permission constants if missing
- screens/sheets/forms
- navigation entry points
- localized strings
- generated localization updates
- state/cache invalidation
- tests
- formatting
- analyzer-clean code

Keep the implementation consistent with the existing Scenario Mobile codebase rather than introducing a parallel architecture.

---

# 15. Definition of Done

The work is complete only when:

- [ ] Edit Customer works end-to-end.
- [ ] Add Employee works end-to-end and is ADMIN only.
- [ ] Edit Employee works end-to-end and is ADMIN only.
- [ ] Deactivate Employee works end-to-end and is ADMIN only.
- [ ] Add Team works end-to-end and is ADMIN only.
- [ ] All five API contracts are implemented exactly.
- [ ] Existing models/providers are reused where appropriate.
- [ ] Mutations correctly invalidate/refetch affected data.
- [ ] 400/403/404 responses are handled safely.
- [ ] No crashes occur on success, validation failure, permission failure, or cancellation.
- [ ] Arabic and English localization are complete.
- [ ] Tests cover repository + UI authorization + important mutation flows.
- [ ] `flutter analyze` is clean.
- [ ] Full test suite passes.
- [ ] Formatting is clean.
- [ ] A final audit confirms no regressions in existing Groups 1–9 functionality.
