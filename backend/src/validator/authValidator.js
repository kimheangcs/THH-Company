function validateOtpInput(body) {
  const code = body?.code;

  if (typeof code !== "string" || !/^\d{6}$/.test(code)) {
    const error = new Error("A valid 6-digit OTP is required");
    error.statusCode = 400;
    throw error;
  }

  return code;
}

module.exports = {
  validateOtpInput,
};