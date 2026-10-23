const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const crypto = require("crypto");
const prisma = require("../config/db");

const {
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

module.exports = {
  login,
  getProfile,
  logout,
};