const prisma = require("../config/db");

const {
  validateProject,
  positiveId,
  PROJECT_STATUSES,
} = require("../validator/projectValidator");

const {
  recordActivity,
} = require("./activityLogService");

function httpError(statusCode, message) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

const includeProject = {
  ownerDepartment: {
    select: { id: true, name: true, code: true },
  },
  leadManager: {
    select: {
      id: true,
      firstName: true,
      lastName: true,
      email: true,
      role: true,
    },
  },
  createdBy: {
    select: {
      id: true,
      firstName: true,
      lastName: true,
    },
  },
  departments: {
    include: {
      department: {
        select: { id: true, name: true, code: true },
      },
    },
  },
  _count: {
    select: { tasks: true },
  },
};

function visibilityFilter(actor) {
  if (actor.role === "ADMIN") return {};

  if (!actor.departmentId) {
    return { id: -1 };
  }

  return {
    OR: [
      { ownerDepartmentId: actor.departmentId },
      {
        departments: {
          some: { departmentId: actor.departmentId },
        },
      },
    ],
  };
}

async function getVisibleProject(id, actor) {
  const project = await prisma.project.findFirst({
    where: {
      AND: [
        { id: positiveId(id, "Project ID") },
        visibilityFilter(actor),
      ],
    },
    include: includeProject,
  });

  if (!project) {
    throw httpError(404, "Project not found");
  }

  return project;
}

async function validateRelations(data, actor) {
  const department = await prisma.department.findUnique({
    where: { id: data.ownerDepartmentId },
  });

  if (!department || !department.isActive) {
    throw httpError(
      400,
      "Owner department is invalid or inactive"
    );
  }

  const lead = await prisma.user.findUnique({
    where: { id: data.leadManagerId },
  });

  if (
    !lead ||
    lead.status !== "ACTIVE" ||
    !lead.emailVerifiedAt ||
    !["ADMIN", "MANAGER"].includes(lead.role)
  ) {
    throw httpError(
      400,
      "Project lead must be an active, verified manager or admin"
    );
  }

  if (
    lead.role === "MANAGER" &&
    lead.departmentId !== data.ownerDepartmentId
  ) {
    throw httpError(
      400,
      "Project lead must belong to the owner department"
    );
  }

  if (actor.role === "MANAGER") {
    if (
      actor.departmentId !== data.ownerDepartmentId ||
      actor.id !== data.leadManagerId
    ) {
      throw httpError(
        403,
        "Managers can only create projects for their own department and lead them personally"
      );
    }
  }

  const ids = [
    ...new Set([
      data.ownerDepartmentId,
      ...(data.departmentIds || []),
    ]),
  ];

  const departments = await prisma.department.findMany({
    where: {
      id: { in: ids },
      isActive: true,
    },
    select: { id: true },
  });

  if (departments.length !== ids.length) {
    throw httpError(
      400,
      "One or more participating departments are invalid"
    );
  }

  return ids;
}

function changedFields(existing, data) {
  const changes = {};

  for (const [field, newValue] of Object.entries(data)) {
    if (field === "completedAt") continue;

    const oldValue = existing[field];

    const before =
      oldValue instanceof Date
        ? oldValue.toISOString()
        : oldValue;

    const after =
      newValue instanceof Date
        ? newValue.toISOString()
        : newValue;

    if (before !== after) {
      changes[field] = {
        before: before ?? null,
        after: after ?? null,
      };
    }
  }

  return changes;
}

function departmentChanges(existing, departmentIds) {
  if (departmentIds === undefined) return null;

  const before = existing.departments
    .map((item) => item.departmentId)
    .sort((a, b) => a - b);

  const after = [...new Set(departmentIds)]
    .sort((a, b) => a - b);

  if (JSON.stringify(before) === JSON.stringify(after)) {
    return null;
  }

  return { before, after };
}

async function logProjectActivity(
  tx,
  actor,
  projectId,
  action,
  details
) {
  await recordActivity({
    db: tx,
    userId: actor.id,
    action,
    entityType: "PROJECT",
    entityId: projectId,
    details,
  });
}

// --------------------------------------------------
// Create project
// --------------------------------------------------

async function create(body, actor) {
  const data = validateProject(body);

  if (
    actor.role === "MANAGER" &&
    body.departmentIds !== undefined
  ) {
    if (
      data.departmentIds.some(
        (id) => id !== actor.departmentId
      )
    ) {
      throw httpError(
        403,
        "Managers cannot add other departments"
      );
    }
  }

  const departmentIds = await validateRelations(
    data,
    actor
  );

  const existing = await prisma.project.findUnique({
    where: { code: data.code },
    select: { id: true },
  });

  if (existing) {
    throw httpError(409, "Project code already exists");
  }

  const {
    departmentIds: ignored,
    ...projectData
  } = data;

  if (projectData.status === "COMPLETED") {
    projectData.completedAt = new Date();
  }

  return prisma.$transaction(async (tx) => {
    const project = await tx.project.create({
      data: {
        ...projectData,
        createdById: actor.id,
        departments: {
          create: departmentIds.map(
            (departmentId) => ({ departmentId })
          ),
        },
      },
      include: includeProject,
    });

    await logProjectActivity(
      tx,
      actor,
      project.id,
      "PROJECT_CREATED",
      {
        code: project.code,
        name: project.name,
        status: project.status,
        ownerDepartmentId: project.ownerDepartmentId,
        leadManagerId: project.leadManagerId,
        departmentIds,
      }
    );

    return project;
  });
}

// --------------------------------------------------
// List projects
// --------------------------------------------------

async function list(query, actor) {
  const page = Math.max(
    1,
    Number.parseInt(query.page, 10) || 1
  );

  const limit = Math.min(
    100,
    Math.max(
      1,
      Number.parseInt(query.limit, 10) || 20
    )
  );

  if (!Number.isSafeInteger(page)) {
    throw httpError(400, "Invalid page");
  }

  const filters = [visibilityFilter(actor)];

  if (query.status) {
    if (!PROJECT_STATUSES.includes(query.status)) {
      throw httpError(400, "Invalid project status");
    }

    filters.push({ status: query.status });
  }

  if (query.search) {
    const search = String(query.search).trim();

    filters.push({
      OR: [
        { name: { contains: search } },
        { code: { contains: search } },
      ],
    });
  }

  const where = { AND: filters };

  const [projects, total] = await prisma.$transaction([
    prisma.project.findMany({
      where,
      include: includeProject,
      orderBy: { createdAt: "desc" },
      skip: (page - 1) * limit,
      take: limit,
    }),
    prisma.project.count({ where }),
  ]);

  return {
    projects,
    pagination: {
      page,
      limit,
      total,
      totalPages: Math.ceil(total / limit),
    },
  };
}

// --------------------------------------------------
// Get project
// --------------------------------------------------

async function getById(id, actor) {
  return getVisibleProject(id, actor);
}

// --------------------------------------------------
// Update project and audit every change type
// --------------------------------------------------

async function update(id, body, actor) {
  const existing = await getVisibleProject(id, actor);

  if (
    actor.role !== "ADMIN" &&
    (
      actor.role !== "MANAGER" ||
      existing.leadManagerId !== actor.id ||
      existing.ownerDepartmentId !== actor.departmentId
    )
  ) {
    throw httpError(403, "Permission denied");
  }

  const data = validateProject(body, true);

  if (actor.role === "MANAGER") {
    const restricted = [
      "ownerDepartmentId",
      "leadManagerId",
      "departmentIds",
    ];

    if (
      restricted.some(
        (field) => data[field] !== undefined
      )
    ) {
      throw httpError(
        403,
        "Only admins can change project ownership or participating departments"
      );
    }
  }

  const ownerDepartmentId =
    data.ownerDepartmentId ??
    existing.ownerDepartmentId;

  const leadManagerId =
    data.leadManagerId ??
    existing.leadManagerId;

  let departmentIds;

  if (
    data.ownerDepartmentId !== undefined ||
    data.leadManagerId !== undefined ||
    data.departmentIds !== undefined
  ) {
    departmentIds = await validateRelations(
      {
        ownerDepartmentId,
        leadManagerId,
        departmentIds:
          data.departmentIds ??
          existing.departments.map(
            (item) => item.departmentId
          ),
      },
      actor
    );
  }

  const startDate =
    data.startDate !== undefined
      ? data.startDate
      : existing.startDate;

  const dueDate =
    data.dueDate !== undefined
      ? data.dueDate
      : existing.dueDate;

  if (
    startDate &&
    dueDate &&
    dueDate < startDate
  ) {
    throw httpError(
      400,
      "dueDate cannot be earlier than startDate"
    );
  }

  if (
    data.code &&
    data.code !== existing.code
  ) {
    const duplicate = await prisma.project.findUnique({
      where: { code: data.code },
      select: { id: true },
    });

    if (duplicate) {
      throw httpError(
        409,
        "Project code already exists"
      );
    }
  }

  if (
    data.status === "COMPLETED" &&
    existing.status !== "COMPLETED"
  ) {
    data.completedAt = new Date();
  } else if (
    data.status !== undefined &&
    data.status !== "COMPLETED"
  ) {
    data.completedAt = null;
  }

  const {
    departmentIds: ignored,
    ...projectData
  } = data;

  return prisma.$transaction(async (tx) => {
    const current = await tx.project.findUnique({
      where: { id: existing.id },
      include: {
        departments: {
          select: { departmentId: true },
        },
      },
    });

    if (!current) {
      throw httpError(404, "Project not found");
    }

    if (
      current.updatedAt.getTime() !==
      existing.updatedAt.getTime()
    ) {
      throw httpError(
        409,
        "Project changed. Refresh and try again."
      );
    }

    const changes = changedFields(
      current,
      projectData
    );

    const departmentChange = departmentChanges(
      current,
      departmentIds
    );

    if (departmentChange) {
      changes.departmentIds = departmentChange;
    }

    if (Object.keys(changes).length === 0) {
      return tx.project.findUnique({
        where: { id: existing.id },
        include: includeProject,
      });
    }

    const result = await tx.project.updateMany({
      where: {
        id: existing.id,
        updatedAt: current.updatedAt,
      },
      data: projectData,
    });

    if (result.count !== 1) {
      throw httpError(
        409,
        "Project changed. Refresh and try again."
      );
    }

    if (departmentChange) {
      await tx.projectDepartment.deleteMany({
        where: { projectId: existing.id },
      });

      await tx.projectDepartment.createMany({
        data: departmentIds.map(
          (departmentId) => ({
            projectId: existing.id,
            departmentId,
          })
        ),
      });
    }

    const project = await tx.project.findUnique({
      where: { id: existing.id },
      include: includeProject,
    });

    // Separate changes by audit event category.
    const generalChanges = { ...changes };

    delete generalChanges.status;
    delete generalChanges.leadManagerId;
    delete generalChanges.departmentIds;

    if (Object.keys(generalChanges).length > 0) {
      await logProjectActivity(
        tx,
        actor,
        project.id,
        "PROJECT_UPDATED",
        {
          code: project.code,
          changes: generalChanges,
        }
      );
    }

    if (changes.status) {
      await logProjectActivity(
        tx,
        actor,
        project.id,
        "PROJECT_STATUS_CHANGED",
        {
          code: project.code,
          changes: {
            status: changes.status,
          },
        }
      );
    }

    if (changes.leadManagerId) {
      await logProjectActivity(
        tx,
        actor,
        project.id,
        "PROJECT_MANAGER_CHANGED",
        {
          code: project.code,
          changes: {
            leadManagerId: changes.leadManagerId,
          },
        }
      );
    }

    if (departmentChange) {
      const before = new Set(
        departmentChange.before
      );

      const after = new Set(
        departmentChange.after
      );

      for (const departmentId of departmentChange.after) {
        if (!before.has(departmentId)) {
          await logProjectActivity(
            tx,
            actor,
            project.id,
            "PROJECT_DEPARTMENT_ADDED",
            {
              code: project.code,
              departmentId,
            }
          );
        }
      }

      for (const departmentId of departmentChange.before) {
        if (!after.has(departmentId)) {
          await logProjectActivity(
            tx,
            actor,
            project.id,
            "PROJECT_DEPARTMENT_REMOVED",
            {
              code: project.code,
              departmentId,
            }
          );
        }
      }
    }

    return project;
  });
}

// --------------------------------------------------
// Change status
// --------------------------------------------------

async function changeStatus(id, status, actor) {
  if (!PROJECT_STATUSES.includes(status)) {
    throw httpError(
      400,
      "Invalid project status"
    );
  }

  return update(id, { status }, actor);
}

module.exports = {
  create,
  list,
  getById,
  update,
  changeStatus,
};