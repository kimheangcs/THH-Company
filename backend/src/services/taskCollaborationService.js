const prisma = require("../config/db");

const {
  positiveId,
  validateComment,
  validateChecklist,
} = require("../validator/taskCollaborationValidator");

const {
  recordActivity,
} = require("./activityLogService");

function httpError(statusCode, message) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

const userSelect = {
  id: true,
  firstName: true,
  lastName: true,
  email: true,
};

const commentInclude = {
  user: {
    select: userSelect,
  },
};

const checklistInclude = {
  createdBy: {
    select: userSelect,
  },
};

// --------------------------------------------------
// Task access and permissions
// --------------------------------------------------

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
    (item) => item.userId === actor.id
  );

  const projectDepartmentIds = [
    task.project.ownerDepartmentId,
    ...task.project.departments.map(
      (item) => item.departmentId
    ),
  ];

  const managerCanView =
    actor.role === "MANAGER" &&
    actor.departmentId !== null &&
    projectDepartmentIds.includes(actor.departmentId);

  const managerCanManage =
    actor.role === "MANAGER" &&
    task.project.leadManagerId === actor.id &&
    task.project.ownerDepartmentId === actor.departmentId;

  const isAdmin = actor.role === "ADMIN";

  const canView =
    isAdmin ||
    managerCanView ||
    (actor.role === "EMPLOYEE" && assigned);

  if (!canView) {
    throw httpError(404, "Task not found");
  }

  const canCollaborate =
    isAdmin ||
    managerCanManage ||
    assigned;

  const canManage =
    isAdmin ||
    managerCanManage;

  return {
    task,
    canView,
    canCollaborate,
    canManage,
  };
}

function requireCollaboration(access) {
  if (!access.canCollaborate) {
    throw httpError(
      403,
      "You cannot collaborate on this task"
    );
  }

  if (
    ["COMPLETED", "CANCELLED"].includes(
      access.task.status
    ) ||
    ["COMPLETED", "CANCELLED"].includes(
      access.task.project.status
    )
  ) {
    throw httpError(
      400,
      "This task or project is closed"
    );
  }
}

function requireChecklistManagement(access) {
  if (!access.canManage) {
    throw httpError(
      403,
      "Only the project lead or an admin can manage checklist items"
    );
  }

  requireCollaboration(access);
}

// --------------------------------------------------
// Audit helpers
// --------------------------------------------------

async function logTaskActivity(
  tx,
  actor,
  taskId,
  action,
  details
) {
  return recordActivity({
    db: tx,
    userId: actor.id,
    action,
    entityType: "TASK",
    entityId: taskId,
    details,
  });
}

function getChecklistChanges(existing, data) {
  const changes = {};

  for (const field of [
    "title",
    "position",
    "isCompleted",
  ]) {
    if (
      !Object.prototype.hasOwnProperty.call(
        data,
        field
      )
    ) {
      continue;
    }

    if (existing[field] !== data[field]) {
      changes[field] = {
        before: existing[field],
        after: data[field],
      };
    }
  }

  return changes;
}

// --------------------------------------------------
// Comments: list
// --------------------------------------------------

async function listComments(taskId, actor) {
  const access = await getTaskAccess(taskId, actor);

  return prisma.taskComment.findMany({
    where: {
      taskId: access.task.id,
    },
    include: commentInclude,
    orderBy: [
      { createdAt: "asc" },
      { id: "asc" },
    ],
  });
}

// --------------------------------------------------
// Comments: create
// --------------------------------------------------

async function createComment(taskId, body, actor) {
  const access = await getTaskAccess(taskId, actor);
  requireCollaboration(access);

  const data = validateComment(body);

  return prisma.$transaction(async (tx) => {
    const comment = await tx.taskComment.create({
      data: {
        taskId: access.task.id,
        userId: actor.id,
        content: data.content,
      },
      include: commentInclude,
    });

    await logTaskActivity(
      tx,
      actor,
      access.task.id,
      "TASK_COMMENT_CREATED",
      {
        commentId: comment.id,
        authorId: comment.userId,
      }
    );

    return comment;
  });
}

// --------------------------------------------------
// Comments: update
// --------------------------------------------------

async function updateComment(
  taskId,
  commentId,
  body,
  actor
) {
  const access = await getTaskAccess(taskId, actor);
  requireCollaboration(access);

  const id = positiveId(commentId, "Comment ID");
  const data = validateComment(body);

  return prisma.$transaction(async (tx) => {
    const comment = await tx.taskComment.findFirst({
      where: {
        id,
        taskId: access.task.id,
      },
    });

    if (!comment) {
      throw httpError(404, "Comment not found");
    }

    if (
      actor.role !== "ADMIN" &&
      comment.userId !== actor.id
    ) {
      throw httpError(
        403,
        "You can only edit your own comments"
      );
    }

    // Do not write or log an unchanged comment.
    if (comment.content === data.content) {
      return tx.taskComment.findUnique({
        where: { id },
        include: commentInclude,
      });
    }

    const result = await tx.taskComment.updateMany({
      where: {
        id,
        taskId: access.task.id,
        content: comment.content,
      },
      data: {
        content: data.content,
      },
    });

    if (result.count !== 1) {
      throw httpError(
        409,
        "Comment changed. Refresh and try again."
      );
    }

    const updated = await tx.taskComment.findUnique({
      where: { id },
      include: commentInclude,
    });

    await logTaskActivity(
      tx,
      actor,
      access.task.id,
      "TASK_COMMENT_UPDATED",
      {
        commentId: id,
        authorId: comment.userId,
        contentChanged: true,
      }
    );

    return updated;
  });
}

// --------------------------------------------------
// Comments: delete
// --------------------------------------------------

async function deleteComment(taskId, commentId, actor) {
  const access = await getTaskAccess(taskId, actor);
  requireCollaboration(access);

  const id = positiveId(commentId, "Comment ID");

  return prisma.$transaction(async (tx) => {
    const comment = await tx.taskComment.findFirst({
      where: {
        id,
        taskId: access.task.id,
      },
    });

    if (!comment) {
      throw httpError(404, "Comment not found");
    }

    if (
      actor.role !== "ADMIN" &&
      comment.userId !== actor.id
    ) {
      throw httpError(
        403,
        "You can only delete your own comments"
      );
    }

    const result = await tx.taskComment.deleteMany({
      where: {
        id,
        taskId: access.task.id,
      },
    });

    if (result.count !== 1) {
      throw httpError(
        404,
        "Comment not found"
      );
    }

    await logTaskActivity(
      tx,
      actor,
      access.task.id,
      "TASK_COMMENT_DELETED",
      {
        commentId: id,
        authorId: comment.userId,
      }
    );

    return { id };
  });
}

// --------------------------------------------------
// Checklist: list
// --------------------------------------------------

async function listChecklist(taskId, actor) {
  const access = await getTaskAccess(taskId, actor);

  return prisma.taskChecklist.findMany({
    where: {
      taskId: access.task.id,
    },
    include: checklistInclude,
    orderBy: [
      { position: "asc" },
      { id: "asc" },
    ],
  });
}

// --------------------------------------------------
// Checklist: create
// --------------------------------------------------

async function createChecklist(taskId, body, actor) {
  const access = await getTaskAccess(taskId, actor);
  requireChecklistManagement(access);

  const data = validateChecklist(body);

  return prisma.$transaction(async (tx) => {
    const item = await tx.taskChecklist.create({
      data: {
        taskId: access.task.id,
        createdById: actor.id,
        title: data.title,
        position: data.position ?? 0,
        isCompleted: data.isCompleted ?? false,
      },
      include: checklistInclude,
    });

    await logTaskActivity(
      tx,
      actor,
      access.task.id,
      "TASK_CHECKLIST_CREATED",
      {
        checklistId: item.id,
        title: item.title,
        position: item.position,
        isCompleted: item.isCompleted,
        createdById: actor.id,
      }
    );

    return item;
  });
}

// --------------------------------------------------
// Checklist: update
// --------------------------------------------------

async function updateChecklist(
  taskId,
  checklistId,
  body,
  actor
) {
  const access = await getTaskAccess(taskId, actor);

  const id = positiveId(
    checklistId,
    "Checklist item ID"
  );

  const data = validateChecklist(body, true);

  // Preserve the original permission distinction:
  // assigned employees may update completion only.
  const fields = Object.keys(data);

  const completionOnly =
    fields.length === 1 &&
    fields[0] === "isCompleted";

  if (completionOnly) {
    requireCollaboration(access);
  } else {
    requireChecklistManagement(access);
  }

  return prisma.$transaction(async (tx) => {
    const existing = await tx.taskChecklist.findFirst({
      where: {
        id,
        taskId: access.task.id,
      },
    });

    if (!existing) {
      throw httpError(
        404,
        "Checklist item not found"
      );
    }

    const changes = getChecklistChanges(
      existing,
      data
    );

    if (Object.keys(changes).length === 0) {
      return tx.taskChecklist.findUnique({
        where: { id },
        include: checklistInclude,
      });
    }

    const result = await tx.taskChecklist.updateMany({
      where: {
        id,
        taskId: access.task.id,
        title: existing.title,
        position: existing.position,
        isCompleted: existing.isCompleted,
      },
      data,
    });

    if (result.count !== 1) {
      throw httpError(
        409,
        "Checklist item changed. Refresh and try again."
      );
    }

    const updated = await tx.taskChecklist.findUnique({
      where: { id },
      include: checklistInclude,
    });

    await logTaskActivity(
      tx,
      actor,
      access.task.id,
      "TASK_CHECKLIST_UPDATED",
      {
        checklistId: id,
        changes,
      }
    );

    return updated;
  });
}

// --------------------------------------------------
// Checklist: delete
// --------------------------------------------------

async function deleteChecklist(
  taskId,
  checklistId,
  actor
) {
  const access = await getTaskAccess(taskId, actor);
  requireChecklistManagement(access);

  const id = positiveId(
    checklistId,
    "Checklist item ID"
  );

  return prisma.$transaction(async (tx) => {
    const existing = await tx.taskChecklist.findFirst({
      where: {
        id,
        taskId: access.task.id,
      },
    });

    if (!existing) {
      throw httpError(
        404,
        "Checklist item not found"
      );
    }

    const result = await tx.taskChecklist.deleteMany({
      where: {
        id,
        taskId: access.task.id,
      },
    });

    if (result.count !== 1) {
      throw httpError(
        404,
        "Checklist item not found"
      );
    }

    await logTaskActivity(
      tx,
      actor,
      access.task.id,
      "TASK_CHECKLIST_DELETED",
      {
        checklistId: id,
        title: existing.title,
        wasCompleted: existing.isCompleted,
        createdById: existing.createdById,
      }
    );

    return { id };
  });
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