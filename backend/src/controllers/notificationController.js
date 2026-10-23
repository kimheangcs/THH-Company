const service = require(
  "../services/notificationService"
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

async function unreadCount(req, res, next) {
  try {
    const data = await service.getUnreadCount(
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

async function markAsRead(req, res, next) {
  try {
    const data = await service.markAsRead(
      req.params.id,
      req.user
    );

    return res.json({
      success: true,
      message: "Notification marked as read",
      data,
    });
  } catch (error) {
    next(error);
  }
}

async function markAllAsRead(req, res, next) {
  try {
    const data = await service.markAllAsRead(
      req.user
    );

    return res.json({
      success: true,
      message: "All notifications marked as read",
      data,
    });
  } catch (error) {
    next(error);
  }
}

async function remove(req, res, next) {
  try {
    const data = await service.remove(
      req.params.id,
      req.user
    );

    return res.json({
      success: true,
      message: "Notification deleted successfully",
      data,
    });
  } catch (error) {
    next(error);
  }
}

async function removeAllRead(req, res, next) {
  try {
    const data = await service.removeAllRead(
      req.user
    );

    return res.json({
      success: true,
      message: "Read notifications deleted",
      data,
    });
  } catch (error) {
    next(error);
  }
}

module.exports = {
  list,
  unreadCount,
  markAsRead,
  markAllAsRead,
  remove,
  removeAllRead,
};