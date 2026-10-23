const express = require("express");

const authMiddleware = require(
  "../middlewares/authMiddleware"
);

const controller = require(
  "../controllers/notificationController"
);

const router = express.Router();

router.use(authMiddleware);

router.get(
  "/",
  controller.list
);

router.get(
  "/unread-count",
  controller.unreadCount
);

router.patch(
  "/read-all",
  controller.markAllAsRead
);

router.patch(
  "/:id/read",
  controller.markAsRead
);

router.delete(
  "/read",
  controller.removeAllRead
);

router.delete(
  "/:id",
  controller.remove
);

module.exports = router;