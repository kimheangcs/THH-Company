const express = require("express");

const authMiddleware = require("../middlewares/authMiddleware");
const roleCheckMiddleware = require(
  "../middlewares/roleCheckMiddleware"
);
const userController = require("../controllers/userController");

const router = express.Router();

router.use(authMiddleware);
router.use(roleCheckMiddleware("ADMIN", "MANAGER"));

router.post("/", userController.create);
router.get("/", userController.list);
router.get("/:id", userController.getById);

router.patch("/:id/status", userController.changeStatus);

router.patch(
  "/:id/password",
  roleCheckMiddleware("ADMIN"),
  userController.changePassword
);

router.patch("/:id", userController.update);

module.exports = router;