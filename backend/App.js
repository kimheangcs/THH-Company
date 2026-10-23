require("dotenv").config();

const express = require("express");
const cors = require("cors");
const prisma = require("./src/config/db");
const authRoute = require("./src/router/authRoute");
const departmentRoute = require("./src/router/departmentRoute");
const userRoute = require("./src/router/userRoute");
const projectRoute = require("./src/router/projectRoute");
const taskRoute = require("./src/router/taskRoute");
const taskAttachmentRoute = require("./src/router/taskAttachmentRoute");
const taskReviewRoute = require("./src/router/taskReviewRoute");
const notificationRoute = require("./src/router/notificationRoute");
const activityLogRoute = require("./src/router/activityLogRoute");
const requestRoute = require("./src/router/requestRoute");

const app = express();
const PORT = Number(process.env.PORT || 3000);

app.disable("x-powered-by");

// Middleware
app.use(cors());
app.use(express.json({ limit: "1mb" }));
app.use(express.urlencoded({ extended: true }));

// API Routes
app.use("/api/auth", authRoute);
app.use("/api/departments", departmentRoute);
app.use("/api/users", userRoute);
app.use("/api/projects", projectRoute);
app.use("/api/tasks", taskRoute);
app.use("/api/tasks", taskAttachmentRoute);
app.use("/api/tasks", taskReviewRoute);
app.use("/api/notifications", notificationRoute);
app.use("/api/activity-logs", activityLogRoute);
app.use("/api/requests", requestRoute);

// Welcome
app.get("/", (req, res) => {
  res.json({
    success: true,
    message: "Welcome to THH Company API",
  });
});

// API health
app.get("/api/health", (req, res) => {
  res.json({
    success: true,
    message: "THH Company API is running",
    timestamp: new Date().toISOString(),
  });
});

// Database health
app.get("/api/health/database", async (req, res) => {
  try {
    await prisma.$queryRaw`SELECT 1`;

    res.json({
      success: true,
      message: "MySQL database connected successfully",
    });
  } catch (error) {
    console.error("Database error:", error);

    res.status(503).json({
      success: false,
      message: "Database connection failed",
    });
  }
});


// Not found
app.use((req, res) => {
  res.status(404).json({
    success: false,
    message: "API route not found",
  });
});

// Error handler
app.use((error, req, res, next) => {
  console.error("API error:", error);

  const status =
    Number.isInteger(error.statusCode) &&
    error.statusCode >= 400 &&
    error.statusCode <= 599
      ? error.statusCode
      : 500;

  res.status(status).json({
    success: false,
    message: status < 500 ? error.message : "Internal server error",
  });
});

async function startServer() {
  if (
    !process.env.JWT_SECRET ||
    process.env.JWT_SECRET.length < 32
  ) {
    console.error("Configure JWT_SECRET in .env");
    process.exit(1);
  }

  try {
    await prisma.$connect();
    console.log("MySQL database connected");

    const server = app.listen(PORT, "127.0.0.1", () => {
      console.log(
        `THH Company API running at http://127.0.0.1:${PORT}`
      );
    });

    async function shutdown() {
      server.close(async () => {
        await prisma.$disconnect();
        process.exit(0);
      });
    }

    process.on("SIGINT", shutdown);
    process.on("SIGTERM", shutdown);
  } catch (error) {
    console.error("Server startup failed:", error.message);
    await prisma.$disconnect();
    process.exit(1);
  }
}

startServer();