const { test } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const net = require('node:net');
const { fork } = require('node:child_process');
const { once } = require('node:events');
const { PrismaClient } = require('@prisma/client');
const { seedDemo, databaseName, manifest, ACCOUNTS } = require('../scripts/seed-demo');

const url = process.env.DEMO_TEST_DATABASE_URL;
test('demo seeding is additive, atomic, repeatable and usable through real API endpoints', { skip: !url, timeout: 60000 }, async () => {
  const db = new PrismaClient({ datasourceUrl: url });
  const name = await databaseName(db);
  assert.match(name, /_test$/, 'Use a dedicated database ending in _test');
  assert.equal(await db.department.count({ where: { code: { startsWith: 'DEMO-' } } }), 0, 'Use a fresh demo test database');
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'thh-demo-seed-'));
  const password = `SeedTest@${crypto.randomBytes(16).toString('hex')}`;
  const sentinel = await db.department.create({ data: { name: `Existing ${crypto.randomUUID()}`, code: crypto.randomBytes(10).toString('hex') } });
  let collision, server;
  try {
    await assert.rejects(seedDemo({ db, expectedDatabase: `${name}_wrong`, password, storageRoot: directory }), /does not match/);
    assert.equal(await db.user.count(), 0);
    collision = await db.user.create({ data: { firstName: 'Existing', lastName: 'Account', email: 'admin@demo.thh.example', passwordHash: 'unchanged-existing-hash', departmentId: sentinel.id } });
    await assert.rejects(seedDemo({ db, expectedDatabase: name, password, storageRoot: directory }), /collision/);
    assert.equal((await db.user.findUnique({ where: { id: collision.id } })).passwordHash, 'unchanged-existing-hash');
    assert.equal(await db.department.count(), 1);
    await db.user.delete({ where: { id: collision.id } });
    collision = null;

    // Filesystem failures must roll back all database inserts as well.
    const invalidRoot = path.join(directory, 'not-a-directory');
    await fs.writeFile(invalidRoot, 'existing local file');
    await assert.rejects(seedDemo({ db, expectedDatabase: name, password, storageRoot: invalidRoot }));
    assert.equal(await db.user.count(), 0);
    assert.equal(await db.project.count(), 0);
    assert.equal(await db.department.count(), 1);

    const result = await seedDemo({ db, expectedDatabase: name, password, storageRoot: directory });
    assert.equal(result.status, 'created');
    assert.equal(await db.user.count(), manifest.users);
    assert.equal(await db.department.count(), manifest.departments + 1);
    assert.equal(await db.project.count(), manifest.projects);
    assert.equal(await db.task.count(), manifest.tasks);
    assert.equal(await db.request.count(), manifest.requests);
    assert.equal(await db.taskChecklist.count(), 36);
    assert.equal(await db.taskComment.count(), 12);
    assert.equal(await db.taskReview.count(), 3);
    assert.equal(await db.approvalStep.count(), 7);
    assert.equal(await db.approvalAction.count(), 2);
    assert.equal(await db.taskAttachment.count(), 1);
    assert.equal(await db.requestAttachment.count(), 2);
    assert.equal(await db.session.count(), 0);
    assert.equal(await db.emailVerificationOtp.count(), 0);
    assert.equal((await db.department.findUnique({ where: { id: sentinel.id } })).name, sentinel.name);

    const reserve = net.createServer();
    reserve.listen(0, '127.0.0.1');
    await once(reserve, 'listening');
    const port = reserve.address().port;
    await new Promise(resolve => reserve.close(resolve));
    server = fork(path.resolve(__dirname, '../App.js'), [], { cwd: directory, env: {
      ...process.env, DATABASE_URL: url, PORT: String(port), DEFAULT_USER_PASSWORD: password,
      JWT_SECRET: crypto.randomBytes(48).toString('hex'), OTP_SECRET: crypto.randomBytes(48).toString('hex'),
    }, stdio: ['ignore', 'ignore', 'ignore', 'ipc'] });
    const base = `http://127.0.0.1:${port}`;
    let ready = false;
    for (let i = 0; i < 50; i++) {
      try { if ((await fetch(`${base}/api/health`)).ok) { ready = true; break; } } catch {}
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    assert.ok(ready, 'API startup completed');
    async function request(route, token, body, status = 200) {
      const response = await fetch(base + route, { method: body ? 'POST' : 'GET', headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) }, ...(body ? { body: JSON.stringify(body) } : {}) });
      assert.equal(response.status, status, `${route} status`);
      return response.json();
    }
    const tokens = {};
    for (const key of ['admin', 'approver', 'it.manager', 'employee', 'designer']) {
      const login = await request('/api/auth/login', null, { email: `${key}@demo.thh.example`, password });
      assert.ok(login.token, `${key} can log in`);
      tokens[key] = login.token;
    }
    assert.equal((await request('/api/auth/login', null, { email: 'verify.email@demo.thh.example', password })).requiresEmailVerification, true);
    assert.equal((await request('/api/auth/login', null, { email: 'change.password@demo.thh.example', password })).requiresPasswordChange, true);
    for (const key of ['inactive', 'suspended']) await request('/api/auth/login', null, { email: `${key}@demo.thh.example`, password }, 403);
    for (const route of ['/api/departments', '/api/users', '/api/projects', '/api/tasks', '/api/requests', '/api/requests/pending-approvals', '/api/notifications', '/api/activity-logs']) {
      assert.equal((await request(route, tokens.admin)).success, true);
    }
    assert.equal((await request('/api/tasks', tokens.employee)).data.length, manifest.tasks);
    assert.equal((await request('/api/tasks', tokens.designer)).data.length, 0);
    await request('/api/users', tokens.employee, null, 403);
    const fileTask = await db.taskAttachment.findFirst();
    const fileResponse = await fetch(`${base}/api/tasks/${fileTask.taskId}/attachments/${fileTask.id}/download`, { headers: { Authorization: `Bearer ${tokens.employee}` } });
    assert.equal(fileResponse.status, 200);
    assert.match(await fileResponse.text(), /THH Workflow demo attachment/);
    const fileRequest = await db.requestAttachment.findFirst();
    const requestFile = await fetch(`${base}/api/requests/${fileRequest.requestId}/attachments/${fileRequest.id}/download`, { headers: { Authorization: `Bearer ${tokens.employee}` } });
    assert.equal(requestFile.status, 200);
    const task = await db.task.findFirst({ where: { status: 'IN_REVIEW' }, orderBy: { id: 'asc' } });
    await request(`/api/tasks/${task.id}/reviews`, tokens.admin, { decision: 'APPROVED' });
    const pending = await db.request.findUnique({ where: { requestNo: 'DEMO-REQ-002' } });
    await request(`/api/requests/${pending.id}/approve`, tokens['it.manager'], {});
    assert.equal((await db.request.findUnique({ where: { id: pending.id } })).status, 'APPROVED');
    assert.ok((await request(`/api/requests/${pending.id}/history`, tokens.employee)).data.approvalActions.length);

    const userBefore = await db.user.findFirst({ where: { email: 'employee@demo.thh.example' } });
    const taskBefore = await db.task.update({ where: { id: task.id }, data: { description: 'Keep my demo edits' } });
    const countsBefore = await Promise.all([db.user.count(), db.task.count(), db.request.count(), db.notification.count(), db.activityLog.count()]);
    assert.equal((await seedDemo({ db, expectedDatabase: name, password: 'a different password is not applied', storageRoot: directory })).status, 'already-installed');
    assert.deepEqual(await Promise.all([db.user.count(), db.task.count(), db.request.count(), db.notification.count(), db.activityLog.count()]), countsBefore);
    assert.equal((await db.task.findUnique({ where: { id: taskBefore.id } })).description, 'Keep my demo edits');
    assert.equal((await db.user.findUnique({ where: { id: userBefore.id } })).passwordHash, userBefore.passwordHash);
  } finally {
    if (server && server.exitCode === null) { const exited = once(server, 'exit'); server.kill('SIGTERM'); await exited; }
    const users = await db.user.findMany({ where: { employeeCode: { startsWith: 'DEMO-' } }, select: { id: true } });
    await db.request.deleteMany({ where: { requestNo: { startsWith: 'DEMO-' } } });
    await db.task.deleteMany({ where: { project: { code: { startsWith: 'DEMO-' } } } });
    await db.project.deleteMany({ where: { code: { startsWith: 'DEMO-' } } });
    await db.activityLog.deleteMany({ where: { userId: { in: users.map(user => user.id) } } });
    await db.user.deleteMany({ where: { id: { in: users.map(user => user.id) } } });
    if (collision) await db.user.delete({ where: { id: collision.id } });
    await db.department.deleteMany({ where: { code: { startsWith: 'DEMO-' } } });
    await db.department.delete({ where: { id: sentinel.id } });
    await db.$disconnect();
    await fs.rm(directory, { recursive: true, force: true });
  }
});
