const service = require(
  "../services/activityLogService"
);

async function list(req, res, next) {
  try {
    const data = await service.list(
      req.query,
      req.user
    );

    return res.json({
      success: true,
      data,
    });
  } catch (error) {
    next(error);
  }
}

async function myActivity(req, res, next) {
  try {
    const data = await service.list(
      req.query,
      req.user,
      true
    );

    return res.json({
      success: true,
      data,
    });
  } catch (error) {
    next(error);
  }
}

async function getById(req, res, next) {
  try {
    const data = await service.getById(
      req.params.id,
      req.user
    );

    return res.json({
      success: true,
      data,
    });
  } catch (error) {
    next(error);
  }
}

async function getEntityHistory(req, res, next) {
  try {
    const data = await service.getEntityHistory(
      req.params.entityType,
      req.params.entityId,
      req.user,
      req.query
    );

    return res.json({
      success: true,
      data,
    });
  } catch (error) {
    next(error);
  }
}

module.exports = {
  list,
  myActivity,
  getById,
  getEntityHistory,
};
