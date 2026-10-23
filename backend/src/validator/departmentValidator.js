function validationError(message) {
  const error = new Error(message);
  error.statusCode = 400;
  return error;
}

function validateDepartmentId(value) {
  const id = Number(value);

  if (!Number.isSafeInteger(id) || id <= 0) {
    throw validationError("Invalid department ID");
  }

  return id;
}

function validateCreateDepartment(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw validationError("A department object is required");
  }

  const { name, code, description } = body;

  if (typeof name !== "string" || !name.trim() || name.trim().length > 100) {
    throw validationError("Department name must be 1 to 100 characters");
  }

  if (
    typeof code !== "string" ||
    !/^[A-Za-z0-9_-]{2,30}$/.test(code.trim())
  ) {
    throw validationError(
      "Department code must be 2 to 30 letters, numbers, underscores or hyphens"
    );
  }

  if (
    description !== undefined &&
    description !== null &&
    typeof description !== "string"
  ) {
    throw validationError("Description must be a string or null");
  }

  return {
    name: name.trim(),
    code: code.trim().toUpperCase(),
    description:
      typeof description === "string"
        ? description.trim() || null
        : null,
  };
}

function validateUpdateDepartment(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw validationError("A department object is required");
  }

  const allowed = ["name", "code", "description", "isActive"];
  const keys = Object.keys(body);

  if (keys.length === 0 || keys.some((key) => !allowed.includes(key))) {
    throw validationError("Invalid department update fields");
  }

  const data = {};

  if (Object.prototype.hasOwnProperty.call(body, "name")) {
    if (
      typeof body.name !== "string" ||
      !body.name.trim() ||
      body.name.trim().length > 100
    ) {
      throw validationError("Department name must be 1 to 100 characters");
    }

    data.name = body.name.trim();
  }

  if (Object.prototype.hasOwnProperty.call(body, "code")) {
    if (
      typeof body.code !== "string" ||
      !/^[A-Za-z0-9_-]{2,30}$/.test(body.code.trim())
    ) {
      throw validationError("Invalid department code");
    }

    data.code = body.code.trim().toUpperCase();
  }

  if (Object.prototype.hasOwnProperty.call(body, "description")) {
    if (body.description !== null && typeof body.description !== "string") {
      throw validationError("Description must be a string or null");
    }

    data.description =
      typeof body.description === "string"
        ? body.description.trim() || null
        : null;
  }

  if (Object.prototype.hasOwnProperty.call(body, "isActive")) {
    if (typeof body.isActive !== "boolean") {
      throw validationError("isActive must be true or false");
    }

    data.isActive = body.isActive;
  }

  return data;
}

function validateManagerAssignment(body) {
  if (
    !body ||
    typeof body !== "object" ||
    Array.isArray(body) ||
    !Object.prototype.hasOwnProperty.call(body, "managerId") ||
    Object.keys(body).length !== 1
  ) {
    throw validationError("Only managerId is allowed");
  }

  if (body.managerId === null) {
    return null;
  }

  if (!Number.isSafeInteger(body.managerId) || body.managerId <= 0) {
    throw validationError("managerId must be a positive integer or null");
  }

  return body.managerId;
}

module.exports = {
  validateDepartmentId,
  validateCreateDepartment,
  validateUpdateDepartment,
  validateManagerAssignment,
};