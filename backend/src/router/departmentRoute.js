const express = require("express");

const departmentController = require(
  "../controllers/departmentController"
);
const authMiddleware = require("../middlewares/authMiddleware");
const roleCheckMiddleware = require(
  "../middlewares/roleCheckMiddleware"
);

const router = express.Router();

// Every department endpoint requires authentication.
router.use(authMiddleware);

// Read permissions: ADMIN and MANAGER
router.get(
  "/",
  roleCheckMiddleware("ADMIN", "MANAGER"),
  departmentController.list
);

router.get(
  "/:id",
  roleCheckMiddleware("ADMIN", "MANAGER"),
  departmentController.getById
);

// Write permissions: ADMIN only
router.post(
  "/",
  roleCheckMiddleware("ADMIN"),
  departmentController.create
);

router.patch(
  "/:id/manager",
  roleCheckMiddleware("ADMIN"),
  departmentController.assignManager
);

router.patch(
  "/:id",
  roleCheckMiddleware("ADMIN"),
  departmentController.update
);

router.delete(
  "/:id",
  roleCheckMiddleware("ADMIN"),
  departmentController.remove
);

module.exports = router;