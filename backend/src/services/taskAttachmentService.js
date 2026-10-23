const prisma = require("../config/db");
const fs = require("fs/promises");
const path = require("path");
const crypto = require("crypto");

const {
  recordActivity,
} = require("./activityLogService");

const STORAGE_ROOT = path.resolve(
  process.cwd(),
  "private_uploads",
  "task_attachments"
);

const MIME_EXTENSIONS = {
  "application/pdf": [".pdf"],
  "image/jpeg": [".jpg", ".jpeg"],
  "image/png": [".png"],
  "text/plain": [".txt"],
};

function httpError(statusCode, message) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

function positiveId(value, field) {
  const id = Number(value);

  if (
    value === null ||
    value === "" ||
    typeof value === "boolean" ||
    !Number.isSafeInteger(id) ||
    id <= 0
  ) {
    throw httpError(
      400,
      `${field} must be a positive integer`
    );
  }

  return id;
}

// --------------------------------------------------
// File validation
// --------------------------------------------------

function fileIsValid(file) {
  const extension = path.extname(
    file.originalname
  ).toLowerCase();

  if (
    !MIME_EXTENSIONS[file.mimetype]?.includes(
      extension
    )
  ) {
    return false;
  }

  const buffer = file.buffer;

  if (!buffer || !buffer.length) {
    return false;
  }

  if (file.mimetype === "application/pdf") {
    return (
      buffer.subarray(0, 5).toString() === "%PDF-"
    );
  }

  if (file.mimetype === "image/jpeg") {
    return (
      buffer.length >= 4 &&
      buffer[0] === 0xff &&
      buffer[1] === 0xd8 &&
      buffer[2] === 0xff &&
      buffer[buffer.length - 2] === 0xff &&
      buffer[buffer.length - 1] === 0xd9
    );
  }

  if (file.mimetype === "image/png") {
    return (
      buffer.length >= 8 &&
      buffer.subarray(0, 8).equals(
        Buffer.from([
          137, 80, 78, 71, 13, 10, 26, 10,
        ])
      )
    );
  }

  if (file.mimetype === "text/plain") {
    if (buffer.includes(0)) {
      return false;
    }

    const decoder = new TextDecoder("utf-8", {
      fatal: true,
    });

    try {
      decoder.decode(buffer);
      return true;
    } catch {
      return false;
    }
  }

  return false;
}

function cleanFileName(name) {
  const cleaned = String(
    name || "attachment"
  )
    .replace(/\\/g, "/")
    .split("/")
    .pop()
    .replace(/[\x00-\x1f\x7f]/g, "")
    .trim();

  const extension = path.extname(cleaned);
  const base = path.basename(
    cleaned,
    extension
  );

  return (
    base.slice(
      0,
      Math.max(1, 255 - extension.length)
    ) + extension
  ) || "attachment";
}

function attachmentResponse(attachment) {
  return {
    ...attachment,
    fileSize:
      attachment.fileSize === null
        ? null
        : Number(attachment.fileSize),
    downloadUrl:
      `/api/tasks/${attachment.taskId}` +
      `/attachments/${attachment.id}/download`,
  };
}

// --------------------------------------------------
// Task access
// --------------------------------------------------

async function getTaskAccess(taskId, actor) {
  const id = positiveId(
    taskId,
    "Task ID"
  );

  const task = await prisma.task.findUnique({
    where: { id },
    include: {
      project: {
        select: {
          status: true,
          ownerDepartmentId: true,
          leadManagerId: true,
          departments: {
            select: {
              departmentId: true,
            },
          },
        },
      },
      assignments: {
        select: {
          userId: true,
        },
      },
    },
  });

  if (!task) {
    throw httpError(
      404,
      "Task not found"
    );
  }

  const assigned = task.assignments.some(
    (item) => item.userId === actor.id
  );

  const isAdmin =
    actor.role === "ADMIN";

  const managerCanView =
    actor.role === "MANAGER" &&
    actor.departmentId != null &&
    (
      task.project.ownerDepartmentId ===
        actor.departmentId ||
      task.project.departments.some(
        (item) =>
          item.departmentId ===
          actor.departmentId
      )
    );

  const managerCanManage =
    actor.role === "MANAGER" &&
    task.project.leadManagerId ===
      actor.id &&
    task.project.ownerDepartmentId ===
      actor.departmentId;

  if (
    !isAdmin &&
    !managerCanView &&
    !(
      actor.role === "EMPLOYEE" &&
      assigned
    )
  ) {
    throw httpError(
      404,
      "Task not found"
    );
  }

  return {
    task,
    canManage:
      isAdmin || managerCanManage,
    canUpload:
      isAdmin ||
      managerCanManage ||
      assigned,
  };
}

function ensureUploadAllowed(access) {
  if (!access.canUpload) {
    throw httpError(
      403,
      "You cannot upload files to this task"
    );
  }

  if (
    ["COMPLETED", "CANCELLED"].includes(
      access.task.status
    ) ||
    ["COMPLETED", "CANCELLED"].includes(
      access.task.project.status
    )
  ) {
    throw httpError(
      400,
      "Cannot upload files to a closed task or project"
    );
  }
}

function attachmentInclude() {
  return {
    uploadedBy: {
      select: {
        id: true,
        firstName: true,
        lastName: true,
        email: true,
      },
    },
  };
}

// --------------------------------------------------
// Upload attachment + audit log
// --------------------------------------------------

async function uploadAttachment(
  taskId,
  file,
  actor
) {
  const access = await getTaskAccess(
    taskId,
    actor
  );

  ensureUploadAllowed(access);

  if (!file) {
    throw httpError(
      400,
      "Please upload a file using the field name 'file'"
    );
  }

  if (!fileIsValid(file)) {
    throw httpError(
      400,
      "File content does not match an allowed file type"
    );
  }

  const extension = path.extname(
    file.originalname
  ).toLowerCase();

  const storageName =
    `${crypto.randomUUID()}${extension}`;

  const storagePath = path.join(
    STORAGE_ROOT,
    storageName
  );

  await fs.mkdir(
    STORAGE_ROOT,
    { recursive: true }
  );

  await fs.writeFile(
    storagePath,
    file.buffer,
    {
      flag: "wx",
      mode: 0o600,
    }
  );

  try {
    const attachment =
      await prisma.$transaction(
        async (tx) => {
          const created =
            await tx.taskAttachment.create({
              data: {
                taskId: access.task.id,
                uploadedById: actor.id,
                fileName: cleanFileName(
                  file.originalname
                ),
                fileUrl: storageName,
                mimeType: file.mimetype,
                fileSize: BigInt(
                  file.size
                ),
              },
              include: attachmentInclude(),
            });

          await recordActivity({
            db: tx,
            userId: actor.id,
            action:
              "TASK_ATTACHMENT_UPLOADED",
            entityType: "TASK",
            entityId: access.task.id,
            details: {
              attachmentId: created.id,
              fileName: created.fileName,
              mimeType: created.mimeType,
              fileSize: Number(
                created.fileSize
              ),
            },
          });

          return created;
        }
      );

    return attachmentResponse(
      attachment
    );
  } catch (error) {
    // Remove the uploaded file if the database
    // transaction or audit record fails.
    await fs.unlink(
      storagePath
    ).catch((cleanupError) => {
      console.error(
        "Failed to clean up uploaded file:",
        cleanupError
      );
    });

    throw error;
  }
}

// --------------------------------------------------
// List attachments
// --------------------------------------------------

async function listAttachments(
  taskId,
  actor
) {
  const access = await getTaskAccess(
    taskId,
    actor
  );

  const attachments =
    await prisma.taskAttachment.findMany({
      where: {
        taskId: access.task.id,
      },
      include: attachmentInclude(),
      orderBy: {
        createdAt: "desc",
      },
    });

  return attachments.map(
    attachmentResponse
  );
}

// --------------------------------------------------
// Get attachment
// --------------------------------------------------

async function getAttachment(
  taskId,
  attachmentId,
  actor
) {
  const access = await getTaskAccess(
    taskId,
    actor
  );

  const id = positiveId(
    attachmentId,
    "Attachment ID"
  );

  const attachment =
    await prisma.taskAttachment.findFirst({
      where: {
        id,
        taskId: access.task.id,
      },
      include: attachmentInclude(),
    });

  if (!attachment) {
    throw httpError(
      404,
      "Attachment not found"
    );
  }

  return {
    access,
    attachment,
  };
}

// --------------------------------------------------
// Storage path validation
// --------------------------------------------------

function resolveStoragePath(fileUrl) {
  if (
    typeof fileUrl !== "string" ||
    !/^[0-9a-f-]{36}\.(pdf|jpg|jpeg|png|txt)$/.test(
      fileUrl
    )
  ) {
    throw httpError(
      404,
      "Attachment storage path is invalid"
    );
  }

  return path.join(
    STORAGE_ROOT,
    fileUrl
  );
}

// --------------------------------------------------
// Download attachment
// --------------------------------------------------

async function downloadAttachment(
  taskId,
  attachmentId,
  actor
) {
  const { attachment } =
    await getAttachment(
      taskId,
      attachmentId,
      actor
    );

  const filePath = resolveStoragePath(
    attachment.fileUrl
  );

  try {
    await fs.access(filePath);
  } catch {
    throw httpError(
      404,
      "Attachment file not found"
    );
  }

  return {
    filePath,
    fileName: attachment.fileName,
    mimeType: attachment.mimeType,
  };
}

// --------------------------------------------------
// Delete attachment + audit log
// --------------------------------------------------

async function deleteAttachment(
  taskId,
  attachmentId,
  actor
) {
  const {
    access,
    attachment,
  } = await getAttachment(
    taskId,
    attachmentId,
    actor
  );

  if (
    !access.canManage &&
    attachment.uploadedById !== actor.id
  ) {
    throw httpError(
      403,
      "Only the uploader or project manager can delete this attachment"
    );
  }

  const filePath = resolveStoragePath(
    attachment.fileUrl
  );

  await prisma.$transaction(
    async (tx) => {
      // Prevent a second deletion from producing
      // a duplicate audit event.
      const result =
        await tx.taskAttachment.deleteMany({
          where: {
            id: attachment.id,
            taskId: access.task.id,
          },
        });

      if (result.count !== 1) {
        throw httpError(
          404,
          "Attachment not found"
        );
      }

      await recordActivity({
        db: tx,
        userId: actor.id,
        action:
          "TASK_ATTACHMENT_DELETED",
        entityType: "TASK",
        entityId: access.task.id,
        details: {
          attachmentId: attachment.id,
          fileName: attachment.fileName,
          mimeType: attachment.mimeType,
          fileSize:
            attachment.fileSize === null
              ? null
              : Number(
                  attachment.fileSize
                ),
          uploadedById:
            attachment.uploadedById,
        },
      });
    }
  );

  // Filesystem deletion happens after the
  // database transaction has committed.
  try {
    await fs.unlink(filePath);
  } catch (error) {
    if (error.code !== "ENOENT") {
      console.error(
        "Attachment file cleanup failed:",
        error
      );
    }
  }

  return {
    id: attachment.id,
  };
}

module.exports = {
  uploadAttachment,
  listAttachments,
  downloadAttachment,
  deleteAttachment,
};