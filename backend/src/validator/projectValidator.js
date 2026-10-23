const PROJECT_STATUSES = [
  "PLANNED",
  "IN_PROGRESS",
  "ON_HOLD",
  "COMPLETED",
  "CANCELLED",
];

const PRIORITIES = ["LOW", "MEDIUM", "HIGH", "URGENT"];

function badRequest(message) {
  const error = new Error(message);
  error.statusCode = 400;
  return error;
}

function positiveId(value, field) {
  const number = Number(value);

  if (!Number.isSafeInteger(number) || number <= 0) {
    throw badRequest(`${field} must be a positive integer`);
  }

  return number;
}

function text(value, field, maxLength, required = false) {
  if (value === undefined) {
    if (required) throw badRequest(`${field} is required`);
    return undefined;
  }

  if (typeof value !== "string") {
    throw badRequest(`${field} must be a string`);
  }

  const cleaned = value.trim();

  if (required && !cleaned) {
    throw badRequest(`${field} is required`);
  }

  if (cleaned.length > maxLength) {
    throw badRequest(`${field} must not exceed ${maxLength} characters`);
  }

  return cleaned || null;
}

function dateValue(value, field) {
  if (value === undefined) return undefined;
  if (value === null || value === "") return null;

  if (
    typeof value !== "string" ||
    !/^\d{4}-\d{2}-\d{2}$/.test(value)
  ) {
    throw badRequest(`${field} must use YYYY-MM-DD format`);
  }

  const date = new Date(`${value}T00:00:00.000Z`);

  if (
    Number.isNaN(date.getTime()) ||
    date.toISOString().slice(0, 10) !== value
  ) {
    throw badRequest(`${field} is not a valid date`);
  }

  return date;
}

function validateProject(body, partial = false) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw badRequest("Request body must be an object");
  }

  const allowed = [
    "code",
    "name",
    "description",
    "status",
    "priority",
    "startDate",
    "dueDate",
    "ownerDepartmentId",
    "leadManagerId",
    "departmentIds",
  ];

  for (const key of Object.keys(body)) {
    if (!allowed.includes(key)) {
      throw badRequest(`Unknown field: ${key}`);
    }
  }

  const data = {};

  for (const field of ["code", "name", "description"]) {
    const max = field === "code" ? 40 : field === "name" ? 255 : 65535;
    const value = text(
      body[field],
      field,
      max,
      !partial && field !== "description"
    );

    if (value !== undefined) data[field] = value;
  }

  if (data.code) data.code = data.code.toUpperCase();

  for (const field of ["status", "priority"]) {
    if (body[field] !== undefined) {
      const allowedValues =
        field === "status" ? PROJECT_STATUSES : PRIORITIES;

      if (!allowedValues.includes(body[field])) {
        throw badRequest(`Invalid ${field}`);
      }

      data[field] = body[field];
    }
  }

  for (const field of ["startDate", "dueDate"]) {
    const value = dateValue(body[field], field);
    if (value !== undefined) data[field] = value;
  }

  for (const field of ["ownerDepartmentId", "leadManagerId"]) {
    if (body[field] !== undefined) {
      data[field] = positiveId(body[field], field);
    } else if (!partial) {
      throw badRequest(`${field} is required`);
    }
  }

  if (body.departmentIds !== undefined) {
    if (!Array.isArray(body.departmentIds)) {
      throw badRequest("departmentIds must be an array");
    }

    data.departmentIds = [
      ...new Set(
        body.departmentIds.map((id) =>
          positiveId(id, "departmentIds item")
        )
      ),
    ];
  }

  if (
    data.startDate &&
    data.dueDate &&
    data.dueDate < data.startDate
  ) {
    throw badRequest("dueDate cannot be earlier than startDate");
  }

  if (partial && Object.keys(data).length === 0) {
    throw badRequest("At least one field is required");
  }

  return data;
}

module.exports = {
  validateProject,
  positiveId,
  PROJECT_STATUSES,
};