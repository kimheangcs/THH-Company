function badRequest(message) {
  const error = new Error(message);
  error.statusCode = 400;
  return error;
}

function positiveId(value, field = "ID") {
  if (
    typeof value !== "string" &&
    typeof value !== "number"
  ) {
    throw badRequest(`${field} must be a positive integer`);
  }

  if (
    !/^[1-9]\d*$/.test(String(value)) ||
    !Number.isSafeInteger(Number(value))
  ) {
    throw badRequest(`${field} must be a positive integer`);
  }

  return Number(value);
}

function validateDate(value, field) {
  if (value === undefined) return undefined;

  if (
    typeof value !== "string" ||
    !/^\d{4}-\d{2}-\d{2}$/.test(value)
  ) {
    throw badRequest(`${field} must use YYYY-MM-DD`);
  }

  const date = new Date(`${value}T00:00:00.000Z`);

  if (
    Number.isNaN(date.getTime()) ||
    date.toISOString().slice(0, 10) !== value
  ) {
    throw badRequest(`Invalid ${field}`);
  }

  return date;
}

function validateListQuery(query, allowUserId = true) {
  const allowed = [
    "page",
    "limit",
    "action",
    "entityType",
    "entityId",
    "startDate",
    "endDate",
  ];

  if (allowUserId) allowed.push("userId");

  for (const key of Object.keys(query)) {
    if (!allowed.includes(key)) {
      throw badRequest(`Unknown query parameter: ${key}`);
    }
  }

  const page =
    query.page === undefined
      ? 1
      : positiveId(query.page, "page");

  const limit =
    query.limit === undefined
      ? 20
      : positiveId(query.limit, "limit");

  if (limit > 100) {
    throw badRequest("limit cannot exceed 100");
  }

  const result = { page, limit };

  if (query.userId !== undefined) {
    result.userId = positiveId(query.userId, "userId");
  }

  if (query.entityId !== undefined) {
    result.entityId = positiveId(
      query.entityId,
      "entityId"
    );
  }

  for (const field of ["action", "entityType"]) {
    if (query[field] !== undefined) {
      const value = query[field];

      if (
        typeof value !== "string" ||
        !value.trim() ||
        value.length > 100 ||
        !/^[A-Za-z][A-Za-z0-9_]*$/.test(value)
      ) {
        throw badRequest(`Invalid ${field}`);
      }

      result[field] = value.trim();
    }
  }

  result.startDate = validateDate(
    query.startDate,
    "startDate"
  );

  result.endDate = validateDate(
    query.endDate,
    "endDate"
  );

  if (
    result.startDate &&
    result.endDate &&
    result.endDate < result.startDate
  ) {
    throw badRequest(
      "endDate cannot be earlier than startDate"
    );
  }

  return result;
}

module.exports = {
  positiveId,
  validateListQuery,
};