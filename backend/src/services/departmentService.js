const { Prisma } = require("@prisma/client");
const prisma = require("../config/db");

const {
  recordActivity,
} = require("./activityLogService");

function httpError(message, statusCode) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

const departmentInclude = {
  manager: {
    select: {
      id: true,
      employeeCode: true,
      firstName: true,
      lastName: true,
      email: true,
      role: true,
      status: true,
      departmentId: true,
    },
  },
  _count: {
    select: {
      users: true,
      tasks: true,
      ownedProjects: true,
    },
  },
};

function handlePrismaError(error) {
  if (error instanceof Prisma.PrismaClientKnownRequestError) {
    if (error.code === "P2002") {
      throw httpError(
        "Department name, code, or manager assignment already exists",
        409
      );
    }

    if (error.code === "P2003") {
      throw httpError("Invalid related record", 400);
    }

    if (error.code === "P2025") {
      throw httpError(
        "Department or related record not found",
        404
      );
    }
  }

  throw error;
}

// --------------------------------------------------
// Helpers
// --------------------------------------------------

function requireActorId(actorId) {
  if (
    !Number.isSafeInteger(actorId) ||
    actorId <= 0
  ) {
    throw httpError(
      "Authenticated administrator is required",
      401
    );
  }
}

async function ensureDepartment(id, db = prisma) {
  const department = await db.department.findUnique({
    where: { id },
  });

  if (!department) {
    throw httpError("Department not found", 404);
  }

  return department;
}

function departmentChanges(current, updates) {
  const allowedFields = [
    "name",
    "code",
    "description",
    "isActive",
  ];

  const changes = {};

  for (const field of allowedFields) {
    if (
      !Object.prototype.hasOwnProperty.call(
        updates,
        field
      )
    ) {
      continue;
    }

    const before = current[field] ?? null;
    const after = updates[field] ?? null;

    if (before !== after) {
      changes[field] = {
        before,
        after,
      };
    }
  }

  return changes;
}

// --------------------------------------------------
// Create department
// --------------------------------------------------

async function createDepartment(data, actorId) {
  requireActorId(actorId);

  try {
    return await prisma.$transaction(async (tx) => {
      const department = await tx.department.create({
        data,
        include: departmentInclude,
      });

      await recordActivity({
        db: tx,
        userId: actorId,
        action: "DEPARTMENT_CREATED",
        entityType: "DEPARTMENT",
        entityId: department.id,
        details: {
          name: department.name,
          code: department.code,
          description: department.description,
          isActive: department.isActive,
          managerId: department.managerId,
        },
      });

      return department;
    });
  } catch (error) {
    handlePrismaError(error);
  }
}

// --------------------------------------------------
// List departments
// --------------------------------------------------

async function listDepartments(query = {}) {
  const where = {};

  if (query.isActive !== undefined) {
    if (
      query.isActive !== "true" &&
      query.isActive !== "false"
    ) {
      throw httpError(
        "isActive must be true or false",
        400
      );
    }

    where.isActive = query.isActive === "true";
  }

  return prisma.department.findMany({
    where,
    include: departmentInclude,
    orderBy: { name: "asc" },
  });
}

// --------------------------------------------------
// Get department
// --------------------------------------------------

async function getDepartment(id) {
  const department = await prisma.department.findUnique({
    where: { id },
    include: departmentInclude,
  });

  if (!department) {
    throw httpError("Department not found", 404);
  }

  return department;
}

// --------------------------------------------------
// Update department
// --------------------------------------------------

async function updateDepartment(id, data, actorId) {
  requireActorId(actorId);

  try {
    return await prisma.$transaction(async (tx) => {
      const current = await ensureDepartment(id, tx);

      const changes = departmentChanges(
        current,
        data
      );

      if (Object.keys(changes).length === 0) {
        return tx.department.findUnique({
          where: { id },
          include: departmentInclude,
        });
      }

      // Only the fields validated by the existing
      // controller are passed to Prisma.
      const department = await tx.department.update({
        where: { id },
        data,
        include: departmentInclude,
      });

      const detailChanges = {};
      const statusChanges = {};

      for (const [field, change] of Object.entries(changes)) {
        if (field === "isActive") {
          statusChanges[field] = change;
        } else {
          detailChanges[field] = change;
        }
      }

      if (Object.keys(detailChanges).length > 0) {
        await recordActivity({
          db: tx,
          userId: actorId,
          action: "DEPARTMENT_UPDATED",
          entityType: "DEPARTMENT",
          entityId: id,
          details: {
            changes: detailChanges,
          },
        });
      }

      if (Object.keys(statusChanges).length > 0) {
        await recordActivity({
          db: tx,
          userId: actorId,
          action: "DEPARTMENT_STATUS_CHANGED",
          entityType: "DEPARTMENT",
          entityId: id,
          details: {
            changes: statusChanges,
          },
        });
      }

      return department;
    });
  } catch (error) {
    handlePrismaError(error);
  }
}

// --------------------------------------------------
// Assign or remove department manager
// --------------------------------------------------

async function assignManager(
  departmentId,
  managerId,
  actorId
) {
  requireActorId(actorId);

  try {
    return await prisma.$transaction(async (tx) => {
      const department = await ensureDepartment(
        departmentId,
        tx
      );

      if (
        !department.isActive &&
        managerId !== null
      ) {
        throw httpError(
          "Cannot assign a manager to an inactive department",
          409
        );
      }

      if (managerId !== null) {
        const manager = await tx.user.findUnique({
          where: { id: managerId },
          select: {
            id: true,
            role: true,
            status: true,
            departmentId: true,
          },
        });

        if (!manager) {
          throw httpError(
            "Manager user not found",
            404
          );
        }

        if (manager.role !== "MANAGER") {
          throw httpError(
            "Selected user must have the MANAGER role",
            400
          );
        }

        if (manager.status !== "ACTIVE") {
          throw httpError(
            "Selected manager must be active",
            409
          );
        }

        if (manager.departmentId !== departmentId) {
          throw httpError(
            "Manager must belong to the selected department",
            409
          );
        }

        const existingAssignment =
          await tx.department.findFirst({
            where: {
              managerId,
              id: { not: departmentId },
            },
            select: { id: true },
          });

        if (existingAssignment) {
          throw httpError(
            "Manager is already assigned to another department",
            409
          );
        }
      }

      if (department.managerId === managerId) {
        return tx.department.findUnique({
          where: { id: departmentId },
          include: departmentInclude,
        });
      }

      const updated = await tx.department.update({
        where: { id: departmentId },
        data: { managerId },
        include: departmentInclude,
      });

      await recordActivity({
        db: tx,
        userId: actorId,
        action: "DEPARTMENT_MANAGER_CHANGED",
        entityType: "DEPARTMENT",
        entityId: departmentId,
        details: {
          managerId: {
            before: department.managerId,
            after: managerId,
          },
        },
      });

      return updated;
    });
  } catch (error) {
    handlePrismaError(error);
  }
}

// --------------------------------------------------
// Deactivate department
// --------------------------------------------------

async function deactivateDepartment(id, actorId) {
  requireActorId(actorId);

  try {
    return await prisma.$transaction(async (tx) => {
      const current = await ensureDepartment(id, tx);

      if (!current.isActive) {
        return tx.department.findUnique({
          where: { id },
          include: departmentInclude,
        });
      }

      const department = await tx.department.update({
        where: { id },
        data: {
          isActive: false,
        },
        include: departmentInclude,
      });

      await recordActivity({
        db: tx,
        userId: actorId,
        action: "DEPARTMENT_STATUS_CHANGED",
        entityType: "DEPARTMENT",
        entityId: id,
        details: {
          isActive: {
            before: true,
            after: false,
          },
        },
      });

      return department;
    });
  } catch (error) {
    handlePrismaError(error);
  }
}

module.exports = {
  createDepartment,
  listDepartments,
  getDepartment,
  updateDepartment,
  assignManager,
  deactivateDepartment,
};