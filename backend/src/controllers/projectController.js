const projectService = require("../services/projectService");

function handleError(error, next) {
  if (error.code === "P2002") {
    error.statusCode = 409;
    error.message = "Project code or unique field already exists";
  }

  if (error.code === "P2025") {
    error.statusCode = 404;
    error.message = "Project not found";
  }

  next(error);
}

async function create(req, res, next) {
  try {
    const project = await projectService.create(req.body, req.user);

    return res.status(201).json({
      success: true,
      message: "Project created successfully",
      data: project,
    });
  } catch (error) {
    handleError(error, next);
  }
}

async function list(req, res, next) {
  try {
    const result = await projectService.list(req.query, req.user);

    return res.json({
      success: true,
      data: result.projects,
      pagination: result.pagination,
    });
  } catch (error) {
    handleError(error, next);
  }
}

async function getById(req, res, next) {
  try {
    const project = await projectService.getById(
      req.params.id,
      req.user
    );

    return res.json({
      success: true,
      data: project,
    });
  } catch (error) {
    handleError(error, next);
  }
}

async function update(req, res, next) {
  try {
    const project = await projectService.update(
      req.params.id,
      req.body,
      req.user
    );

    return res.json({
      success: true,
      message: "Project updated successfully",
      data: project,
    });
  } catch (error) {
    handleError(error, next);
  }
}

async function changeStatus(req, res, next) {
  try {
    const project = await projectService.changeStatus(
      req.params.id,
      req.body?.status,
      req.user
    );

    return res.json({
      success: true,
      message: "Project status updated successfully",
      data: project,
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
  changeStatus,
};