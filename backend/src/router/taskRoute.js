const express = require("express");

const authMiddleware = require(
  "../middlewares/authMiddleware"
);

const roleCheckMiddleware = require(
  "../middlewares/roleCheckMiddleware"
);

const taskController = require(
  "../controllers/taskController"
);

const collaborationController = require(
  "../controllers/taskCollaborationController"
);

const router = express.Router();

router.use(authMiddleware);

// --------------------------------------------------
// Task Management
// --------------------------------------------------

router.post(
  "/",
  roleCheckMiddleware("ADMIN", "MANAGER"),
  taskController.create
);

router.get("/", taskController.list);

router.patch(
  "/:id/assign",
  roleCheckMiddleware("ADMIN", "MANAGER"),
  taskController.assign
);

router.patch(
  "/:id/progress",
  taskController.updateProgress
);

router.post(
  "/:id/submit-review",
  taskController.submitForReview
);

router.patch(
  "/:id",
  roleCheckMiddleware("ADMIN", "MANAGER"),
  taskController.update
);

router.get("/:id", taskController.getById);

// --------------------------------------------------
// Task Comments
// --------------------------------------------------

router.get(
  "/:taskId/comments",
  collaborationController.listComments
);

router.post(
  "/:taskId/comments",
  collaborationController.createComment
);

router.patch(
  "/:taskId/comments/:commentId",
  collaborationController.updateComment
);

router.delete(
  "/:taskId/comments/:commentId",
  collaborationController.deleteComment
);

// --------------------------------------------------
// Task Checklist
// --------------------------------------------------

router.get(
  "/:taskId/checklist",
  collaborationController.listChecklist
);

router.post(
  "/:taskId/checklist",
  roleCheckMiddleware("ADMIN", "MANAGER"),
  collaborationController.createChecklist
);

router.patch(
  "/:taskId/checklist/:checklistId",
  collaborationController.updateChecklist
);

router.delete(
  "/:taskId/checklist/:checklistId",
  roleCheckMiddleware("ADMIN", "MANAGER"),
  collaborationController.deleteChecklist
);

module.exports = router;