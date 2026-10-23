const express = require("express");

const authMiddleware = require(
  "../middlewares/authMiddleware"
);

const roleCheckMiddleware = require(
  "../middlewares/roleCheckMiddleware"
);

const controller = require(
  "../controllers/activityLogController"
);

const router = express.Router();

router.use(authMiddleware);

// Accessible by all authenticated users.
// Must appear before the /:id route.
router.get(
  "/my-activity",
  controller.myActivity
);

// Admin-only audit endpoints.
router.get(
  "/",
  roleCheckMiddleware("ADMIN"),
  controller.list
);

router.get(
  "/entity/:entityType/:entityId",
  roleCheckMiddleware("ADMIN"),
  controller.getEntityHistory
);

router.get(
  "/:id",
  roleCheckMiddleware("ADMIN"),
  controller.getById
);

module.exports = router;