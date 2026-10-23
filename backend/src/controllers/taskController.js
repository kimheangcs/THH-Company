const taskService = require("../services/taskService");

function handleError(error, next) {
  if (error.code === "P2025") {
    error.statusCode = 404;
    error.message = "Task or related record not found";
  }

  if (error.code === "P2003") {
    error.statusCode = 400;
    error.message = "Invalid related record";
  }

  next(error);
}

async function create(req, res, next) {
  try {
    const task = await taskService.create(req.body, req.user);

    res.status(201).json({
      success: true,
      message: "Task created successfully",
      data: task,
    });
  } catch (error) {
    handleError(error, next);
  }
}

async function list(req, res, next) {
  try {
    const result = await taskService.list(req.query, req.user);

    res.json({
      success: true,
      data: result.tasks,
      pagination: result.pagination,
    });
  } catch (error) {
    handleError(error, next);
  }
}

async function getById(req, res, next) {
  try {
    const task = await taskService.getById(
      req.params.id,
      req.user
    );

    res.json({
      success: true,
      data: task,
    });
  } catch (error) {
    handleError(error, next);
  }
}

async function update(req, res, next) {
  try {
    const task = await taskService.update(
      req.params.id,
      req.body,
      req.user
    );

    res.json({
      success: true,
      message: "Task updated successfully",
      data: task,
    });
  } catch (error) {
    handleError(error, next);
  }
}

async function assign(req, res, next) {
  try {
    const task = await taskService.assign(
      req.params.id,
      req.body,
      req.user
    );

    res.json({
      success: true,
      message: "Task assignments updated successfully",
      data: task,
    });
  } catch (error) {
    handleError(error, next);
  }
}

async function updateProgress(req, res, next) {
  try {
    const task = await taskService.updateProgress(
      req.params.id,
      req.body,
      req.user
    );

    res.json({
      success: true,
      message: "Task progress updated successfully",
      data: task,
    });
  } catch (error) {
    handleError(error, next);
  }
}

async function submitForReview(req, res, next) {
  try {
    const task = await taskService.submitForReview(
      req.params.id,
      req.user
    );

    res.json({
      success: true,
      message: "Task submitted for review",
      data: task,
    });
  } catch (error) {
    handleError(error, next);
  }
}

module.exports = {
  create,
  list,
  getById,
  update,
  assign,
  updateProgress,
  submitForReview,
};