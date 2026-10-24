const authService = require("../services/authService");
const emailOtpService = require("../services/emailOtpService");
const { validateOtpInput } = require("../validator/authValidator");

async function login(req, res, next) {
  try {
    const { email, password } = req.body || {};

    if (
      typeof email !== "string" ||
      typeof password !== "string" ||
      !email.trim() ||
      !password
    ) {
      return res.status(400).json({
        success: false,
        message: "Email and password are required",
      });
    }

    const result = await authService.login(email, password);

    if (result.requiresEmailVerification) {
      return res.json({
        success: true,
        message: "Email verification required",
        ...result,
      });
    }

    return res.json({
      success: true,
      message: result.requiresPasswordChange ? "Password change required" : "Login successful",
      ...result,
    });
  } catch (error) {
    next(error);
  }
}

async function me(req, res, next) {
  try {
    const user = await authService.getProfile(req.user.id);

    return res.json({
      success: true,
      user,
    });
  } catch (error) {
    next(error);
  }
}

async function logout(req, res, next) {
  try {
    await authService.logout(req.sessionId);

    return res.json({
      success: true,
      message: "Logged out successfully",
    });
  } catch (error) {
    next(error);
  }
}

async function sendVerificationOtp(req, res, next) {
  try {
    const result = await emailOtpService.sendOtp(req.user.id);

    return res.json({
      success: true,
      ...result,
    });
  } catch (error) {
    next(error);
  }
}

async function verifyEmail(req, res, next) {
  try {
    const code = validateOtpInput(req.body);
    const result = await emailOtpService.verifyOtp(req.user.id, code);

    return res.json({
      success: true,
      ...result,
    });
  } catch (error) {
    next(error);
  }
}

async function changeInitialPassword(req, res, next) {
  try {
    const match = /^Bearer\s+(.+)$/i.exec(req.headers.authorization || "");
    if (!match) return res.status(401).json({ success: false, message: "Password change authentication required" });
    const { validatePasswordChange } = require("../validator/userValidator");
    const password = validatePasswordChange(req.body);
    const result = await authService.changeInitialPassword(match[1], password);
    return res.json({ success: true, ...result });
  } catch (error) { next(error); }
}

module.exports = {
  changeInitialPassword,
  login,
  me,
  logout,
  sendVerificationOtp,
  verifyEmail,
};