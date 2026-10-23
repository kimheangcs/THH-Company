const express = require("express");

const authMiddleware = require(
  "../middlewares/authMiddleware"
);

const uploadMiddleware = require(
  "../middlewares/taskUploadMiddleware"
);

const controller = require(
  "../controllers/taskAttachmentController"
);

const router = express.Router();

router.use(authMiddleware);

router.post(
  "/:taskId/attachments",
  uploadMiddleware,
  controller.upload
);

router.get(
  "/:taskId/attachments",
  controller.list
);

router.get(
  "/:taskId/attachments/:attachmentId/download",
  controller.download
);

router.delete(
  "/:taskId/attachments/:attachmentId",
  controller.remove
);

module.exports = router;