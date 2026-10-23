const jwt = require("jsonwebtoken");
const prisma = require("../config/db");
const { hashToken } = require("../utils/generateToken");

async function emailVerificationMiddleware(req, res, next) {
  try {
    const header = req.headers.authorization || "";
    const match = /^Bearer\s+(.+)$/i.exec(header);

    if (!match) {
      return res.status(401).json({
        success: false,
        message: "Verification authentication required",
      });
    }

    const token = match[1];

    const payload = jwt.verify(token, process.env.JWT_SECRET, {
      algorithms: ["HS256"],
    });

    if (!Number.isInteger(payload.userId)) {
      return res.status(401).json({
        success: false,
        message: "Invalid verification token",
      });
    }

    if (
      payload.type !== "email_verification" &&
      payload.type !== "access"
    ) {
      return res.status(401).json({
        success: false,
        message: "Invalid token type",
      });
    }

    if (payload.type === "access") {
      if (typeof payload.sessionId !== "string") {
        return res.status(401).json({
          success: false,
          message: "Invalid session",
        });
      }

      const session = await prisma.session.findUnique({
        where: { id: payload.sessionId },
      });

      if (
        !session ||
        session.userId !== payload.userId ||
        session.tokenHash !== hashToken(token) ||
        session.revokedAt ||
        session.expiresAt <= new Date()
      ) {
        return res.status(401).json({
          success: false,
          message: "Session expired or revoked",
        });
      }
    }

    const user = await prisma.user.findUnique({
      where: { id: payload.userId },
      select: {
        id: true,
        email: true,
        status: true,
        emailVerifiedAt: true,
      },
    });

    if (!user || user.status !== "ACTIVE") {
      return res.status(403).json({
        success: false,
        message: "Account is not active",
      });
    }

    req.user = user;
    req.verificationTokenType = payload.type;

    next();
  } catch (error) {
    if (
      error instanceof jwt.JsonWebTokenError ||
      error instanceof jwt.TokenExpiredError ||
      error instanceof jwt.NotBeforeError
    ) {
      return res.status(401).json({
        success: false,
        message: "Invalid or expired verification token",
      });
    }

    next(error);
  }
}

module.exports = emailVerificationMiddleware;