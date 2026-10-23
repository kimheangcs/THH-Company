const bcrypt = require("bcryptjs");
const { Prisma } = require("@prisma/client");
const prisma = require("../config/db");

const {
  recordActivity,
} = require("./activityLogService");

const userSelect = {
  id: true,
  employeeCode: true,
  firstName: true,
  lastName: true,
  email: true,
  emailVerifiedAt: true,
  phone: true,
  avatarUrl: true,
  jobTitle: true,
  role: true,
  status: true,
  departmentId: true,
  canApproveManagerRequests: true,
  lastLogin: true,
  createdAt: true,
  updatedAt: true,
  department: {
    select: {
      id: true,
      name: true,
      code: true,
      isActive: true,
    },
  },
};

function httpError(message, statusCode) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

function handleDatabaseError(error) {
  if (error instanceof Prisma.PrismaClientKnownRequestError) {
    if (error.code === "P2002") {
      throw httpError(
        "Email or employee code already exists",
        409
      );
    }

    if (error.code === "P2003") {
      throw httpError(
        "Invalid department reference",
        400
      );
    }

    if (error.code === "P2025") {
      throw httpError(
        "User or related record not found",
        404
      );
    }
  }

  throw error;
}

function requireManagerDepartment(actor) {
  if (
    actor.role === "MANAGER" &&
    (
      !Number.isSafeInteger(actor.departmentId) ||
      actor.departmentId <= 0
    )
  ) {
    throw httpError(
      "Manager has no assigned department",
      403
    );
  }
}

function assertCanManage(actor, target) {
  if (actor.role === "ADMIN") return;

  requireManagerDepartment(actor);

  if (
    actor.role !== "MANAGER" ||
    target.role !== "EMPLOYEE" ||
    target.departmentId !== actor.departmentId
  ) {
    throw httpError("Permission denied", 403);
  }
}

async function requireActiveDepartment(
  departmentId,
  db = prisma
) {
  const department = await db.department.findUnique({
    where: { id: departmentId },
    select: {
      id: true,
      isActive: true,
    },
  });

  if (!department || !department.isActive) {
    throw httpError(
      "Department not found or inactive",
      400
    );
  }

  return department;
}

async function getTarget(id) {
  const target = await prisma.user.findUnique({
    where: { id },
    select: {
      id: true,
      role: true,
      departmentId: true,
      email: true,
      status: true,
    },
  });

  if (!target) {
    throw httpError("User not found", 404);
  }

  return target;
}

// --------------------------------------------------
// Audit helpers
// --------------------------------------------------

// Only explicitly approved fields may enter audit details.
// Never audit passwordHash, passwords, OTPs or tokens.
const AUDIT_FIELDS = [
  "employeeCode",
  "firstName",
  "lastName",
  "email",
  "phone",
  "avatarUrl",
  "jobTitle",
  "role",
  "departmentId",
  "canApproveManagerRequests",
];

function auditValue(value) {
  if (value instanceof Date) {
    return value.toISOString();
  }

  return value ?? null;
}

function getUserChanges(current, updates) {
  const changes = {};

  for (const field of AUDIT_FIELDS) {
    if (
      !Object.prototype.hasOwnProperty.call(
        updates,
        field
      )
    ) {
      continue;
    }

    const before = auditValue(current[field]);
    const after = auditValue(updates[field]);

    if (before !== after) {
      changes[field] = {
        before,
        after,
      };
    }
  }

  return changes;
}

function getCreatedUserDetails(user) {
  return {
    employeeCode: user.employeeCode,
    firstName: user.firstName,
    lastName: user.lastName,
    email: user.email,
    role: user.role,
    departmentId: user.departmentId,
    status: user.status,
  };
}

// --------------------------------------------------
// Create user
// --------------------------------------------------

async function createUser(actor, input) {
  if (
    actor.role !== "ADMIN" &&
    actor.role !== "MANAGER"
  ) {
    throw httpError("Permission denied", 403);
  }

  if (actor.role === "MANAGER") {
    requireManagerDepartment(actor);

    if (
      input.role !== "EMPLOYEE" ||
      input.departmentId !== actor.departmentId
    ) {
      throw httpError(
        "Managers can create Employees in their own department only",
        403
      );
    }
  }

  await requireActiveDepartment(input.departmentId);

  const passwordHash = await bcrypt.hash(
    input.password,
    12
  );

  const data = {
    employeeCode: input.employeeCode ?? null,
    firstName: input.firstName,
    lastName: input.lastName,
    email: input.email,
    passwordHash,
    phone: input.phone ?? null,
    jobTitle: input.jobTitle ?? null,
    role: input.role,
    departmentId: input.departmentId,
    status: "ACTIVE",
    emailVerifiedAt: null,
    canApproveManagerRequests: false,
  };

  try {
    return await prisma.$transaction(async (tx) => {
      await requireActiveDepartment(
        input.departmentId,
        tx
      );

      if (actor.role === "MANAGER") {
        const manager = await tx.user.findUnique({
          where: { id: actor.id },
          select: {
            role: true,
            status: true,
            departmentId: true,
            emailVerifiedAt: true,
          },
        });

        if (
          !manager ||
          manager.role !== "MANAGER" ||
          manager.status !== "ACTIVE" ||
          !manager.emailVerifiedAt ||
          manager.departmentId !== input.departmentId
        ) {
          throw httpError(
            "Manager permission changed",
            403
          );
        }
      }

      const user = await tx.user.create({
        data,
        select: userSelect,
      });

      await recordActivity({
        db: tx,
        userId: actor.id,
        action: "USER_CREATED",
        entityType: "USER",
        entityId: user.id,
        details: getCreatedUserDetails(user),
      });

      return user;
    });
  } catch (error) {
    handleDatabaseError(error);
  }
}

// --------------------------------------------------
// List users
// --------------------------------------------------

async function listUsers(actor, filters) {
  requireManagerDepartment(actor);

  const where = {};

  if (actor.role === "MANAGER") {
    where.role = "EMPLOYEE";
    where.departmentId = actor.departmentId;
  } else {
    if (filters.departmentId !== undefined) {
      where.departmentId = filters.departmentId;
    }

    if (filters.role !== undefined) {
      where.role = filters.role;
    }
  }

  if (filters.status !== undefined) {
    where.status = filters.status;
  }

  if (filters.search) {
    where.OR = [
      {
        firstName: {
          contains: filters.search,
        },
      },
      {
        lastName: {
          contains: filters.search,
        },
      },
      {
        email: {
          contains: filters.search,
        },
      },
      {
        employeeCode: {
          contains: filters.search,
        },
      },
    ];
  }

  if (actor.role === "MANAGER") {
    if (
      (
        filters.departmentId !== undefined &&
        filters.departmentId !== actor.departmentId
      ) ||
      (
        filters.role !== undefined &&
        filters.role !== "EMPLOYEE"
      )
    ) {
      throw httpError("Permission denied", 403);
    }
  }

  return prisma.user.findMany({
    where,
    select: userSelect,
    orderBy: [
      { firstName: "asc" },
      { lastName: "asc" },
    ],
  });
}

// --------------------------------------------------
// Get user
// --------------------------------------------------

async function getUser(actor, id) {
  const target = await getTarget(id);

  assertCanManage(actor, target);

  return prisma.user.findUnique({
    where: { id },
    select: userSelect,
  });
}

// --------------------------------------------------
// Update user
// --------------------------------------------------

async function updateUser(actor, id, data) {
  const target = await getTarget(id);

  assertCanManage(actor, target);

  if (
    actor.role === "MANAGER" &&
    Object.prototype.hasOwnProperty.call(
      data,
      "departmentId"
    )
  ) {
    throw httpError(
      "Managers cannot change departments",
      403
    );
  }

  if (data.departmentId !== undefined) {
    await requireActiveDepartment(
      data.departmentId
    );
  }

  try {
    return await prisma.$transaction(async (tx) => {
      const current = await tx.user.findUnique({
        where: { id },
        select: {
          id: true,
          employeeCode: true,
          firstName: true,
          lastName: true,
          email: true,
          phone: true,
          avatarUrl: true,
          jobTitle: true,
          role: true,
          status: true,
          departmentId: true,
          canApproveManagerRequests: true,
        },
      });

      if (!current) {
        throw httpError("User not found", 404);
      }

      assertCanManage(actor, current);

      if (data.departmentId !== undefined) {
        await requireActiveDepartment(
          data.departmentId,
          tx
        );
      }

      const updates = { ...data };

      const emailChanged =
        updates.email !== undefined &&
        updates.email !== current.email;

      const changes = getUserChanges(
        current,
        updates
      );

      if (emailChanged) {
        updates.emailVerifiedAt = null;

        await tx.session.updateMany({
          where: {
            userId: id,
            revokedAt: null,
          },
          data: {
            revokedAt: new Date(),
          },
        });

        await tx.emailVerificationOtp.updateMany({
          where: {
            userId: id,
            consumedAt: null,
          },
          data: {
            consumedAt: new Date(),
          },
        });
      }

      // Preserve the existing update behavior.
      const user = await tx.user.update({
        where: { id },
        data: updates,
        select: userSelect,
      });

      if (Object.keys(changes).length > 0) {
        await recordActivity({
          db: tx,
          userId: actor.id,
          action: "USER_UPDATED",
          entityType: "USER",
          entityId: user.id,
          details: {
            changes,
            emailVerificationReset: emailChanged,
          },
        });
      }

      return user;
    });
  } catch (error) {
    handleDatabaseError(error);
  }
}

// --------------------------------------------------
// Change user status
// --------------------------------------------------

async function changeStatus(actor, id, status) {
  const target = await getTarget(id);

  assertCanManage(actor, target);

  if (actor.id === id) {
    throw httpError(
      "You cannot change your own account status",
      403
    );
  }

  try {
    return await prisma.$transaction(async (tx) => {
      const current = await tx.user.findUnique({
        where: { id },
        select: {
          id: true,
          role: true,
          departmentId: true,
          status: true,
        },
      });

      if (!current) {
        throw httpError("User not found", 404);
      }

      assertCanManage(actor, current);

      const previousStatus = current.status;

      const user = await tx.user.update({
        where: { id },
        data: { status },
        select: userSelect,
      });

      if (status !== "ACTIVE") {
        await tx.session.updateMany({
          where: {
            userId: id,
            revokedAt: null,
          },
          data: {
            revokedAt: new Date(),
          },
        });

        await tx.emailVerificationOtp.updateMany({
          where: {
            userId: id,
            consumedAt: null,
          },
          data: {
            consumedAt: new Date(),
          },
        });
      }

      if (previousStatus !== status) {
        await recordActivity({
          db: tx,
          userId: actor.id,
          action: "USER_STATUS_CHANGED",
          entityType: "USER",
          entityId: user.id,
          details: {
            status: {
              before: previousStatus,
              after: status,
            },
            sessionsRevoked: status !== "ACTIVE",
          },
        });
      }

      return user;
    });
  } catch (error) {
    handleDatabaseError(error);
  }
}

// --------------------------------------------------
// Change password
// --------------------------------------------------

async function changePassword(actor, id, password) {
  if (actor.role !== "ADMIN") {
    throw httpError(
      "Only Admin can reset user passwords",
      403
    );
  }

  const target = await getTarget(id);

  if (
    target.role === "ADMIN" &&
    target.id !== actor.id
  ) {
    throw httpError(
      "Cannot reset another Admin account",
      403
    );
  }

  const passwordHash = await bcrypt.hash(
    password,
    12
  );

  try {
    await prisma.$transaction(async (tx) => {
      await tx.user.update({
        where: { id },
        data: { passwordHash },
      });

      await tx.session.updateMany({
        where: {
          userId: id,
          revokedAt: null,
        },
        data: {
          revokedAt: new Date(),
        },
      });

      await tx.emailVerificationOtp.updateMany({
        where: {
          userId: id,
          consumedAt: null,
        },
        data: {
          consumedAt: new Date(),
        },
      });

      await recordActivity({
        db: tx,
        userId: actor.id,
        action: "USER_PASSWORD_RESET",
        entityType: "USER",
        entityId: id,
        details: {
          passwordChanged: true,
          sessionsRevoked: true,
          verificationOtpsInvalidated: true,
        },
      });
    });

    return {
      message:
        "Password updated. Existing sessions revoked.",
    };
  } catch (error) {
    handleDatabaseError(error);
  }
}

module.exports = {
  createUser,
  listUsers,
  getUser,
  updateUser,
  changeStatus,
  changePassword,
};