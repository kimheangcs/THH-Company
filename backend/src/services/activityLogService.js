const prisma = require("../config/db");

const {
  positiveId,
  validateListQuery,
} = require("../validator/activityLogValidator");

function httpError(statusCode, message) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

const logInclude = {
  user: {
    select: {
      id: true,
      firstName: true,
      lastName: true,
      email: true,
      role: true,
    },
  },
};

const SENSITIVE_KEYS = new Set([
  "password",
  "passwordhash",
  "token",
  "accesstoken",
  "refreshtoken",
  "authorization",
  "secret",
  "jwtsecret",
  "otp",
  "codehash",
  "apikey",
  "cookie",
  "sessionid",
  "tokenhash",
]);

function sanitizeDetails(value, depth = 0) {
  if (depth > 6) return "[MAX_DEPTH]";

  if (value === null || value === undefined) {
    return null;
  }

  if (value instanceof Date) {
    return value.toISOString();
  }

  if (Array.isArray(value)) {
    return value
      .slice(0, 100)
      .map((item) => sanitizeDetails(item, depth + 1));
  }

  if (typeof value === "object") {
    const safe = {};

    for (const [key, item] of Object.entries(value)) {
      const normalized = key
        .replace(/[^a-z0-9]/gi, "")
        .toLowerCase();

      if (SENSITIVE_KEYS.has(normalized)) {
        continue;
      }

      safe[key] = sanitizeDetails(item, depth + 1);
    }

    return safe;
  }

  if (typeof value === "string") {
    return value.slice(0, 1000);
  }

  if (
    typeof value === "number" ||
    typeof value === "boolean"
  ) {
    return value;
  }

  return String(value).slice(0, 1000);
}

// Internal use only.
// Pass db: tx to write an audit record in the same
// transaction as the business operation.
async function recordActivity({
  userId = null,
  action,
  entityType,
  entityId = null,
  details = null,
  db = prisma,
}) {
  if (
    userId !== null &&
    (!Number.isSafeInteger(userId) || userId <= 0)
  ) {
    throw httpError(400, "Invalid activity userId");
  }

  if (
    entityId !== null &&
    (!Number.isSafeInteger(entityId) || entityId <= 0)
  ) {
    throw httpError(400, "Invalid activity entityId");
  }

  for (const [field, value] of Object.entries({
    action,
    entityType,
  })) {
    if (
      typeof value !== "string" ||
      !/^[A-Za-z][A-Za-z0-9_]*$/.test(value) ||
      value.length > 100
    ) {
      throw httpError(400, `Invalid ${field}`);
    }
  }

  return db.activityLog.create({
    data: {
      userId,
      action,
      entityType,
      entityId,
      details:
        details === null
          ? undefined
          : sanitizeDetails(details),
    },
  });
}

async function list(query, actor, myActivity = false) {
  if (!myActivity && actor.role !== "ADMIN") {
    throw httpError(403, "Admin access required");
  }

  const filters = validateListQuery(
    query,
    !myActivity
  );

  const where = {};

  if (myActivity) {
    where.userId = actor.id;
  } else if (filters.userId !== undefined) {
    where.userId = filters.userId;
  }

  if (filters.action !== undefined) {
    where.action = filters.action;
  }

  if (filters.entityType !== undefined) {
    where.entityType = filters.entityType;
  }

  if (filters.entityId !== undefined) {
    where.entityId = filters.entityId;
  }

  if (filters.startDate || filters.endDate) {
    where.createdAt = {};

    if (filters.startDate) {
      where.createdAt.gte = filters.startDate;
    }

    if (filters.endDate) {
      const nextDay = new Date(filters.endDate);
      nextDay.setUTCDate(nextDay.getUTCDate() + 1);

      where.createdAt.lt = nextDay;
    }
  }

  const [logs, total] = await prisma.$transaction([
    prisma.activityLog.findMany({
      where,
      include: logInclude,
      orderBy: [
        { createdAt: "desc" },
        { id: "desc" },
      ],
      skip: (filters.page - 1) * filters.limit,
      take: filters.limit,
    }),
    prisma.activityLog.count({ where }),
  ]);

  return {
    logs,
    pagination: {
      page: filters.page,
      limit: filters.limit,
      total,
      totalPages: Math.ceil(
        total / filters.limit
      ),
    },
  };
}

async function getById(id, actor) {
  if (actor.role !== "ADMIN") {
    throw httpError(403, "Admin access required");
  }

  const log = await prisma.activityLog.findUnique({
    where: {
      id: positiveId(id, "Activity log ID"),
    },
    include: logInclude,
  });

  if (!log) {
    throw httpError(404, "Activity log not found");
  }

  return log;
}

async function getEntityHistory(
  entityType,
  entityId,
  actor,
  query = {}
) {
  if (actor.role !== "ADMIN") {
    throw httpError(403, "Admin access required");
  }

  if (
    typeof entityType !== "string" ||
    !/^[A-Za-z][A-Za-z0-9_]*$/.test(entityType) ||
    entityType.length > 100
  ) {
    throw httpError(400, "Invalid entity type");
  }

  return list(
    {
      ...query,
      entityType,
      entityId: String(
        positiveId(entityId, "Entity ID")
      ),
    },
    actor
  );
}

module.exports = {
  recordActivity,
  list,
  getById,
  getEntityHistory,
};