const express = require("express");

const authMiddleware = require(
  "../middlewares/authMiddleware"
);

const roleCheckMiddleware = require(
  "../middlewares/roleCheckMiddleware"
);

const requestController = require(
  "../controllers/requestController"
);

const requestAttachmentRoute = require(
  "./requestAttachmentRoute"
);

const router = express.Router();

router.use(authMiddleware);

// Create request
router.post(
  "/",
  requestController.create
);

// List requests
router.get(
  "/",
  requestController.list
);

// Pending approvals
router.get(
  "/pending-approvals",
  roleCheckMiddleware("ADMIN", "MANAGER"),
  requestController.pendingApprovals
);

// Request attachments
router.use(
  "/:id/attachments",
  requestAttachmentRoute
);

// Request approval history
router.get(
  "/:id/history",
  requestController.getHistory
);

// View request
router.get(
  "/:id",
  requestController.getById
);

// Edit draft
router.patch(
  "/:id",
  requestController.updateDraft
);

// Submit request
router.post(
  "/:id/submit",
  requestController.submit
);

// Cancel request
router.post(
  "/:id/cancel",
  requestController.cancel
);

// Approve request
router.post(
  "/:id/approve",
  roleCheckMiddleware("ADMIN", "MANAGER"),
  requestController.approve
);

// Reject request
router.post(
  "/:id/reject",
  roleCheckMiddleware("ADMIN", "MANAGER"),
  requestController.reject
);

module.exports = router;