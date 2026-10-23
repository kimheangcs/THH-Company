function getDefaultPassword() {
  const password = process.env.DEFAULT_USER_PASSWORD;
  if (!password || password.length < 12 || Buffer.byteLength(password, "utf8") > 72) {
    throw new Error("Configure DEFAULT_USER_PASSWORD in .env (12-72 UTF-8 bytes)");
  }
  return password;
}

module.exports = { getDefaultPassword };
