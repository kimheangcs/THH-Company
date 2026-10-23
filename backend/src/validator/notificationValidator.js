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
    !/^[1-9]\d*$/.test(String(value)) ||
    !Number.isSafeInteger(Number(value))
  ) {
    throw badRequest(`${field} must be a positive integer`);
  }

  return Number(value);
}

function validateListQuery(query) {
  const allowed = ["page", "limit", "isRead"];

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

  let isRead;

  if (query.isRead !== undefined) {
    if (query.isRead === "true") {
      isRead = true;
    } else if (query.isRead === "false") {
      isRead = false;
    } else {
      throw badRequest("isRead must be true or false");
    }
  }

  return {
    page,
    limit,
    isRead,
  };
}

module.exports = {
  positiveId,
  validateListQuery,
};