const express = require("express");

const uploadMiddleware = require(
  "../middlewares/taskUploadMiddleware"
);

const controller = require(
  "../controllers/requestAttachmentController"
);

const router = express.Router({
  mergeParams: true,
});

// Authentication is enforced by the parent request router.

// Upload attachment
router.post(
  "/",
  uploadMiddleware,
  controller.upload
);

// List attachments
router.get(
  "/",
  controller.list
);

// Download attachment
router.get(
  "/:attachmentId/download",
  controller.download
);

// Delete attachment
router.delete(
  "/:attachmentId",
  controller.remove
);

module.exports = router;