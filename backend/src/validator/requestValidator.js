const REQUEST_TYPES = [
  "LEAVE",
  "EXPENSE",
  "PURCHASE",
  "IT_SUPPORT",
  "GENERAL",
];

const PRIORITIES = [
  "LOW",
  "MEDIUM",
  "HIGH",
  "URGENT",
];

const EDITABLE_FIELDS = [
  "title",
  "description",
  "type",
  "priority",
  "amount",
  "currency",
  "startDate",
  "endDate",
  "departmentId",
];

function httpError(message) {
  const error = new Error(message);
  error.statusCode = 400;
  return error;
}

function positiveId(value, name = "ID") {
  const id = Number(value);

  if (!Number.isSafeInteger(id) || id <= 0) {
    throw httpError(`${name} must be a positive integer`);
  }

  return id;
}

function validateCreateRequest(body) {
  if (
    !body ||
    typeof body !== "object" ||
    Array.isArray(body)
  ) {
    throw httpError("Request body must be an object");
  }

  for (const key of Object.keys(body)) {
    if (!EDITABLE_FIELDS.includes(key)) {
      throw httpError(`Unknown field: ${key}`);
    }
  }

  if (
    typeof body.title !== "string" ||
    !body.title.trim() ||
    body.title.trim().length > 255
  ) {
    throw httpError(
      "Title is required (maximum 255 characters)"
    );
  }

  if (!REQUEST_TYPES.includes(body.type)) {
    throw httpError("Invalid request type");
  }

  const data = {
    title: body.title.trim(),
    type: body.type,
    priority: body.priority ?? "MEDIUM",
    currency: body.currency ?? "USD",
  };

  if (!PRIORITIES.includes(data.priority)) {
    throw httpError("Invalid priority");
  }

  if (
    typeof data.currency !== "string" ||
    !/^[A-Z]{3}$/.test(data.currency)
  ) {
    throw httpError(
      "Currency must be a three-letter uppercase code"
    );
  }

  if (body.description !== undefined) {
    if (
      body.description !== null &&
      typeof body.description !== "string"
    ) {
      throw httpError(
        "Description must be text or null"
      );
    }

    data.description = body.description;
  }

  if (body.amount !== undefined) {
    if (body.amount === null) {
      data.amount = null;
    } else {
      const amountText = String(body.amount);

      if (!/^\d{1,13}(\.\d{1,2})?$/.test(amountText)) {
        throw httpError(
          "Amount must be a nonnegative number with up to two decimals"
        );
      }

      data.amount = amountText;
    }
  }

  for (const field of ["startDate", "endDate"]) {
    if (body[field] !== undefined) {
      if (body[field] === null) {
        data[field] = null;
      } else {
        if (typeof body[field] !== "string") {
          throw httpError(`Invalid ${field}`);
        }

        const date = new Date(body[field]);

        if (!Number.isFinite(date.getTime())) {
          throw httpError(`Invalid ${field}`);
        }

        data[field] = date;
      }
    }
  }

  if (
    data.startDate &&
    data.endDate &&
    data.endDate < data.startDate
  ) {
    throw httpError(
      "endDate cannot be earlier than startDate"
    );
  }

  if (body.departmentId !== undefined) {
    data.departmentId = positiveId(
      body.departmentId,
      "Department ID"
    );
  }

  return data;
}

function validateUpdateRequest(body, existing) {
  if (
    !body ||
    typeof body !== "object" ||
    Array.isArray(body)
  ) {
    throw httpError("Request body must be an object");
  }

  const keys = Object.keys(body);

  if (keys.length === 0) {
    throw httpError(
      "At least one field is required"
    );
  }

  for (const key of keys) {
    if (!EDITABLE_FIELDS.includes(key)) {
      throw httpError(`Unknown field: ${key}`);
    }
  }

  const merged = {
    title: existing.title,
    description: existing.description,
    type: existing.type,
    priority: existing.priority,
    amount: existing.amount == null
      ? null
      : String(existing.amount),
    currency: existing.currency,
    startDate: existing.startDate
      ? existing.startDate.toISOString()
      : null,
    endDate: existing.endDate
      ? existing.endDate.toISOString()
      : null,
    departmentId: existing.departmentId,
    ...body,
  };

  const validated = validateCreateRequest(merged);
  const result = {};

  for (const key of keys) {
    result[key] = validated[key];
  }

  // Check combined dates, including unchanged values.
  const startDate = validated.startDate;
  const endDate = validated.endDate;

  if (
    startDate &&
    endDate &&
    endDate < startDate
  ) {
    throw httpError(
      "endDate cannot be earlier than startDate"
    );
  }

  return result;
}

module.exports = {
  REQUEST_TYPES,
  PRIORITIES,
  positiveId,
  validateCreateRequest,
  validateUpdateRequest,
};