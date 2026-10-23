require("dotenv").config();

const bcrypt = require("bcryptjs");
const readline = require("readline");
const prisma = require("../src/config/db");

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
});

function ask(question) {
  return new Promise((resolve) => {
    rl.question(question, resolve);
  });
}

async function main() {
  console.log("\n==================================");
  console.log("THH COMPANY - FIRST ADMIN SETUP");
  console.log("==================================\n");

  const existingAdmin = await prisma.user.findFirst({
    where: {
      role: "ADMIN",
    },
    select: {
      id: true,
    },
  });

  if (existingAdmin) {
    console.log("An Admin account already exists.");
    console.log("No new account was created.");
    return;
  }

  const firstName = (await ask("First name: ")).trim();
  const lastName = (await ask("Last name: ")).trim();
  const email = (await ask("Email: ")).trim().toLowerCase();

  if (!firstName || !lastName) {
    throw new Error("First name and last name are required.");
  }

  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new Error("Invalid email address.");
  }

  const existingEmail = await prisma.user.findUnique({
    where: { email },
    select: { id: true },
  });

  if (existingEmail) {
    throw new Error("This email is already registered.");
  }

  // Password input is visible in the terminal.
  const password = await ask("Password (minimum 12 characters): ");
  const confirmPassword = await ask("Confirm password: ");

  if (password.length < 12) {
    throw new Error("Password must be at least 12 characters.");
  }

  if (password !== confirmPassword) {
    throw new Error("Passwords do not match.");
  }

  const passwordHash = await bcrypt.hash(password, 12);

  const admin = await prisma.$transaction(async (tx) => {
    const adminCount = await tx.user.count({
      where: { role: "ADMIN" },
    });

    if (adminCount > 0) {
      throw new Error("An Admin account already exists.");
    }

    return tx.user.create({
      data: {
        firstName,
        lastName,
        email,
        passwordHash,
        role: "ADMIN",
        status: "ACTIVE",
        canApproveManagerRequests: true,
      },
      select: {
        id: true,
        firstName: true,
        lastName: true,
        email: true,
        role: true,
        status: true,
      },
    });
  });

  console.log("\n==================================");
  console.log("ADMIN CREATED SUCCESSFULLY");
  console.log("==================================");
  console.log(admin);
}

main()
  .catch((error) => {
    console.error("\nSetup failed:", error.message);
    process.exitCode = 1;
  })
  .finally(async () => {
    rl.close();
    await prisma.$disconnect();
  });