const userService = require("../services/userService");

const {
  validateUserId,
  validateCreateUser,
  validateUpdateUser,
  validateStatus,
  validatePasswordChange,
  validateListQuery,
} = require("../validator/userValidator");

async function create(req, res, next) {
  try {
    const input = validateCreateUser(req.body);
    const user = await userService.createUser(req.user, input);

    return res.status(201).json({
      success: true,
      message: "User created successfully",
      user,
    });
  } catch (error) {
    next(error);
  }
}

async function list(req, res, next) {
  try {
    const filters = validateListQuery(req.query);
    const users = await userService.listUsers(req.user, filters);

    return res.json({
      success: true,
      count: users.length,
      users,
    });
  } catch (error) {
    next(error);
  }
}

async function getById(req, res, next) {
  try {
    const id = validateUserId(req.params.id);
    const user = await userService.getUser(req.user, id);

    return res.json({
      success: true,
      user,
    });
  } catch (error) {
    next(error);
  }
}

async function update(req, res, next) {
  try {
    const id = validateUserId(req.params.id);
    const data = validateUpdateUser(req.body);

    const user = await userService.updateUser(req.user, id, data);

    return res.json({
      success: true,
      message: "User updated successfully",
      user,
    });
  } catch (error) {
    next(error);
  }
}

async function changeStatus(req, res, next) {
  try {
    const id = validateUserId(req.params.id);
    const status = validateStatus(req.body);

    const user = await userService.changeStatus(
      req.user,
      id,
      status
    );

    return res.json({
      success: true,
      message: "User status updated successfully",
      user,
    });
  } catch (error) {
    next(error);
  }
}

async function changePassword(req, res, next) {
  try {
    const id = validateUserId(req.params.id);
    const password = validatePasswordChange(req.body);

    const result = await userService.changePassword(
      req.user,
      id,
      password
    );

    return res.json({
      success: true,
      ...result,
    });
  } catch (error) {
    next(error);
  }
}

module.exports = {
  create,
  list,
  getById,
  update,
  changeStatus,
  changePassword,
};