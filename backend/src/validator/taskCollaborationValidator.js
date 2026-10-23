function badRequest(message) {
  const error = new Error(message);
  error.statusCode = 400;
  return error;
}

function positiveId(value, field = "ID") {
  if (
    typeof value === "boolean" ||
    value === null ||
    value === "" ||
    !Number.isSafeInteger(Number(value)) ||
    Number(value) <= 0
  ) {
    throw badRequest(`${field} must be a positive integer`);
  }

  return Number(value);
}

function validateObject(body, allowedFields) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw badRequest("Request body must be an object");
  }

  for (const field of Object.keys(body)) {
    if (!allowedFields.includes(field)) {
      throw badRequest(`Unknown field: ${field}`);
    }
  }
}

function requiredText(value, field, maxLength) {
  if (
    typeof value !== "string" ||
    !value.trim() ||
    value.trim().length > maxLength
  ) {
    throw badRequest(
      `${field} must contain 1 to ${maxLength} characters`
    );
  }

  return value.trim();
}

function validateComment(body) {
  validateObject(body, ["content"]);

  return {
    content: requiredText(body.content, "content", 10000),
  };
}

function validateChecklist(body, partial = false) {
  validateObject(body, [
    "title",
    "position",
    "isCompleted",
  ]);

  const data = {};

  if (body.title !== undefined) {
    data.title = requiredText(body.title, "title", 255);
  } else if (!partial) {
    throw badRequest("title is required");
  }

  if (body.position !== undefined) {
    if (
      !Number.isSafeInteger(body.position) ||
      body.position < 0
    ) {
      throw badRequest("position must be a non-negative integer");
    }

    data.position = body.position;
  }

  if (body.isCompleted !== undefined) {
    if (typeof body.isCompleted !== "boolean") {
      throw badRequest("isCompleted must be true or false");
    }

    data.isCompleted = body.isCompleted;
  }

  if (partial && Object.keys(data).length === 0) {
    throw badRequest("At least one field is required");
  }

  return data;
}

module.exports = {
  positiveId,
  validateComment,
  validateChecklist,
};