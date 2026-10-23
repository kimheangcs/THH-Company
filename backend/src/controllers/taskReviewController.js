const taskReviewService = require(
  "../services/taskReviewService"
);

async function list(req, res, next) {
  try {
    const reviews = await taskReviewService.listReviews(
      req.params.taskId,
      req.user
    );

    return res.json({
      success: true,
      data: reviews,
    });
  } catch (error) {
    next(error);
  }
}

async function review(req, res, next) {
  try {
    const result = await taskReviewService.reviewTask(
      req.params.taskId,
      req.body,
      req.user
    );

    return res.json({
      success: true,
      message:
        result.review.decision === "APPROVED"
          ? "Task approved successfully"
          : "Changes requested successfully",
      data: result,
    });
  } catch (error) {
    next(error);
  }
}

module.exports = {
  list,
  review,
};