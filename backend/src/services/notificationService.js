const prisma = require("../config/db");

const {
  positiveId,
  validateListQuery,
} = require("../validator/notificationValidator");

function httpError(statusCode, message) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

// Accepts either the main Prisma client or a transaction client.
// This lets task operations and their notifications commit together.
async function createNotification({
  userId,
  type,
  title,
  message,
  targetUrl = null,
  db = prisma,
}) {
  if (!Number.isSafeInteger(userId) || userId <= 0) {
    throw httpError(400, "Invalid notification recipient");
  }

  if (
    typeof title !== "string" ||
    !title.trim() ||
    title.length > 255
  ) {
    throw httpError(400, "Invalid notification title");
  }

  if (
    typeof message !== "string" ||
    !message.trim()
  ) {
    throw httpError(400, "Invalid notification message");
  }

  if (
    targetUrl !== null &&
    (
      typeof targetUrl !== "string" ||
      !targetUrl.startsWith("/") ||
      targetUrl.startsWith("//") ||
      targetUrl.length > 500
    )
  ) {
    throw httpError(400, "Invalid notification target URL");
  }

  return db.notification.create({
    data: {
      userId,
      type,
      title: title.trim(),
      message: message.trim(),
      targetUrl,
    },
  });
}

async function createNotifications(items, db = prisma) {
  if (!Array.isArray(items) || items.length === 0) {
    return { count: 0 };
  }

  const notifications = [];

  for (const item of items) {
    if (
      !Number.isSafeInteger(item.userId) ||
      item.userId <= 0
    ) {
      throw httpError(400, "Invalid notification recipient");
    }

    if (
      typeof item.title !== "string" ||
      !item.title.trim() ||
      item.title.length > 255
    ) {
      throw httpError(400, "Invalid notification title");
    }

    if (
      typeof item.message !== "string" ||
      !item.message.trim()
    ) {
      throw httpError(400, "Invalid notification message");
    }

    if (
      item.targetUrl != null &&
      (
        typeof item.targetUrl !== "string" ||
        !item.targetUrl.startsWith("/") ||
        item.targetUrl.startsWith("//") ||
        item.targetUrl.length > 500
      )
    ) {
      throw httpError(400, "Invalid notification target URL");
    }

    notifications.push({
      userId: item.userId,
      type: item.type,
      title: item.title.trim(),
      message: item.message.trim(),
      targetUrl: item.targetUrl ?? null,
    });
  }

  return db.notification.createMany({
    data: notifications,
  });
}

async function list(query, actor) {
  const { page, limit, isRead } = validateListQuery(query);

  const where = {
    userId: actor.id,
    ...(isRead !== undefined ? { isRead } : {}),
  };

  const [notifications, total, unreadCount] =
    await prisma.$transaction([
      prisma.notification.findMany({
        where,
        orderBy: [
          { createdAt: "desc" },
          { id: "desc" },
        ],
        skip: (page - 1) * limit,
        take: limit,
      }),
      prisma.notification.count({ where }),
      prisma.notification.count({
        where: {
          userId: actor.id,
          isRead: false,
        },
      }),
    ]);

  return {
    notifications,
    pagination: {
      page,
      limit,
      total,
      totalPages: Math.ceil(total / limit),
    },
    unreadCount,
  };
}

async function getUnreadCount(actor) {
  const count = await prisma.notification.count({
    where: {
      userId: actor.id,
      isRead: false,
    },
  });

  return { unreadCount: count };
}

async function markAsRead(id, actor) {
  const notificationId = positiveId(id, "Notification ID");

  const result = await prisma.notification.updateMany({
    where: {
      id: notificationId,
      userId: actor.id,
      isRead: false,
    },
    data: {
      isRead: true,
      readAt: new Date(),
    },
  });

  if (result.count === 0) {
    const existing = await prisma.notification.findFirst({
      where: {
        id: notificationId,
        userId: actor.id,
      },
    });

    if (!existing) {
      throw httpError(404, "Notification not found");
    }

    return existing;
  }

  return prisma.notification.findFirst({
    where: {
      id: notificationId,
      userId: actor.id,
    },
  });
}

async function markAllAsRead(actor) {
  const result = await prisma.notification.updateMany({
    where: {
      userId: actor.id,
      isRead: false,
    },
    data: {
      isRead: true,
      readAt: new Date(),
    },
  });

  return {
    updatedCount: result.count,
  };
}

async function remove(id, actor) {
  const notificationId = positiveId(id, "Notification ID");

  const result = await prisma.notification.deleteMany({
    where: {
      id: notificationId,
      userId: actor.id,
    },
  });

  if (result.count === 0) {
    throw httpError(404, "Notification not found");
  }

  return { id: notificationId };
}

async function removeAllRead(actor) {
  const result = await prisma.notification.deleteMany({
    where: {
      userId: actor.id,
      isRead: true,
    },
  });

  return {
    deletedCount: result.count,
  };
}

module.exports = {
  createNotification,
  createNotifications,
  list,
  getUnreadCount,
  markAsRead,
  markAllAsRead,
  remove,
  removeAllRead,
};