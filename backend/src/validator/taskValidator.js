const TASK_STATUSES = [
  "PENDING",
  "IN_PROGRESS",
  "IN_REVIEW",
  "COMPLETED",
  "CANCELLED",
];

const PRIORITIES = ["LOW", "MEDIUM", "HIGH", "URGENT"];

function httpError(message) {
  const error = new Error(message);
  error.statusCode = 400;
  return error;
}

function positiveId(value, field) {
  if (
    typeof value === "boolean" ||
    value === null ||
    value === "" ||
    !Number.isSafeInteger(Number(value)) ||
    Number(value) <= 0
  ) {
    throw httpError(`${field} must be a positive integer`);
  }

  return Number(value);
}

function validateDate(value, field) {
  if (value === undefined) return undefined;
  if (value === null || value === "") return null;

  if (
    typeof value !== "string" ||
    !/^\d{4}-\d{2}-\d{2}$/.test(value)
  ) {
    throw httpError(`${field} must use YYYY-MM-DD`);
  }

  const date = new Date(`${value}T00:00:00.000Z`);

  if (
    Number.isNaN(date.getTime()) ||
    date.toISOString().slice(0, 10) !== value
  ) {
    throw httpError(`${field} is invalid`);
  }

  return date;
}

function validateTask(body, partial = false) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw httpError("Request body must be an object");
  }

  const allowed = [
    "projectId",
    "title",
    "description",
    "priority",
    "startDate",
    "dueDate",
    "departmentId",
    "assigneeIds",
  ];

  for (const key of Object.keys(body)) {
    if (!allowed.includes(key)) {
      throw httpError(`Unknown field: ${key}`);
    }
  }

  const data = {};

  if (body.projectId !== undefined) {
    data.projectId = positiveId(body.projectId, "projectId");
  } else if (!partial) {
    throw httpError("projectId is required");
  }

  if (body.departmentId !== undefined) {
    data.departmentId = positiveId(body.departmentId, "departmentId");
  } else if (!partial) {
    throw httpError("departmentId is required");
  }

  if (body.title !== undefined) {
    if (
      typeof body.title !== "string" ||
      !body.title.trim() ||
      body.title.trim().length > 255
    ) {
      throw httpError("title must contain 1 to 255 characters");
    }

    data.title = body.title.trim();
  } else if (!partial) {
    throw httpError("title is required");
  }

  if (body.description !== undefined) {
    if (
      body.description !== null &&
      typeof body.description !== "string"
    ) {
      throw httpError("description must be a string or null");
    }

    data.description =
      typeof body.description === "string"
        ? body.description.trim() || null
        : null;
  }

  if (body.priority !== undefined) {
    if (!PRIORITIES.includes(body.priority)) {
      throw httpError("Invalid task priority");
    }

    data.priority = body.priority;
  }

  for (const field of ["startDate", "dueDate"]) {
    const value = validateDate(body[field], field);

    if (value !== undefined) {
      data[field] = value;
    }
  }

  if (
    data.startDate &&
    data.dueDate &&
    data.dueDate < data.startDate
  ) {
    throw httpError("dueDate cannot be earlier than startDate");
  }

  if (body.assigneeIds !== undefined) {
    if (!Array.isArray(body.assigneeIds)) {
      throw httpError("assigneeIds must be an array");
    }

    data.assigneeIds = [
      ...new Set(
        body.assigneeIds.map((id) =>
          positiveId(id, "assigneeIds item")
        )
      ),
    ];
  }

  if (partial && Object.keys(data).length === 0) {
    throw httpError("At least one field is required");
  }

  return data;
}

function validateProgress(body) {
  if (
    !body ||
    typeof body !== "object" ||
    Array.isArray(body) ||
    Object.keys(body).some((key) => key !== "progress")
  ) {
    throw httpError("Only progress is allowed");
  }

  const progress = body.progress;

  if (
    !Number.isInteger(progress) ||
    progress < 0 ||
    progress > 100
  ) {
    throw httpError("progress must be an integer from 0 to 100");
  }

  return progress;
}

module.exports = {
  TASK_STATUSES,
  PRIORITIES,
  positiveId,
  validateTask,
  validateProgress,
};