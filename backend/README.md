# Backend authentication

Run commands from `backend` with Node.js and a MySQL-compatible database available.
Configure the ignored `.env` with `DATABASE_URL`, `JWT_SECRET` (at least 32
characters), `OTP_SECRET` (at least 32 characters), and `DEFAULT_USER_PASSWORD`.
The default password is shared by newly created accounts and must be configured
on each deployment. It is hashed using bcrypt before storage; never return it in
API responses or include it in logs. SMTP delivery additionally requires
`SMTP_USER` and `SMTP_APP_PASSWORD`, with optional `SMTP_HOST`, `SMTP_PORT`,
`SMTP_SECURE`, and `SMTP_FROM_NAME`.

After installing dependencies, run:

```sh
npx prisma generate
npx prisma migrate deploy
node App.js
```

Create the first admin using `node scripts/create-admin.js`. It prompts for the
name and email and uses the configured default password. This admin must complete
the same email verification and password change flow as other new accounts.

## User creation and first login

1. An admin calls `POST /api/users` with `firstName`, `lastName`, `email`,
   `departmentId`, and optionally `role` (`ADMIN`, `MANAGER`, or `EMPLOYEE`;
   defaults to `EMPLOYEE`). Do not send a `password` field. A manager can create
   only employees in their own department, and retains the same restriction for
   user management. New accounts are active, unverified, and marked
   `mustChangePassword`.
2. Call `POST /api/auth/login` with `{ "email": "...", "password": "..." }`.
   An unverified account receives `requiresEmailVerification: true` and a
   `verificationToken`, valid for 10 minutes. No access session is created.
3. Send that token as `Authorization: Bearer <verificationToken>` to
   `POST /api/auth/send-verification-otp` (or `/resend-verification-otp`).
   Submit `{ "code": "123456" }` to `POST /api/auth/verify-email` with the same
   token. OTPs expire after five minutes, allow five incorrect attempts, and have
   a 60-second resend cooldown.
4. Successful verification returns `requiresPasswordChange: true` and a
   `passwordChangeToken`, valid for 10 minutes. Use it as a Bearer token for
   `POST /api/auth/change-initial-password` with `{ "password": "..." }`.
   The personal password must differ from the default and current password, be
   12–72 characters and at most 72 UTF-8 bytes, and include uppercase, lowercase,
   a digit, and a symbol. This token cannot access normal API routes.
5. Password change consumes the authorization, revokes existing sessions, and
   asks the user to log in again. Login now returns an access `token` backed by a
   database session. If the password-change token expires, logging in again
   provides a fresh one for a verified account still requiring a password change.
6. Use the access Bearer token for protected routes. They check the signature,
   session, account status, verified email, and completed password change.
   `POST /api/auth/logout` revokes the current session.

An admin password reset also requires the user to choose a personal password
before receiving another access session. Existing accounts retain their current
password-change state when the migration is applied; it does not reset passwords
or force previously onboarded users through first login again.

The frontend must handle both `requiresEmailVerification` and
`requiresPasswordChange`; the backend does not issue an access token during either
restricted stage.

## Request approval permission

Employee requests go to their department's configured manager. Manager and admin
requests go to another admin with `canApproveManagerRequests: true`. Approvers
must be active, email verified, and finished with their required password change.
If no eligible approver exists, submission fails and the request stays a draft.

An authenticated admin can grant or revoke this permission on an admin account:

```http
PATCH /api/users/:id
Authorization: Bearer <admin-access-token>
Content-Type: application/json

{ "canApproveManagerRequests": true }
```

Use `false` to revoke it. Managers cannot change approval permission, and it
cannot be set on manager or employee accounts. The first admin setup script grants
the permission; additional admins start without it. Existing accounts retain their
stored value. Both approve and reject operations recheck the permission, so revoking
it also prevents decisions on requests already assigned to that admin. Restore the
permission to let that admin process those pending requests. Self-approval remains
prohibited.

Admin password resets enforce the same 72 UTF-8 byte limit as initial password
changes, including passwords containing Khmer or other multibyte characters.

## Integration tests

Apply migrations to a dedicated test database, then provide its URL as
`TEST_DATABASE_URL` when running `npm test`. The tests use real HTTP requests,
Prisma, MySQL, bcrypt, and JWTs. SMTP is replaced with a local capture, so no email
is sent. Test users and departments are removed afterward. Without
`TEST_DATABASE_URL`, the database integration suite is explicitly skipped.

## Demo data for endpoint walkthroughs

Run this on the machine that can reach the intended database. `127.0.0.1` means
that machine; a cloud task cannot reach MySQL on your own computer through its
loopback address. Keep the correct `DATABASE_URL` in the ignored `backend/.env`
or an existing process variable. Configure a strong `DEMO_PASSWORD` securely in
that file or your environment: 12+ characters, upper/lowercase, a number and a
symbol, at most 72 UTF-8 bytes. Do not put credentials in Git, command arguments,
screenshots or chat. Use a new demo-only password rather than a real user's password.

The database must already have this backend's migrations applied. The seeder does
not create, drop, reset or migrate databases. First review its read-only preview:

```sh
cd backend
npm run seed:demo -- --dry-run
```

The preview shows the database name and hostname without credentials. On the
intended machine, insert only when that target is correct:

```sh
npm run seed:demo -- --apply --expected-database thh_company_db
```

For a connection stored in another variable, select it explicitly without copying
its value into the command:

```sh
npm run seed:demo -- --dry-run --database-variable LIVE_DATABASE_URL
npm run seed:demo -- --apply --expected-database thh_company_db --database-variable LIVE_DATABASE_URL
```

The expected database name must match `SELECT DATABASE()`. There are no hardcoded
passwords. The first successful run creates the following marked demo records:

| Records | Count / scenarios |
| --- | --- |
| Departments | 5: Technology, Marketing, Operations, an inactive department and an empty department suitable for demonstrating deletion |
| Users | 12: 2 authorized admins, 3 department managers, 3 active employees, inactive/suspended employees, an email-verification account and a personal-password-setup account |
| Projects | 5, covering every project status and participating departments |
| Tasks | 12, covering every task status, priorities, overdue work, assignments, independent review and revision examples |
| Collaboration | 36 checklist items, 12 comments and 3 review-history entries |
| Requests | 9, covering every request type/status, employee-to-manager approval and manager/admin-to-authorized-admin approval |
| Approval history | 7 steps and 2 historical decisions; pending examples can be approved, rejected or cancelled through the API |
| Attachments | 3 real harmless TXT files: one task attachment and draft/pending request attachments |
| Inbox/audit | Read/unread notifications, pending approval alerts, task assignment and activity history |

Normal demo logins use the configured `DEMO_PASSWORD`:

| Role | Email |
| --- | --- |
| Admin | `admin@demo.thh.example` |
| Independent admin approver | `approver@demo.thh.example` |
| Technology manager | `it.manager@demo.thh.example` |
| Marketing manager | `marketing.manager@demo.thh.example` |
| Operations manager | `operations.manager@demo.thh.example` |
| Assigned employee | `employee@demo.thh.example` |
| Marketing employee | `designer@demo.thh.example` |
| Operations employee | `coordinator@demo.thh.example` |

Normal fixtures are explicitly verified and have completed password setup so you
can demonstrate business endpoints immediately. `verify.email@demo.thh.example`
requires email verification; optionally set `DEMO_ONBOARDING_EMAIL` to an address
you control **before the first seed** to exercise actual SMTP delivery. Reserved
`.example` addresses cannot receive mail. `change.password@demo.thh.example`
starts at required personal password setup. Both disabled accounts (`inactive`
and `suspended` at the same domain) demonstrate login rejection. Sessions and OTP
codes are generated by the real endpoints, never pre-populated by the seeder.

Seeded pending approvals are assigned to demo managers/admins. New requests
submitted later follow the normal backend routing and may select an existing
authorized admin.

The seeder inserts in one transaction and leaves existing records/passwords
unchanged. It refuses conflicting demo identifiers rather than overwriting them.
A marker makes reruns a no-op, preserving edits or deletions made during your
walkthrough. File failures roll back database inserts and remove only newly
created files. Attachments are written under this backend's normal upload folders;
run the seeder on the API server's filesystem so downloads can access them.

Campaigns, calendar events and saved reports have schema models but no mounted API
routers, so they are outside this endpoint dataset. No emails are sent by seeding.
The demo accounts are real accounts: use them only on the database you intentionally
selected and manage their access like other accounts.

Validation uses its own empty database ending in `_test`, separate from the auth
integration test database:

```sh
DEMO_TEST_DATABASE_URL=<dedicated-test-connection> node --test test/demo-seed.integration.test.js
```

The test verifies wrong-target rejection, collision protection, transaction rollback,
real file downloads, role logins/permissions, task reviews, request approvals and
repeatability without changing existing data. Never use a live database for this test.
