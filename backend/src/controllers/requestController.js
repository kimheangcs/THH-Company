const requestService = require("../services/requestService");

function handleError(error, next) {
  if (error.code === "P2002") {
    error.statusCode = 409;
    error.message =
      "Request already exists or a unique field conflicts";
  }

  if (error.code === "P2025") {
    error.statusCode = 404;
    error.message = "Request or approval step not found";
  }

  next(error);
}

async function create(req, res, next) {
  try {
    const request = await requestService.create(
      req.body,
      req.user
    );

    return res.status(201).json({
      success: true,
      message: "Request created successfully",
      data: request,
    });
  } catch (error) {
    handleError(error, next);
  }
}

async function list(req, res, next) {
  try {
    const result = await requestService.list(
      req.query,
      req.user
    );

    return res.json({
      success: true,
      data: result.requests,
      pagination: result.pagination,
    });
  } catch (error) {
    handleError(error, next);
  }
}

async function getById(req, res, next) {
  try {
    const request = await requestService.getById(
      req.params.id,
      req.user
    );

    return res.json({
      success: true,
      data: request,
    });
  } catch (error) {
    handleError(error, next);
  }
}

async function submit(req, res, next) {
  try {
    const request = await requestService.submit(
      req.params.id,
      req.user
    );

    return res.json({
      success: true,
      message: "Request submitted successfully",
      data: request,
    });
  } catch (error) {
    handleError(error, next);
  }
}

async function pendingApprovals(req, res, next) {
  try {
    const result = await requestService.pendingApprovals(
      req.query,
      req.user
    );

    return res.json({
      success: true,
      data: result.requests,
      pagination: result.pagination,
    });
  } catch (error) {
    handleError(error, next);
  }
}

async function approve(req, res, next) {
  try {
    const request = await requestService.approve(
      req.params.id,
      req.body,
      req.user
    );

    return res.json({
      success: true,
      message: "Request approved successfully",
      data: request,
    });
  } catch (error) {
    handleError(error, next);
  }
}

async function reject(req, res, next) {
  try {
    const request = await requestService.reject(
      req.params.id,
      req.body,
      req.user
    );

    return res.json({
      success: true,
      message: "Request rejected successfully",
      data: request,
    });
  } catch (error) {
    handleError(error, next);
  }
}

async function updateDraft(req, res, next) {
  try {
    const request = await requestService.updateDraft(
      req.params.id,
      req.body,
      req.user
    );

    return res.json({
      success: true,
      message: "Draft request updated successfully",
      data: request,
    });
  } catch (error) {
    handleError(error, next);
  }
}

async function cancel(req, res, next) {
  try {
    const request = await requestService.cancel(
      req.params.id,
      req.user
    );

    return res.json({
      success: true,
      message: "Request cancelled successfully",
      data: request,
    });
  } catch (error) {
    handleError(error, next);
  }
}

async function getHistory(req, res, next) {
  try {
    const history = await requestService.getHistory(
      req.params.id,
      req.user
    );

    return res.json({
      success: true,
      data: history,
    });
  } catch (error) {
    handleError(error, next);
  }
}

module.exports = {
  create,
  list,
  getById,
  submit,
  pendingApprovals,
  approve,
  reject,
  updateDraft,
  cancel,
  getHistory,
};