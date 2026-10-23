const prisma = require("../config/db");

const {
  TASK_STATUSES,
  positiveId,
  validateTask,
  validateProgress,
} = require("../validator/taskValidator");

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

const taskInclude = {
  project: {
    select: {
      id: true,
      code: true,
      name: true,
      status: true,
      leadManagerId: true,
      ownerDepartmentId: true,
    },
  },
  department: {
    select: {
      id: true,
      name: true,
      code: true,
    },
  },
  createdBy: {
    select: {
      id: true,
      firstName: true,
      lastName: true,
    },
  },
  assignments: {
    include: {
      user: {
        select: {
          id: true,
          firstName: true,
          lastName: true,
          email: true,
          role: true,
        },
      },
    },
  },
  _count: {
    select: {
      comments: true,
      attachments: true,
      checklist: true,
      reviews: true,
    },
  },
};

function managerCanManage(project, actor) {
  return (
    actor.role === "MANAGER" &&
    project.leadManagerId === actor.id &&
    project.ownerDepartmentId === actor.departmentId
  );
}

function taskVisibility(actor) {
  if (actor.role === "ADMIN") return {};

  if (actor.role === "EMPLOYEE") {
    return {
      assignments: {
        some: { userId: actor.id },
      },
    };
  }

  if (actor.role === "MANAGER" && actor.departmentId) {
    return {
      OR: [
        {
          project: {
            ownerDepartmentId: actor.departmentId,
          },
        },
        {
          project: {
            departments: {
              some: {
                departmentId: actor.departmentId,
              },
            },
          },
        },
      ],
    };
  }

  return { id: -1 };
}

async function getVisibleTask(id, actor) {
  const task = await prisma.task.findFirst({
    where: {
      AND: [
        { id: positiveId(id, "Task ID") },
        taskVisibility(actor),
      ],
    },
    include: taskInclude,
  });

  if (!task) {
    throw httpError(404, "Task not found");
  }

  return task;
}

async function getProject(projectId, actor) {
  const project = await prisma.project.findUnique({
    where: { id: projectId },
    include: {
      departments: {
        select: { departmentId: true },
      },
    },
  });

  if (!project) {
    throw httpError(404, "Project not found");
  }

  if (
    actor.role !== "ADMIN" &&
    !managerCanManage(project, actor)
  ) {
    throw httpError(
      403,
      "You cannot manage tasks in this project"
    );
  }

  return project;
}

async function validateDepartment(project, departmentId) {
  const allowedIds = new Set([
    project.ownerDepartmentId,
    ...project.departments.map(
      (item) => item.departmentId
    ),
  ]);

  if (!allowedIds.has(departmentId)) {
    throw httpError(
      400,
      "Task department must participate in the project"
    );
  }

  const department = await prisma.department.findUnique({
    where: { id: departmentId },
    select: { isActive: true },
  });

  if (!department || !department.isActive) {
    throw httpError(
      400,
      "Task department is inactive or invalid"
    );
  }
}

async function validateAssignees(assigneeIds, departmentId) {
  if (assigneeIds.length === 0) return;

  const users = await prisma.user.findMany({
    where: {
      id: { in: assigneeIds },
      departmentId,
      status: "ACTIVE",
      emailVerifiedAt: { not: null },
    },
    select: { id: true },
  });

  if (users.length !== assigneeIds.length) {
    throw httpError(
      400,
      "Assignees must be active, verified users in the task department"
    );
  }
}

function validateTaskDates(data, existing = null) {
  const startDate =
    data.startDate !== undefined
      ? data.startDate
      : existing?.startDate;

  const dueDate =
    data.dueDate !== undefined
      ? data.dueDate
      : existing?.dueDate;

  if (startDate && dueDate && dueDate < startDate) {
    throw httpError(
      400,
      "dueDate cannot be earlier than startDate"
    );
  }
}

function taskUrl(taskId) {
  return `/tasks/${taskId}`;
}

function uniqueIds(ids) {
  return [...new Set(ids)];
}

function assignmentNotifications(task, userIds) {
  return uniqueIds(userIds).map((userId) => ({
    userId,
    type: "TASK_ASSIGNED",
    title: "New task assigned",
    message: `You have been assigned to task: ${task.title}`,
    targetUrl: taskUrl(task.id),
  }));
}

function updateNotifications(task, userIds, message) {
  return uniqueIds(userIds).map((userId) => ({
    userId,
    type: "TASK_UPDATED",
    title: "Task updated",
    message,
    targetUrl: taskUrl(task.id),
  }));
}

// Fields allowed in the task audit history.
const AUDIT_TASK_FIELDS = new Set([
  "projectId",
  "departmentId",
  "title",
  "description",
  "status",
  "priority",
  "startDate",
  "dueDate",
  "progress",
  "completedAt",
  "campaignId",
]);

function auditValue(value) {
  return value instanceof Date
    ? value.toISOString()
    : (value ?? null);
}

function taskFieldChanges(previous, updates) {
  const changes = {};

  for (const [key, next] of Object.entries(updates)) {
    if (!AUDIT_TASK_FIELDS.has(key)) continue;

    const before = auditValue(previous[key]);
    const after = auditValue(next);

    if (before !== after) {
      changes[key] = { before, after };
    }
  }

  return changes;
}

// --------------------------------------------------
// Create task
// --------------------------------------------------

async function create(body, actor) {
  const data = validateTask(body);

  const project = await getProject(data.projectId, actor);

  if (["COMPLETED", "CANCELLED"].includes(project.status)) {
    throw httpError(
      400,
      "Cannot create tasks in a completed or cancelled project"
    );
  }

  await validateDepartment(project, data.departmentId);

  const assigneeIds = data.assigneeIds || [];

  await validateAssignees(assigneeIds, data.departmentId);

  const {
    assigneeIds: ignored,
    ...taskData
  } = data;

  return prisma.$transaction(async (tx) => {
    const task = await tx.task.create({
      data: {
        ...taskData,
        createdById: actor.id,
        assignments: {
          create: assigneeIds.map((userId) => ({
            userId,
            assignedById: actor.id,
          })),
        },
      },
      include: taskInclude,
    });

    await createNotifications(
      assignmentNotifications(task, assigneeIds),
      tx
    );

    await recordActivity({
      db: tx,
      userId: actor.id,
      action: "TASK_CREATED",
      entityType: "TASK",
      entityId: task.id,
      details: {
        projectId: task.projectId,
        departmentId: task.departmentId,
        title: task.title,
        assigneeIds: uniqueIds(assigneeIds),
      },
    });

    return task;
  });
}

// --------------------------------------------------
// List tasks
// --------------------------------------------------

async function list(query, actor) {
  const page = Number(query.page ?? 1);
  const limit = Number(query.limit ?? 20);

  if (
    !Number.isSafeInteger(page) ||
    page < 1 ||
    !Number.isSafeInteger(limit) ||
    limit < 1 ||
    limit > 100
  ) {
    throw httpError(
      400,
      "page must be positive and limit must be between 1 and 100"
    );
  }

  const filters = [taskVisibility(actor)];

  if (query.projectId !== undefined) {
    filters.push({
      projectId: positiveId(query.projectId, "projectId"),
    });
  }

  if (query.departmentId !== undefined) {
    filters.push({
      departmentId: positiveId(
        query.departmentId,
        "departmentId"
      ),
    });
  }

  if (query.status !== undefined) {
    if (!TASK_STATUSES.includes(query.status)) {
      throw httpError(400, "Invalid task status");
    }

    filters.push({ status: query.status });
  }

  if (query.assigneeId !== undefined) {
    filters.push({
      assignments: {
        some: {
          userId: positiveId(
            query.assigneeId,
            "assigneeId"
          ),
        },
      },
    });
  }

  if (query.search !== undefined) {
    if (typeof query.search !== "string") {
      throw httpError(400, "Invalid search");
    }

    filters.push({
      title: {
        contains: query.search.trim(),
      },
    });
  }

  const where = { AND: filters };

  const [tasks, total] = await prisma.$transaction([
    prisma.task.findMany({
      where,
      include: taskInclude,
      orderBy: { createdAt: "desc" },
      skip: (page - 1) * limit,
      take: limit,
    }),
    prisma.task.count({ where }),
  ]);

  return {
    tasks,
    pagination: {
      page,
      limit,
      total,
      totalPages: Math.ceil(total / limit),
    },
  };
}

async function getById(id, actor) {
  return getVisibleTask(id, actor);
}

// --------------------------------------------------
// Update task and assignments
// --------------------------------------------------

async function update(id, body, actor) {
  const existing = await getVisibleTask(id, actor);

  if (
    actor.role !== "ADMIN" &&
    !managerCanManage(existing.project, actor)
  ) {
    throw httpError(403, "Permission denied");
  }

  const data = validateTask(body, true);

  const projectId =
    data.projectId ?? existing.projectId;

  const departmentId =
    data.departmentId ?? existing.departmentId;

  const project = await getProject(projectId, actor);

  if (["COMPLETED", "CANCELLED"].includes(project.status)) {
    throw httpError(
      400,
      "Cannot modify tasks in a completed or cancelled project"
    );
  }

  await validateDepartment(project, departmentId);
  validateTaskDates(data, existing);

  const assigneeIds = data.assigneeIds;

  if (assigneeIds !== undefined) {
    await validateAssignees(
      assigneeIds,
      departmentId
    );
  } else if (
    data.departmentId !== undefined &&
    data.departmentId !== existing.departmentId
  ) {
    const currentIds = existing.assignments.map(
      (assignment) => assignment.userId
    );

    await validateAssignees(
      currentIds,
      departmentId
    );
  }

  const {
    assigneeIds: ignored,
    ...taskData
  } = data;

  return prisma.$transaction(async (tx) => {
    const current = await tx.task.findUnique({
      where: { id: existing.id },
      include: {
        assignments: {
          select: { userId: true },
        },
      },
    });

    if (!current) {
      throw httpError(404, "Task not found");
    }

    const previousIds = current.assignments.map(
      (item) => item.userId
    );

    const nextIds =
      assigneeIds !== undefined
        ? assigneeIds
        : previousIds;

    const previousSet = new Set(previousIds);
    const nextSet = new Set(nextIds);

    const addedIds = nextIds.filter(
      (userId) => !previousSet.has(userId)
    );

    const retainedIds = previousIds.filter(
      (userId) => nextSet.has(userId)
    );

    const removedIds = previousIds.filter(
      (userId) => !nextSet.has(userId)
    );

    // Preserve assignment rows for retained employees.
    if (removedIds.length > 0) {
      await tx.taskAssignment.deleteMany({
        where: {
          taskId: existing.id,
          userId: { in: removedIds },
        },
      });
    }

    if (addedIds.length > 0) {
      await tx.taskAssignment.createMany({
        data: addedIds.map((userId) => ({
          taskId: existing.id,
          userId,
          assignedById: actor.id,
        })),
      });
    }

    const changes = taskFieldChanges(
      current,
      taskData
    );

    const assignmentChanged =
      addedIds.length > 0 ||
      removedIds.length > 0;

    if (
      !assignmentChanged &&
      Object.keys(changes).length === 0
    ) {
      return tx.task.findUnique({
        where: { id: existing.id },
        include: taskInclude,
      });
    }

    const task = await tx.task.update({
      where: { id: existing.id },
      data: taskData,
      include: taskInclude,
    });

    const notifications = [
      ...assignmentNotifications(task, addedIds),
    ];

    if (Object.keys(changes).length > 0) {
      notifications.push(
        ...updateNotifications(
          task,
          retainedIds,
          `Task details were updated: ${task.title}`
        )
      );
    }

    await createNotifications(notifications, tx);

    if (Object.keys(changes).length > 0) {
      await recordActivity({
        db: tx,
        userId: actor.id,
        action: "TASK_UPDATED",
        entityType: "TASK",
        entityId: task.id,
        details: { changes },
      });
    }

    if (assignmentChanged) {
      await recordActivity({
        db: tx,
        userId: actor.id,
        action: "TASK_ASSIGNED",
        entityType: "TASK",
        entityId: task.id,
        details: {
          addedUserIds: uniqueIds(addedIds),
          removedUserIds: uniqueIds(removedIds),
        },
      });
    }

    return task;
  });
}

async function assign(id, body, actor) {
  if (
    !body ||
    !Array.isArray(body.assigneeIds) ||
    Object.keys(body).some(
      (key) => key !== "assigneeIds"
    )
  ) {
    throw httpError(
      400,
      "assigneeIds array is required"
    );
  }

  return update(
    id,
    { assigneeIds: body.assigneeIds },
    actor
  );
}

// --------------------------------------------------
// Update progress
// --------------------------------------------------

async function updateProgress(id, body, actor) {
  const progress = validateProgress(body);
  const task = await getVisibleTask(id, actor);

  const canManage =
    actor.role === "ADMIN" ||
    managerCanManage(task.project, actor);

  const isAssigned = task.assignments.some(
    (assignment) => assignment.userId === actor.id
  );

  if (!canManage && !isAssigned) {
    throw httpError(403, "Permission denied");
  }

  if (
    ["IN_REVIEW", "COMPLETED", "CANCELLED"].includes(
      task.status
    )
  ) {
    throw httpError(
      400,
      "Progress cannot be changed in the current task status"
    );
  }

  if (
    ["COMPLETED", "CANCELLED"].includes(
      task.project.status
    )
  ) {
    throw httpError(400, "Project is closed");
  }

  return prisma.$transaction(async (tx) => {
    const nextStatus =
      task.status === "PENDING" && progress > 0
        ? "IN_PROGRESS"
        : task.status;

    const result = await tx.task.updateMany({
      where: {
        id: task.id,
        status: task.status,
        progress: task.progress,
      },
      data: {
        progress,
        status: nextStatus,
      },
    });

    if (result.count !== 1) {
      throw httpError(
        409,
        "Task changed. Refresh and try again."
      );
    }

    const updatedTask = await tx.task.findUnique({
      where: { id: task.id },
      include: taskInclude,
    });

    if (
      task.progress !== progress ||
      task.status !== nextStatus
    ) {
      const recipientIds = updatedTask.assignments
        .map((item) => item.userId)
        .filter((userId) => userId !== actor.id);

      await createNotifications(
        updateNotifications(
          updatedTask,
          recipientIds,
          `Task progress updated to ${progress}%: ${task.title}`
        ),
        tx
      );

      await recordActivity({
        db: tx,
        userId: actor.id,
        action: "TASK_PROGRESS_UPDATED",
        entityType: "TASK",
        entityId: task.id,
        details: {
          progress: {
            before: task.progress,
            after: progress,
          },
          status: {
            before: task.status,
            after: nextStatus,
          },
        },
      });
    }

    return updatedTask;
  });
}

// --------------------------------------------------
// Submit task for review
// --------------------------------------------------

async function submitForReview(id, actor) {
  const task = await getVisibleTask(id, actor);

  const canManage =
    actor.role === "ADMIN" ||
    managerCanManage(task.project, actor);

  const isAssigned = task.assignments.some(
    (assignment) => assignment.userId === actor.id
  );

  if (!canManage && !isAssigned) {
    throw httpError(403, "Permission denied");
  }

  if (!["PENDING", "IN_PROGRESS"].includes(task.status)) {
    throw httpError(
      400,
      "Only pending or in-progress tasks can be submitted"
    );
  }

  if (
    ["COMPLETED", "CANCELLED"].includes(
      task.project.status
    )
  ) {
    throw httpError(400, "Project is closed");
  }

  return prisma.$transaction(async (tx) => {
    const result = await tx.task.updateMany({
      where: {
        id: task.id,
        status: task.status,
      },
      data: {
        status: "IN_REVIEW",
      },
    });

    if (result.count !== 1) {
      throw httpError(
        409,
        "Task status changed. Refresh and try again."
      );
    }

    const updatedTask = await tx.task.findUnique({
      where: { id: task.id },
      include: taskInclude,
    });

    const projectLeadId =
      updatedTask.project.leadManagerId;

    if (
      projectLeadId &&
      projectLeadId !== actor.id
    ) {
      await createNotifications(
        [
          {
            userId: projectLeadId,
            type: "TASK_UPDATED",
            title: "Task submitted for review",
            message:
              `Task "${updatedTask.title}" is ready for review.`,
            targetUrl: taskUrl(updatedTask.id),
          },
        ],
        tx
      );
    }

    await recordActivity({
      db: tx,
      userId: actor.id,
      action: "TASK_SUBMITTED_FOR_REVIEW",
      entityType: "TASK",
      entityId: task.id,
      details: {
        status: {
          before: task.status,
          after: "IN_REVIEW",
        },
      },
    });

    return updatedTask;
  });
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