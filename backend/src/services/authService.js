const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const crypto = require("crypto");
const prisma = require("../config/db");
const { recordActivity } = require("./activityLogService");

const {
  generatePasswordChangeToken,
  generateToken,
  generateEmailVerificationToken,
  hashToken,
} = require("../utils/generateToken");

const publicUserSelect = {
  id: true,
  employeeCode: true,
  firstName: true,
  lastName: true,
  email: true,
  emailVerifiedAt: true,
  role: true,
  status: true,
  departmentId: true,
  canApproveManagerRequests: true,
  lastLogin: true,
};

async function login(email, password) {
  const user = await prisma.user.findUnique({
    where: {
      email: email.trim().toLowerCase(),
    },
  });

  const validPassword = user
    ? await bcrypt.compare(password, user.passwordHash)
    : false;

  if (!validPassword) {
    const error = new Error("Invalid email or password");
    error.statusCode = 401;
    throw error;
  }

  if (user.status !== "ACTIVE") {
    const error = new Error("Account is not active");
    error.statusCode = 403;
    throw error;
  }

  // Unverified users receive only a restricted token.
  // No normal JWT or database session is created.
  if (!user.emailVerifiedAt) {
    return {
      requiresEmailVerification: true,
      verificationToken: generateEmailVerificationToken(user.id),
      verificationTokenType: "Bearer",
      verificationTokenExpiresInSeconds: 600,
    };
  }

  if (user.mustChangePassword) {
    return {
      requiresEmailVerification: false,
      requiresPasswordChange: true,
      passwordChangeToken: generatePasswordChangeToken(user),
      passwordChangeTokenType: "Bearer",
      passwordChangeTokenExpiresInSeconds: 600,
    };
  }

  const sessionId = crypto.randomUUID();
  const token = generateToken(user.id, sessionId);
  const decoded = jwt.decode(token);
  const expiresAt = new Date(decoded.exp * 1000);

  const publicUser = await prisma.$transaction(async (tx) => {
    await tx.session.create({
      data: {
        id: sessionId,
        userId: user.id,
        tokenHash: hashToken(token),
        expiresAt,
      },
    });

    return tx.user.update({
      where: { id: user.id },
      data: {
        lastLogin: new Date(),
      },
      select: publicUserSelect,
    });
  });

  return {
    requiresEmailVerification: false,
    requiresPasswordChange: false,
    token,
    tokenType: "Bearer",
    expiresAt,
    user: publicUser,
  };
}

async function getProfile(userId) {
  return prisma.user.findUnique({
    where: { id: userId },
    select: publicUserSelect,
  });
}

async function logout(sessionId) {
  await prisma.session.update({
    where: { id: sessionId },
    data: {
      revokedAt: new Date(),
    },
  });
}

async function changeInitialPassword(token, password) {
  const { validatePasswordChange } = require("../validator/userValidator");
  const { getDefaultPassword } = require("../config/defaultPassword");
  const fail = (message, statusCode) => Object.assign(new Error(message), { statusCode });
  let payload;
  try {
    payload = jwt.verify(token, process.env.JWT_SECRET, { algorithms: ["HS256"] });
  } catch {
    throw fail("Invalid or expired password change token", 401);
  }
  if (payload.type !== "password_change" || !Number.isInteger(payload.userId)) {
    throw fail("Password change authentication required", 401);
  }
  const newPassword = validatePasswordChange({ password });
  if (Buffer.byteLength(newPassword, "utf8") > 72 || newPassword === getDefaultPassword()) {
    throw fail("Choose a personal password different from the default (at most 72 UTF-8 bytes)", 400);
  }
  const user = await prisma.user.findUnique({ where: { id: payload.userId } });
  if (!user || user.status !== "ACTIVE" || !user.emailVerifiedAt || !user.mustChangePassword ||
      payload.passwordVersion !== hashToken(user.passwordHash)) {
    throw fail("Password change is no longer authorized", 403);
  }
  if (await bcrypt.compare(newPassword, user.passwordHash)) {
    throw fail("New password must differ from the current password", 400);
  }
  const passwordHash = await bcrypt.hash(newPassword, 12);
  await prisma.$transaction(async (tx) => {
    const changed = await tx.user.updateMany({
      where: { id: user.id, status: "ACTIVE", emailVerifiedAt: { not: null },
        mustChangePassword: true, passwordHash: user.passwordHash },
      data: { passwordHash, mustChangePassword: false },
    });
    if (changed.count !== 1) throw fail("Account changed. Log in again.", 409);
    await tx.session.updateMany({ where: { userId: user.id, revokedAt: null }, data: { revokedAt: new Date() } });
    await recordActivity({
      db: tx, userId: user.id, action: "USER_PASSWORD_CHANGED", entityType: "USER", entityId: user.id,
      details: { passwordChanged: true, sessionsRevoked: true },
    });
  });
  return { message: "Password changed successfully. Please log in again." };
}

module.exports = {
  changeInitialPassword,
  login,
  getProfile,
  logout,
};