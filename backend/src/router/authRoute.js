const express = require("express");
const rateLimit = require("express-rate-limit");

const authController = require("../controllers/authController");
const authMiddleware = require("../middlewares/authMiddleware");
const emailVerificationMiddleware = require(
  "../middlewares/emailVerificationMiddleware"
);
const roleCheckMiddleware = require("../middlewares/roleCheckMiddleware");

const router = express.Router();

const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 20,
  standardHeaders: "draft-7",
  legacyHeaders: false,
  message: {
    success: false,
    message: "Too many login attempts. Please try again later.",
  },
});

const otpLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 10,
  standardHeaders: "draft-7",
  legacyHeaders: false,
  message: {
    success: false,
    message: "Too many OTP requests. Please try again later.",
  },
});

router.post(
  "/login",
  loginLimiter,
  authController.login
);

router.get(
  "/me",
  authMiddleware,
  authController.me
);

router.post(
  "/logout",
  authMiddleware,
  authController.logout
);

router.post(
  "/send-verification-otp",
  otpLimiter,
  emailVerificationMiddleware,
  authController.sendVerificationOtp
);

router.post(
  "/resend-verification-otp",
  otpLimiter,
  emailVerificationMiddleware,
  authController.sendVerificationOtp
);

router.post(
  "/verify-email",
  otpLimiter,
  emailVerificationMiddleware,
  authController.verifyEmail
);

router.get(
  "/admin-test",
  authMiddleware,
  roleCheckMiddleware("ADMIN"),
  (req, res) => {
    res.json({
      success: true,
      message: "Admin access granted",
    });
  }
);

module.exports = router;