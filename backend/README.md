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
