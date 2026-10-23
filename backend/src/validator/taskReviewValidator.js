function badRequest(message) {
  const error = new Error(message);
  error.statusCode = 400;
  return error;
}

function positiveId(value, field = "ID") {
  if (
    value === null ||
    value === "" ||
    typeof value === "boolean" ||
    !Number.isSafeInteger(Number(value)) ||
    Number(value) <= 0
  ) {
    throw badRequest(`${field} must be a positive integer`);
  }

  return Number(value);
}

function validateReview(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw badRequest("Request body must be an object");
  }

  const allowed = ["decision", "comment"];

  for (const key of Object.keys(body)) {
    if (!allowed.includes(key)) {
      throw badRequest(`Unknown field: ${key}`);
    }
  }

  if (!["APPROVED", "CHANGES_REQUESTED"].includes(body.decision)) {
    throw badRequest(
      "decision must be APPROVED or CHANGES_REQUESTED"
    );
  }

  if (
    body.comment !== undefined &&
    body.comment !== null &&
    typeof body.comment !== "string"
  ) {
    throw badRequest("comment must be a string or null");
  }

  const comment =
    typeof body.comment === "string"
      ? body.comment.trim()
      : null;

  if (comment && comment.length > 10000) {
    throw badRequest("comment must not exceed 10000 characters");
  }

  if (body.decision === "CHANGES_REQUESTED" && !comment) {
    throw badRequest(
      "A comment is required when requesting changes"
    );
  }

  return {
    decision: body.decision,
    comment,
  };
}

module.exports = {
  positiveId,
  validateReview,
};