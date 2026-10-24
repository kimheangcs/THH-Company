const jwt = require("jsonwebtoken");
const crypto = require("crypto");

function generateToken(userId, sessionId) {
  return jwt.sign(
    {
      userId,
      sessionId,
      type: "access",
    },
    process.env.JWT_SECRET,
    {
      algorithm: "HS256",
      expiresIn: process.env.JWT_EXPIRES_IN || "8h",
    }
  );
}

function generateEmailVerificationToken(userId) {
  return jwt.sign(
    {
      userId,
      type: "email_verification",
    },
    process.env.JWT_SECRET,
    {
      algorithm: "HS256",
      expiresIn: "10m",
    }
  );
}

function generatePasswordChangeToken(user) {
  return jwt.sign(
    { userId: user.id, type: "password_change", passwordVersion: hashToken(user.passwordHash) },
    process.env.JWT_SECRET,
    { algorithm: "HS256", expiresIn: "10m" }
  );
}

function hashToken(token) {
  return crypto
    .createHash("sha256")
    .update(token)
    .digest("hex");
}

module.exports = {
  generatePasswordChangeToken,
  generateToken,
  generateEmailVerificationToken,
  hashToken,
};