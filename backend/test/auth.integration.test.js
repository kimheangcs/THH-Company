const { test } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');

test('user onboarding and session lifecycle', { skip: !process.env.TEST_DATABASE_URL }, async (t) => {
  process.env.DATABASE_URL = process.env.TEST_DATABASE_URL;
  process.env.JWT_SECRET = crypto.randomBytes(32).toString('hex');
  process.env.OTP_SECRET = crypto.randomBytes(32).toString('hex');
  process.env.DEFAULT_USER_PASSWORD = 'IntegrationDefault@168';
  const bcrypt = require('bcryptjs');
  const jwt = require('jsonwebtoken');
  const prisma = require('../src/config/db');
  const email = require('../src/utils/emailService');
  const originalSend = email.sendVerificationOTP;
  let otp;
  email.sendVerificationOTP = async (_email, code) => { otp = code; };
  const express = require('express');
  const app = express();
  app.use(express.json());
  app.use('/api/auth', require('../src/router/authRoute'));
  app.use('/api/users', require('../src/router/userRoute'));
  app.use('/api/requests', require('../src/router/requestRoute'));
  app.use((error, _req, res, _next) => res.status(error.statusCode || 500).json({ message: error.message }));
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  const request = async (path, body, token, method = 'POST') => {
    const response = await fetch(base + path, {
      method,
      headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    return { status: response.status, body: await response.json() };
  };
  const suffix = crypto.randomUUID();
  const departmentIds = [];
  const userIds = [];
  const requestIds = [];
  const personalPassword = 'PersonalPassword@2026';
  let adminToken, managerToken, employee, changeToken, accessToken;
  const createFixture = async (role, departmentId) => {
    const user = await prisma.user.create({ data: {
      firstName: 'Integration', lastName: role, email: `${role}-${crypto.randomUUID()}@example.test`, role,
      departmentId, passwordHash: await bcrypt.hash(personalPassword, 12), emailVerifiedAt: new Date(),
    } });
    userIds.push(user.id);
    return user;
  };
  try {
    const dept = await prisma.department.create({ data: { name: `Auth ${suffix}`, code: suffix.slice(0, 30) } });
    departmentIds.push(dept.id);
    const other = await prisma.department.create({ data: { name: `Other ${suffix}`, code: `x${suffix.slice(0, 29)}` } });
    departmentIds.push(other.id);
    const admin = await createFixture('ADMIN', dept.id);
    const manager = await createFixture('MANAGER', dept.id);
    adminToken = (await request('/api/auth/login', { email: admin.email, password: personalPassword })).body.token;
    managerToken = (await request('/api/auth/login', { email: manager.email, password: personalPassword })).body.token;

    await t.test('manager cannot create privileged users or employees in another department', async () => {
      for (const [role, departmentId] of [['ADMIN', dept.id], ['MANAGER', dept.id], ['EMPLOYEE', other.id]]) {
        const result = await request('/api/users', { firstName: 'Test', lastName: 'User', email: `denied-${suffix}@example.test`, role, departmentId }, managerToken);
        assert.equal(result.status, 403);
      }
    });
    await t.test('manager creates active unverified employee using hashed environment default', async () => {
      const result = await request('/api/users', { firstName: 'Test', lastName: 'Employee', email: `employee-${suffix}@example.test`, departmentId: dept.id, role: 'EMPLOYEE' }, managerToken);
      assert.equal(result.status, 201);
      employee = result.body.user;
      userIds.push(employee.id);
      const stored = await prisma.user.findUnique({ where: { id: employee.id } });
      assert.equal(stored.status, 'ACTIVE');
      assert.equal(stored.emailVerifiedAt, null);
      assert.equal(stored.mustChangePassword, true);
      assert.notEqual(stored.passwordHash, process.env.DEFAULT_USER_PASSWORD);
      assert.ok(await bcrypt.compare(process.env.DEFAULT_USER_PASSWORD, stored.passwordHash));
    });
    await t.test('admin can create all three roles', async () => {
      for (const role of ['ADMIN', 'MANAGER', 'EMPLOYEE']) {
        const result = await request('/api/users', { firstName: 'Test', lastName: role, email: `created-${role}-${suffix}@example.test`, departmentId: dept.id, role }, adminToken);
        assert.equal(result.status, 201);
        userIds.push(result.body.user.id);
        assert.equal(result.body.user.role, role);
      }
    });
    await t.test('manager management is limited to employees in their department', async () => {
      assert.equal((await request(`/api/users/${employee.id}`, { jobTitle: 'Developer' }, managerToken, 'PATCH')).status, 200);
      assert.equal((await request(`/api/users/${admin.id}`, { jobTitle: 'Denied' }, managerToken, 'PATCH')).status, 403);
      assert.equal((await request(`/api/users/${employee.id}`, { departmentId: other.id }, managerToken, 'PATCH')).status, 403);
      assert.equal((await request(`/api/users/${employee.id}`, { role: 'ADMIN' }, managerToken, 'PATCH')).status, 400);
    });
    await t.test('login requires valid password and active account', async () => {
      assert.equal((await request('/api/auth/login', { email: employee.email, password: 'wrong' })).status, 401);
      await prisma.user.update({ where: { id: employee.id }, data: { status: 'SUSPENDED' } });
      assert.equal((await request('/api/auth/login', { email: employee.email, password: process.env.DEFAULT_USER_PASSWORD })).status, 403);
      await prisma.user.update({ where: { id: employee.id }, data: { status: 'ACTIVE' } });
    });
    await t.test('unverified login token only permits email verification', async () => {
      const login = await request('/api/auth/login', { email: employee.email, password: process.env.DEFAULT_USER_PASSWORD });
      const token = login.body.verificationToken;
      assert.equal(login.body.requiresEmailVerification, true);
      assert.equal(login.body.token, undefined);
      assert.equal(await prisma.session.count({ where: { userId: employee.id } }), 0);
      assert.equal((await request('/api/auth/me', undefined, token, 'GET')).status, 401);
      assert.equal((await request('/api/auth/change-initial-password', { password: personalPassword }, token)).status, 401);
      assert.equal((await request('/api/auth/send-verification-otp', {}, token)).status, 200);
      const wrong = otp === '000000' ? '111111' : '000000';
      assert.equal((await request('/api/auth/verify-email', { code: wrong }, token)).status, 400);
      const verified = await request('/api/auth/verify-email', { code: otp }, token);
      assert.equal(verified.status, 200);
      assert.equal(verified.body.requiresPasswordChange, true);
      changeToken = verified.body.passwordChangeToken;
      assert.equal((await request('/api/auth/verify-email', { code: otp }, token)).status, 409);
    });
    await t.test('verified default-password user cannot receive or use an access session', async () => {
      const login = await request('/api/auth/login', { email: employee.email, password: process.env.DEFAULT_USER_PASSWORD });
      assert.equal(login.body.requiresPasswordChange, true);
      assert.equal(login.body.token, undefined);
      assert.equal((await request('/api/auth/me', undefined, changeToken, 'GET')).status, 401);
      // Even a pre-existing valid session cannot bypass the password requirement.
      const { generateToken, hashToken } = require('../src/utils/generateToken');
      const id = crypto.randomUUID();
      const token = generateToken(employee.id, id);
      await prisma.session.create({ data: { id, userId: employee.id, tokenHash: hashToken(token), expiresAt: new Date(Date.now() + 60000) } });
      assert.equal((await request('/api/auth/me', undefined, token, 'GET')).status, 403);
    });
    await t.test('password change rejects default, weak, expired and tampered credentials', async () => {
      for (const password of [process.env.DEFAULT_USER_PASSWORD, 'weak', 'Aa1!' + 'é'.repeat(35)]) {
        assert.equal((await request('/api/auth/change-initial-password', { password }, changeToken)).status, 400);
      }
      assert.equal((await request('/api/auth/change-initial-password', { password: personalPassword }, changeToken + 'x')).status, 401);
      const payload = jwt.decode(changeToken);
      delete payload.exp; delete payload.iat;
      const expired = jwt.sign(payload, process.env.JWT_SECRET, { expiresIn: -1 });
      assert.equal((await request('/api/auth/change-initial-password', { password: personalPassword }, expired)).status, 401);
    });
    await t.test('personal password consumes change authorization and revokes sessions', async () => {
      assert.equal((await request('/api/auth/change-initial-password', { password: personalPassword }, changeToken)).status, 200);
      assert.equal((await request('/api/auth/change-initial-password', { password: 'AnotherPassword@2026' }, changeToken)).status, 403);
      assert.equal(await prisma.session.count({ where: { userId: employee.id, revokedAt: null } }), 0);
      assert.equal((await request('/api/auth/login', { email: employee.email, password: process.env.DEFAULT_USER_PASSWORD })).status, 401);
      const login = await request('/api/auth/login', { email: employee.email, password: personalPassword });
      assert.equal(login.status, 200);
      assert.equal(login.body.requiresPasswordChange, false);
      accessToken = login.body.token;
      assert.ok(accessToken);
      assert.equal((await request('/api/auth/me', undefined, accessToken, 'GET')).status, 200);
    });
    await t.test('logout revokes access session', async () => {
      assert.equal((await request('/api/auth/logout', {}, accessToken)).status, 200);
      assert.equal((await request('/api/auth/me', undefined, accessToken, 'GET')).status, 401);
    });
    await t.test('admin reset requires another personal password change and invalidates old authorization', async () => {
      const resetPassword = 'ResetPassword@2026';
      assert.equal((await request(`/api/users/${employee.id}/password`, { password: resetPassword }, adminToken, 'PATCH')).status, 200);
      assert.equal((await request('/api/auth/change-initial-password', { password: 'AnotherPassword@2026' }, changeToken)).status, 403);
      const login = await request('/api/auth/login', { email: employee.email, password: resetPassword });
      assert.equal(login.body.requiresPasswordChange, true);
      assert.equal(login.body.token, undefined);
      assert.equal((await request('/api/auth/change-initial-password', { password: personalPassword }, login.body.passwordChangeToken)).status, 200);
    });
    await t.test('admin reset rejects passwords over 72 UTF-8 bytes without changing the account', async () => {
      const before = await prisma.user.findUnique({ where: { id: employee.id } });
      const result = await request(`/api/users/${employee.id}/password`, { password: 'Aa1!' + 'ខ'.repeat(24) }, adminToken, 'PATCH');
      assert.equal(result.status, 400);
      const after = await prisma.user.findUnique({ where: { id: employee.id } });
      assert.equal(after.passwordHash, before.passwordHash);
      assert.equal(after.mustChangePassword, before.mustChangePassword);
      const boundaryPassword = 'Aa1!' + 'ខ'.repeat(22) + 'ab';
      assert.equal(Buffer.byteLength(boundaryPassword, 'utf8'), 72);
      assert.equal((await request(`/api/users/${employee.id}/password`, { password: boundaryPassword }, adminToken, 'PATCH')).status, 200);
      const reset = await prisma.user.findUnique({ where: { id: employee.id } });
      assert.ok(await bcrypt.compare(boundaryPassword, reset.passwordHash));
      assert.equal(reset.mustChangePassword, true);
    });
    await t.test('approval permission is admin-managed and enforced at assignment and decision', async () => {
      const approver = await createFixture('ADMIN', dept.id);
      const approverToken = (await request('/api/auth/login', { email: approver.email, password: personalPassword })).body.token;
      assert.ok(approverToken);
      const draft = await request('/api/requests', { title: 'Approval permission regression', type: 'GENERAL' }, managerToken);
      assert.equal(draft.status, 201);
      const id = draft.body.data.id;
      requestIds.push(id);
      assert.equal((await request(`/api/requests/${id}/submit`, {}, managerToken)).status, 400);
      assert.equal((await prisma.request.findUnique({ where: { id } })).status, 'DRAFT');
      assert.equal((await request(`/api/users/${employee.id}`, { canApproveManagerRequests: true }, managerToken, 'PATCH')).status, 403);
      assert.equal((await request(`/api/users/${employee.id}`, { canApproveManagerRequests: true }, adminToken, 'PATCH')).status, 403);
      assert.equal((await request(`/api/users/${approver.id}`, { canApproveManagerRequests: 'true' }, adminToken, 'PATCH')).status, 400);
      assert.equal((await request(`/api/users/${approver.id}`, { canApproveManagerRequests: true }, adminToken, 'PATCH')).status, 200);
      await prisma.user.update({ where: { id: approver.id }, data: { mustChangePassword: true } });
      assert.equal((await request(`/api/requests/${id}/submit`, {}, managerToken)).status, 400);
      await prisma.user.update({ where: { id: approver.id }, data: { mustChangePassword: false } });
      const submitted = await request(`/api/requests/${id}/submit`, {}, managerToken);
      assert.equal(submitted.status, 200);
      assert.equal(submitted.body.data.assignedApproverId, approver.id);
      await request(`/api/users/${approver.id}`, { canApproveManagerRequests: false }, adminToken, 'PATCH');
      assert.equal((await request(`/api/requests/${id}/approve`, {}, approverToken)).status, 403);
      assert.equal((await request(`/api/requests/${id}/reject`, { comment: 'No' }, approverToken)).status, 403);
      assert.equal((await prisma.request.findUnique({ where: { id } })).status, 'PENDING');
      assert.equal(await prisma.approvalAction.count({ where: { requestId: id } }), 0);
      await request(`/api/users/${approver.id}`, { canApproveManagerRequests: true }, adminToken, 'PATCH');
      assert.equal((await request(`/api/requests/${id}/approve`, {}, approverToken)).status, 200);
      assert.equal((await prisma.request.findUnique({ where: { id } })).status, 'APPROVED');
      assert.equal((await request(`/api/requests/${id}/approve`, {}, approverToken)).status, 409);
    });
  } finally {
    await new Promise(resolve => server.close(resolve));
    email.sendVerificationOTP = originalSend;
    await prisma.request.deleteMany({ where: { id: { in: requestIds } } });
    await prisma.activityLog.deleteMany({ where: { userId: { in: userIds } } });
    await prisma.user.deleteMany({ where: { id: { in: userIds } } });
    await prisma.department.deleteMany({ where: { id: { in: departmentIds } } });
    await prisma.$disconnect();
  }
});
