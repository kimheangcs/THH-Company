const express = require("express");

const authMiddleware = require("../middlewares/authMiddleware");
const roleCheckMiddleware = require("../middlewares/roleCheckMiddleware");
const projectController = require("../controllers/projectController");

const router = express.Router();

router.use(authMiddleware);

// Admin and Manager can create projects.
router.post(
  "/",
  roleCheckMiddleware("ADMIN", "MANAGER"),
  projectController.create
);

// All authenticated users can view permitted projects.
router.get("/", projectController.list);
router.get("/:id", projectController.getById);

// Admin and project lead Manager can update projects.
router.patch(
  "/:id",
  roleCheckMiddleware("ADMIN", "MANAGER"),
  projectController.update
);

router.patch(
  "/:id/status",
  roleCheckMiddleware("ADMIN", "MANAGER"),
  projectController.changeStatus
);

module.exports = router;