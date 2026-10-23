const service = require(
  "../services/taskCollaborationService"
);

function handleError(error, next) {
  if (error.code === "P2025") {
    error.statusCode = 404;
    error.message = "Record not found";
  }

  if (error.code === "P2003") {
    error.statusCode = 400;
    error.message = "Invalid related record";
  }

  next(error);
}

async function execute(res, next, action, status = 200) {
  try {
    const data = await action();

    return res.status(status).json({
      success: true,
      data,
    });
  } catch (error) {
    handleError(error, next);
  }
}

function listComments(req, res, next) {
  return execute(res, next, () =>
    service.listComments(
      req.params.taskId,
      req.user
    )
  );
}

function createComment(req, res, next) {
  return execute(
    res,
    next,
    () =>
      service.createComment(
        req.params.taskId,
        req.body,
        req.user
      ),
    201
  );
}

function updateComment(req, res, next) {
  return execute(res, next, () =>
    service.updateComment(
      req.params.taskId,
      req.params.commentId,
      req.body,
      req.user
    )
  );
}

function deleteComment(req, res, next) {
  return execute(res, next, () =>
    service.deleteComment(
      req.params.taskId,
      req.params.commentId,
      req.user
    )
  );
}

function listChecklist(req, res, next) {
  return execute(res, next, () =>
    service.listChecklist(
      req.params.taskId,
      req.user
    )
  );
}

function createChecklist(req, res, next) {
  return execute(
    res,
    next,
    () =>
      service.createChecklist(
        req.params.taskId,
        req.body,
        req.user
      ),
    201
  );
}

function updateChecklist(req, res, next) {
  return execute(res, next, () =>
    service.updateChecklist(
      req.params.taskId,
      req.params.checklistId,
      req.body,
      req.user
    )
  );
}

function deleteChecklist(req, res, next) {
  return execute(res, next, () =>
    service.deleteChecklist(
      req.params.taskId,
      req.params.checklistId,
      req.user
    )
  );
}

module.exports = {
  listComments,
  createComment,
  updateComment,
  deleteComment,
  listChecklist,
  createChecklist,
  updateChecklist,
  deleteChecklist,
};