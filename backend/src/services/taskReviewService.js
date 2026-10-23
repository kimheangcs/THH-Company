const prisma = require("../config/db");

const {
  positiveId,
  validateReview,
} = require("../validator/taskReviewValidator");

const {
  createNotifications,
} = require("./notificationService");

const {
  recordActivity,
} = require("./activityLogService");

function httpError(statusCode, message) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

const reviewInclude = {
  reviewer: {
    select: {
      id: true,
      firstName: true,
      lastName: true,
      email: true,
      role: true,
    },
  },
};

async function getTaskAccess(taskId, actor) {
  const id = positiveId(taskId, "Task ID");

  const task = await prisma.task.findUnique({
    where: { id },
    include: {
      project: {
        select: {
          id: true,
          status: true,
          leadManagerId: true,
          ownerDepartmentId: true,
          departments: {
            select: { departmentId: true },
          },
        },
      },
      assignments: {
        select: { userId: true },
      },
    },
  });

  if (!task) {
    throw httpError(404, "Task not found");
  }

  const assigned = task.assignments.some(
    (assignment) => assignment.userId === actor.id
  );

  const isAdmin = actor.role === "ADMIN";

  const managerCanView =
    actor.role === "MANAGER" &&
    actor.departmentId != null &&
    (
      task.project.ownerDepartmentId === actor.departmentId ||
      task.project.departments.some(
        (department) =>
          department.departmentId === actor.departmentId
      )
    );

  const managerCanManage =
    actor.role === "MANAGER" &&
    task.project.leadManagerId === actor.id &&
    task.project.ownerDepartmentId === actor.departmentId;

  const canView =
    isAdmin ||
    managerCanView ||
    (actor.role === "EMPLOYEE" && assigned);

  if (!canView) {
    throw httpError(404, "Task not found");
  }

  return {
    task,
    assigned,
    canReview: isAdmin || managerCanManage,
  };
}

async function listReviews(taskId, actor) {
  const access = await getTaskAccess(taskId, actor);

  return prisma.taskReview.findMany({
    where: {
      taskId: access.task.id,
    },
    include: reviewInclude,
    orderBy: [
      { reviewedAt: "desc" },
      { id: "desc" },
    ],
  });
}

async function reviewTask(taskId, body, actor) {
  const data = validateReview(body);

  const access = await getTaskAccess(taskId, actor);
  const task = access.task;

  if (!access.canReview) {
    throw httpError(
      403,
      "Only an admin or the authorized project lead can review tasks"
    );
  }

  if (
    task.createdById === actor.id ||
    access.assigned
  ) {
    throw httpError(
      403,
      "You cannot review a task you created or are assigned to"
    );
  }

  if (task.status !== "IN_REVIEW") {
    throw httpError(
      400,
      "Task must be IN_REVIEW before a decision can be made"
    );
  }

  if (
    ["COMPLETED", "CANCELLED"].includes(
      task.project.status
    )
  ) {
    throw httpError(
      400,
      "Cannot review tasks in a closed project"
    );
  }

  const nextStatus =
    data.decision === "APPROVED"
      ? "COMPLETED"
      : "IN_PROGRESS";

  return prisma.$transaction(async (tx) => {
    const result = await tx.task.updateMany({
      where: {
        id: task.id,
        status: "IN_REVIEW",
        project: {
          status: {
            notIn: ["COMPLETED", "CANCELLED"],
          },
        },
      },
      data: {
        status: nextStatus,
        ...(data.decision === "APPROVED"
          ? {
              progress: 100,
              completedAt: new Date(),
            }
          : {
              completedAt: null,
            }),
      },
    });

    if (result.count !== 1) {
      throw httpError(
        409,
        "Task review state changed. Refresh and try again."
      );
    }

    const review = await tx.taskReview.create({
      data: {
        taskId: task.id,
        reviewerId: actor.id,
        decision: data.decision,
        comment: data.comment,
      },
      include: reviewInclude,
    });

    const updatedTask = await tx.task.findUnique({
      where: { id: task.id },
      include: {
        assignments: {
          select: { userId: true },
        },
      },
    });

    const recipientIds = [
      ...new Set(
        updatedTask.assignments
          .map((assignment) => assignment.userId)
          .filter((userId) => userId !== actor.id)
      ),
    ];

    const approved =
      data.decision === "APPROVED";

    await createNotifications(
      recipientIds.map((userId) => ({
        userId,
        type: "TASK_UPDATED",
        title: approved
          ? "Task approved"
          : "Task changes requested",
        message: approved
          ? `Your task "${updatedTask.title}" has been approved.`
          : `Changes were requested for task "${updatedTask.title}". ${
              data.comment || ""
            }`,
        targetUrl: `/tasks/${task.id}`,
      })),
      tx
    );

    await recordActivity({
      db: tx,
      userId: actor.id,
      action: approved
        ? "TASK_APPROVED"
        : "TASK_CHANGES_REQUESTED",
      entityType: "TASK",
      entityId: task.id,
      details: {
        reviewId: review.id,
        decision: data.decision,
        status: {
          before: "IN_REVIEW",
          after: nextStatus,
        },
        // Review feedback remains in TaskReview.
      },
    });

    return {
      review,
      task: {
        id: updatedTask.id,
        projectId: updatedTask.projectId,
        title: updatedTask.title,
        status: updatedTask.status,
        progress: updatedTask.progress,
        completedAt: updatedTask.completedAt,
        updatedAt: updatedTask.updatedAt,
      },
    };
  });
}

module.exports = {
  listReviews,
  reviewTask,
};