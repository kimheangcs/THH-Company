const crypto = require("crypto");
const prisma = require("../config/db");
const { sendVerificationOTP } = require("../utils/emailService");

const OTP_EXPIRY_MS = 5 * 60 * 1000;
const RESEND_COOLDOWN_MS = 60 * 1000;
const MAX_ATTEMPTS = 5;

function httpError(message, statusCode) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

function hashOtp(userId, otp) {
  const secret = process.env.OTP_SECRET;

  if (!secret || secret.length < 32) {
    throw new Error("OTP_SECRET must contain at least 32 characters");
  }

  return crypto
    .createHmac("sha256", secret)
    .update(`${userId}:${otp}`)
    .digest("hex");
}

async function getEligibleUser(userId) {
  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: {
      id: true,
      email: true,
      status: true,
      emailVerifiedAt: true,
    },
  });

  if (!user || user.status !== "ACTIVE") {
    throw httpError("Account is not active", 403);
  }

  if (user.emailVerifiedAt) {
    throw httpError("Email is already verified", 409);
  }

  return user;
}

async function sendOtp(userId) {
  const user = await getEligibleUser(userId);
  const now = new Date();

  const latest = await prisma.emailVerificationOtp.findFirst({
    where: { userId },
    orderBy: { createdAt: "desc" },
  });

  if (
    latest &&
    now.getTime() - latest.createdAt.getTime() < RESEND_COOLDOWN_MS
  ) {
    throw httpError(
      "Please wait 60 seconds before requesting another code",
      429
    );
  }

  const otp = crypto.randomInt(0, 1000000)
    .toString()
    .padStart(6, "0");

  const record = await prisma.$transaction(async (tx) => {
    await tx.emailVerificationOtp.updateMany({
      where: {
        userId,
        consumedAt: null,
      },
      data: {
        consumedAt: now,
      },
    });

    return tx.emailVerificationOtp.create({
      data: {
        userId,
        codeHash: hashOtp(userId, otp),
        expiresAt: new Date(now.getTime() + OTP_EXPIRY_MS),
      },
    });
  });

  try {
    await sendVerificationOTP(user.email, otp);
  } catch (error) {
    await prisma.emailVerificationOtp.updateMany({
      where: {
        id: record.id,
        consumedAt: null,
      },
      data: {
        consumedAt: new Date(),
      },
    });

    throw httpError(
      "Unable to send verification email. Please try again.",
      503
    );
  }

  return {
    message: "Verification code sent to your registered email",
    expiresInSeconds: 300,
    resendAfterSeconds: 60,
  };
}

async function verifyOtp(userId, code) {
  await getEligibleUser(userId);

  const latest = await prisma.emailVerificationOtp.findFirst({
    where: {
      userId,
      consumedAt: null,
    },
    orderBy: {
      createdAt: "desc",
    },
  });

  if (!latest) {
    throw httpError(
      "No active verification code. Request a new code.",
      400
    );
  }

  const now = new Date();

  if (latest.expiresAt <= now) {
    throw httpError("Verification code expired", 400);
  }

  if (latest.attempts >= MAX_ATTEMPTS) {
    throw httpError(
      "Too many attempts. Request a new code.",
      429
    );
  }

  const suppliedHash = Buffer.from(hashOtp(userId, code), "hex");
  const expectedHash = Buffer.from(latest.codeHash, "hex");

  const matches =
    suppliedHash.length === expectedHash.length &&
    crypto.timingSafeEqual(suppliedHash, expectedHash);

  if (!matches) {
    const updated = await prisma.emailVerificationOtp.updateMany({
      where: {
        id: latest.id,
        consumedAt: null,
        expiresAt: { gt: now },
        attempts: latest.attempts,
      },
      data: {
        attempts: { increment: 1 },
      },
    });

    if (updated.count !== 1) {
      throw httpError(
        "Verification code state changed. Please retry.",
        409
      );
    }

    throw httpError("Invalid verification code", 400);
  }

  await prisma.$transaction(async (tx) => {
    const updated = await tx.emailVerificationOtp.updateMany({
      where: {
        id: latest.id,
        consumedAt: null,
        expiresAt: { gt: now },
        attempts: latest.attempts,
      },
      data: {
        consumedAt: now,
      },
    });

    if (updated.count !== 1) {
      throw httpError(
        "Verification code is no longer valid. Please retry.",
        409
      );
    }

    const verified = await tx.user.updateMany({
      where: {
        id: userId,
        status: "ACTIVE",
        emailVerifiedAt: null,
      },
      data: {
        emailVerifiedAt: now,
      },
    });

    if (verified.count !== 1) {
      throw httpError("Email cannot be verified", 409);
    }

    await tx.emailVerificationOtp.updateMany({
      where: {
        userId,
        consumedAt: null,
      },
      data: {
        consumedAt: now,
      },
    });
  });

  return {
    message: "Email verified successfully",
    emailVerifiedAt: now,
  };
}

module.exports = {
  sendOtp,
  verifyOtp,
};