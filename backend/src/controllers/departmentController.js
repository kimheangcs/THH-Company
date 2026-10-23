const departmentService = require("../services/departmentService");

const {
  validateDepartmentId,
  validateCreateDepartment,
  validateUpdateDepartment,
  validateManagerAssignment,
} = require("../validator/departmentValidator");

async function create(req, res, next) {
  try {
    const data = validateCreateDepartment(req.body);

    const department =
      await departmentService.createDepartment(
        data,
        req.user.id
      );

    return res.status(201).json({
      success: true,
      message: "Department created successfully",
      department,
    });
  } catch (error) {
    next(error);
  }
}

async function list(req, res, next) {
  try {
    const departments =
      await departmentService.listDepartments(
        req.query
      );

    return res.json({
      success: true,
      count: departments.length,
      departments,
    });
  } catch (error) {
    next(error);
  }
}

async function getById(req, res, next) {
  try {
    const id = validateDepartmentId(
      req.params.id
    );

    const department =
      await departmentService.getDepartment(id);

    return res.json({
      success: true,
      department,
    });
  } catch (error) {
    next(error);
  }
}

async function update(req, res, next) {
  try {
    const id = validateDepartmentId(
      req.params.id
    );

    const data = validateUpdateDepartment(
      req.body
    );

    const department =
      await departmentService.updateDepartment(
        id,
        data,
        req.user.id
      );

    return res.json({
      success: true,
      message: "Department updated successfully",
      department,
    });
  } catch (error) {
    next(error);
  }
}

async function assignManager(req, res, next) {
  try {
    const id = validateDepartmentId(
      req.params.id
    );

    const managerId =
      validateManagerAssignment(req.body);

    const department =
      await departmentService.assignManager(
        id,
        managerId,
        req.user.id
      );

    return res.json({
      success: true,
      message:
        managerId === null
          ? "Department manager removed successfully"
          : "Department manager assigned successfully",
      department,
    });
  } catch (error) {
    next(error);
  }
}

async function remove(req, res, next) {
  try {
    const id = validateDepartmentId(
      req.params.id
    );

    const department =
      await departmentService.deactivateDepartment(
        id,
        req.user.id
      );

    return res.json({
      success: true,
      message: "Department deactivated successfully",
      department,
    });
  } catch (error) {
    next(error);
  }
}

module.exports = {
  create,
  list,
  getById,
  update,
  assignManager,
  remove,
};