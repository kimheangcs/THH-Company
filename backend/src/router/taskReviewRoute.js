const express = require("express");

const authMiddleware = require(
  "../middlewares/authMiddleware"
);

const roleCheckMiddleware = require(
  "../middlewares/roleCheckMiddleware"
);

const controller = require(
  "../controllers/taskReviewController"
);

const router = express.Router();

router.use(authMiddleware);

// All authorized task viewers can see review history.
router.get(
  "/:taskId/reviews",
  controller.list
);

// Only admins and managers can submit review decisions.
// The service also checks project leadership and
// prevents creators or assignees from reviewing.
router.post(
  "/:taskId/reviews",
  roleCheckMiddleware("ADMIN", "MANAGER"),
  controller.review
);

module.exports = router;