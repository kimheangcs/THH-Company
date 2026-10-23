require("dotenv").config();

const {
  verifyEmailConnection,
  sendVerificationOTP,
} = require("../src/utils/emailService");

async function main() {
  console.log("Checking Gmail SMTP connection...");

  await verifyEmailConnection();

  console.log("SMTP connection successful.");

  const recipient = process.env.SMTP_TEST_RECIPIENT;

  if (!recipient) {
    console.log(
      "No SMTP_TEST_RECIPIENT configured. Skipping test email."
    );
    return;
  }

  // Test code only. Production OTPs will use secure random generation.
  const testOTP = "123456";

  await sendVerificationOTP(recipient, testOTP);

  console.log("Test verification email sent successfully.");
  console.log(`Recipient: ${recipient}`);
}

main().catch((error) => {
  console.error("Email test failed:", error.message);
  process.exitCode = 1;
});