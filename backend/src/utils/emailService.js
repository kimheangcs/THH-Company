const nodemailer = require("nodemailer");

function createTransporter() {
  const {
    SMTP_HOST,
    SMTP_PORT,
    SMTP_SECURE,
    SMTP_USER,
    SMTP_APP_PASSWORD,
  } = process.env;

  if (!SMTP_USER || !SMTP_APP_PASSWORD) {
    throw new Error("Gmail SMTP credentials are missing.");
  }

  return nodemailer.createTransport({
    host: SMTP_HOST || "smtp.gmail.com",
    port: Number(SMTP_PORT || 465),
    secure: SMTP_SECURE !== "false",
    auth: {
      user: SMTP_USER,
      pass: SMTP_APP_PASSWORD.replace(/\s/g, ""),
    },
  });
}

async function verifyEmailConnection() {
  const transporter = createTransporter();
  await transporter.verify();

  return true;
}

async function sendVerificationOTP(email, otp) {
  if (!/^\d{6}$/.test(String(otp))) {
    throw new Error("OTP must contain exactly 6 digits.");
  }

  const transporter = createTransporter();

  return transporter.sendMail({
    from: {
      name: process.env.SMTP_FROM_NAME || "THH Company",
      address: process.env.SMTP_USER,
    },
    to: email,
    subject: "THH Company - Verify Your Email",
    text: [
      "Welcome to THH Company!",
      "",
      `Your email verification code is: ${otp}`,
      "",
      "This code expires in 5 minutes.",
      "If you did not request this code, please ignore this email.",
    ].join("\n"),
    html: `
      <div style="font-family:Arial,sans-serif;max-width:520px;margin:auto;padding:24px">
        <h2>THH Company</h2>
        <p>Welcome! Please verify your email address.</p>
        <p>Your verification code is:</p>
        <div style="font-size:32px;font-weight:bold;letter-spacing:8px;
                    padding:18px;background:#f3f4f6;text-align:center;
                    border-radius:8px">
          ${otp}
        </div>
        <p>This code expires in <strong>5 minutes</strong>.</p>
        <p>If you did not request this code, please ignore this email.</p>
      </div>
    `,
  });
}

module.exports = {
  createTransporter,
  verifyEmailConnection,
  sendVerificationOTP,
};