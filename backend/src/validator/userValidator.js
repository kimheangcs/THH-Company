const ROLES = ["ADMIN", "MANAGER", "EMPLOYEE"];
const STATUSES = ["ACTIVE", "INACTIVE", "SUSPENDED"];

function badRequest(message) {
  const error = new Error(message);
  error.statusCode = 400;
  throw error;
}

function requireObject(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    badRequest("A JSON object is required");
  }
}

function checkKeys(body, allowed, required = []) {
  requireObject(body);

  const keys = Object.keys(body);

  if (
    keys.length === 0 ||
    keys.some((key) => !allowed.includes(key)) ||
    required.some((key) => !Object.prototype.hasOwnProperty.call(body, key))
  ) {
    badRequest("Missing or unsupported fields");
  }
}

function stringField(value, name, max, required = false) {
  if (value === undefined) {
    if (required) badRequest(`${name} is required`);
    return undefined;
  }

  if (value === null) {
    if (required) badRequest(`${name} is required`);
    return null;
  }

  if (typeof value !== "string") {
    badRequest(`${name} must be a string`);
  }

  const result = value.trim();

  if (result.length > max || (required && !result)) {
    badRequest(`${name} must contain 1 to ${max} characters`);
  }

  return result || (required ? badRequest(`${name} is required`) : null);
}

function positiveId(value, name = "ID") {
  const number = Number(value);

  if (
    value === null ||
    value === undefined ||
    value === "" ||
    !Number.isSafeInteger(number) ||
    number <= 0
  ) {
    badRequest(`${name} must be a positive integer`);
  }

  return number;
}

function validateUserId(value) {
  return positiveId(value, "User ID");
}

function validatePassword(value) {
  if (
    typeof value !== "string" ||
    value.length < 12 ||
    value.length > 72 ||
    !/[a-z]/.test(value) ||
    !/[A-Z]/.test(value) ||
    !/[0-9]/.test(value) ||
    !/[^A-Za-z0-9]/.test(value)
  ) {
    badRequest(
      "Password must be 12-72 characters and include uppercase, lowercase, number and symbol"
    );
  }

  return value;
}

function validateEmail(value) {
  const email = stringField(value, "email", 191, true).toLowerCase();

  if (
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ||
    /[\r\n]/.test(email)
  ) {
    badRequest("Invalid email address");
  }

  return email;
}

function validateCreateUser(body) {
  const allowed = [
    "employeeCode",
    "firstName",
    "lastName",
    "email",
    "password",
    "phone",
    "jobTitle",
    "departmentId",
    "role",
  ];

  checkKeys(body, allowed, [
    "firstName",
    "lastName",
    "email",
    "password",
    "departmentId",
  ]);

  const data = {
    firstName: stringField(body.firstName, "firstName", 100, true),
    lastName: stringField(body.lastName, "lastName", 100, true),
    email: validateEmail(body.email),
    password: validatePassword(body.password),
    departmentId: positiveId(body.departmentId, "departmentId"),
    role: body.role === undefined ? "EMPLOYEE" : body.role,
  };

  if (!ROLES.includes(data.role) || data.role === "ADMIN") {
    badRequest("New users must have the MANAGER or EMPLOYEE role");
  }

  for (const [field, max] of [
    ["employeeCode", 30],
    ["phone", 30],
    ["jobTitle", 100],
  ]) {
    if (Object.prototype.hasOwnProperty.call(body, field)) {
      data[field] = stringField(body[field], field, max);
    }
  }

  return data;
}

function validateUpdateUser(body) {
  const allowed = [
    "employeeCode",
    "firstName",
    "lastName",
    "email",
    "phone",
    "jobTitle",
    "departmentId",
  ];

  checkKeys(body, allowed);

  const data = {};

  for (const [field, max] of [
    ["employeeCode", 30],
    ["firstName", 100],
    ["lastName", 100],
    ["email", 191],
    ["phone", 30],
    ["jobTitle", 100],
  ]) {
    if (Object.prototype.hasOwnProperty.call(body, field)) {
      if (field === "email") {
        data.email = validateEmail(body.email);
      } else {
        data[field] = stringField(
          body[field],
          field,
          max,
          field === "firstName" || field === "lastName"
        );
      }
    }
  }

  if (Object.prototype.hasOwnProperty.call(body, "departmentId")) {
    data.departmentId = positiveId(body.departmentId, "departmentId");
  }

  return data;
}

function validateStatus(body) {
  checkKeys(body, ["status"], ["status"]);

  if (!STATUSES.includes(body.status)) {
    badRequest("status must be ACTIVE, INACTIVE or SUSPENDED");
  }

  return body.status;
}

function validatePasswordChange(body) {
  checkKeys(body, ["password"], ["password"]);
  return validatePassword(body.password);
}

function validateListQuery(query) {
  const allowed = ["departmentId", "role", "status", "search"];

  if (Object.keys(query).some((key) => !allowed.includes(key))) {
    badRequest("Unsupported query parameter");
  }

  const result = {};

  if (query.departmentId !== undefined) {
    result.departmentId = positiveId(query.departmentId, "departmentId");
  }

  if (query.role !== undefined) {
    if (!ROLES.includes(query.role)) badRequest("Invalid role filter");
    result.role = query.role;
  }

  if (query.status !== undefined) {
    if (!STATUSES.includes(query.status)) badRequest("Invalid status filter");
    result.status = query.status;
  }

  if (query.search !== undefined) {
    if (typeof query.search !== "string" || query.search.length > 100) {
      badRequest("Search must be a string of at most 100 characters");
    }

    result.search = query.search.trim();
  }

  return result;
}

module.exports = {
  validateUserId,
  validateCreateUser,
  validateUpdateUser,
  validateStatus,
  validatePasswordChange,
  validateListQuery,
};