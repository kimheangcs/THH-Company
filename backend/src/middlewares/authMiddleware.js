const jwt = require("jsonwebtoken");
const prisma = require("../config/db");
const { hashToken } = require("../utils/generateToken");

async function authMiddleware(req, res, next) {
  try {
    const header = req.headers.authorization || "";
    const match = /^Bearer\s+(.+)$/i.exec(header);

    if (!match) {
      return res.status(401).json({
        success: false,
        message: "Authentication required",
      });
    }

    const token = match[1];

    const payload = jwt.verify(
      token,
      process.env.JWT_SECRET,
      { algorithms: ["HS256"] }
    );

    if (
      payload.type !== "access" ||
      !Number.isInteger(payload.userId) ||
      typeof payload.sessionId !== "string"
    ) {
      return res.status(401).json({
        success: false,
        message: "Invalid token",
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

    const user = await prisma.user.findUnique({
      where: { id: payload.userId },
      select: {
        id: true,
        firstName: true,
        lastName: true,
        email: true,
        emailVerifiedAt: true,
        mustChangePassword: true,
        role: true,
        status: true,
        departmentId: true,
        canApproveManagerRequests: true,
      },
    });

    if (!user || user.status !== "ACTIVE") {
      return res.status(403).json({
        success: false,
        message: "Account is not active",
      });
    }

    if (!user.emailVerifiedAt) {
      return res.status(403).json({
        success: false,
        message: "Email verification required",
        requiresEmailVerification: true,
      });
    }

    if (user.mustChangePassword) {
      return res.status(403).json({ success: false, message: "Password change required", requiresPasswordChange: true });
    }

    req.user = user;
    req.sessionId = session.id;

    next();
  } catch (error) {
    if (
      error instanceof jwt.JsonWebTokenError ||
      error instanceof jwt.TokenExpiredError ||
      error instanceof jwt.NotBeforeError
    ) {
      return res.status(401).json({
        success: false,
        message: "Invalid or expired token",
      });
    }

    next(error);
  }
}

module.exports = authMiddleware;