const fs = require("node:fs/promises");
const path = require("node:path");
const { randomUUID } = require("node:crypto");

const prisma = require("../config/db");
const requestService = require("./requestService");
const { recordActivity } = require("./activityLogService");
const {
  positiveId,
} = require("../validator/requestValidator");

const UPLOAD_DIRECTORY = path.resolve(
  process.cwd(),
  "uploads",
  "request-attachments"
);

const MAX_FILE_SIZE = 10 * 1024 * 1024;

const ALLOWED_TYPES = new Map([
  [".pdf", "application/pdf"],
  [".jpg", "image/jpeg"],
  [".jpeg", "image/jpeg"],
  [".png", "image/png"],
  [".txt", "text/plain"],
]);

function httpError(statusCode, message) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

function serializeAttachment(attachment) {
  if (!attachment) return null;

  return {
    ...attachment,
    fileSize:
      attachment.fileSize === null ||
      attachment.fileSize === undefined
        ? null
        : Number(attachment.fileSize),
  };
}

function validateFile(file) {
  if (!file || !Buffer.isBuffer(file.buffer)) {
    throw httpError(400, "Please upload a file");
  }

  if (
    file.size <= 0 ||
    file.size > MAX_FILE_SIZE
  ) {
    throw httpError(
      400,
      "File must be between 1 byte and 10 MB"
    );
  }

  const extension = path
    .extname(file.originalname)
    .toLowerCase();

  const expectedMimeType = ALLOWED_TYPES.get(extension);

  if (
    !expectedMimeType ||
    file.mimetype !== expectedMimeType
  ) {
    throw httpError(
      400,
      "Only PDF, JPG, PNG, and TXT files are allowed"
    );
  }

  const buffer = file.buffer;

  let validSignature = false;

  if (extension === ".pdf") {
    validSignature =
      buffer.length >= 5 &&
      buffer.subarray(0, 5).toString("ascii") === "%PDF-";
  } else if (
    extension === ".jpg" ||
    extension === ".jpeg"
  ) {
    validSignature =
      buffer.length >= 3 &&
      buffer[0] === 0xff &&
      buffer[1] === 0xd8 &&
      buffer[2] === 0xff;
  } else if (extension === ".png") {
    const pngSignature = Buffer.from([
      137, 80, 78, 71, 13, 10, 26, 10,
    ]);

    validSignature =
      buffer.length >= 8 &&
      buffer.subarray(0, 8).equals(pngSignature);
  } else if (extension === ".txt") {
    const text = buffer.toString("utf8");

    validSignature =
      !text.includes("\uFFFD") &&
      !text.includes("\u0000");
  }

  if (!validSignature) {
    throw httpError(
      400,
      "File content does not match the selected file type"
    );
  }

  return extension;
}

async function getVisibleRequest(requestId, actor) {
  // Reuse the existing request visibility rules.
  return requestService.getById(requestId, actor);
}

function requireDraftOwner(request, actor) {
  if (request.submittedById !== actor.id) {
    throw httpError(
      403,
      "Only the request creator can manage attachments"
    );
  }

  if (request.status !== "DRAFT") {
    throw httpError(
      409,
      "Attachments can only be changed while the request is DRAFT"
    );
  }
}

function getStoredFilePath(fileUrl) {
  const prefix = "/uploads/request-attachments/";

  if (
    typeof fileUrl !== "string" ||
    !fileUrl.startsWith(prefix)
  ) {
    throw httpError(
      500,
      "Invalid attachment storage location"
    );
  }

  const fileName = fileUrl.slice(prefix.length);

  if (
    !/^[0-9a-f-]{36}\.(pdf|jpg|jpeg|png|txt)$/.test(
      fileName
    )
  ) {
    throw httpError(
      500,
      "Invalid attachment storage filename"
    );
  }

  return path.join(UPLOAD_DIRECTORY, fileName);
}

// ========================================
// UPLOAD ATTACHMENT
// ========================================

async function uploadAttachment(requestId, file, actor) {
  const id = positiveId(requestId, "Request ID");

  const request = await getVisibleRequest(id, actor);

  requireDraftOwner(request, actor);

  const extension = validateFile(file);

  const storedName = `${randomUUID()}${extension}`;

  const fileUrl =
    `/uploads/request-attachments/${storedName}`;

  const filePath = path.join(
    UPLOAD_DIRECTORY,
    storedName
  );

  await fs.mkdir(UPLOAD_DIRECTORY, {
    recursive: true,
  });

  await fs.writeFile(filePath, file.buffer, {
    flag: "wx",
  });

  try {
    const attachment = await prisma.$transaction(
      async (tx) => {
        // Recheck status before saving metadata.
        const currentRequest =
          await tx.request.findUnique({
            where: { id },
            select: {
              id: true,
              submittedById: true,
              status: true,
            },
          });

        if (!currentRequest) {
          throw httpError(404, "Request not found");
        }

        requireDraftOwner(currentRequest, actor);

        const created =
          await tx.requestAttachment.create({
            data: {
              requestId: id,
              uploadedById: actor.id,
              fileName: path
                .basename(file.originalname)
                .slice(0, 255),
              fileUrl,
              mimeType: file.mimetype,
              fileSize: BigInt(file.size),
            },
          });

        await recordActivity({
          db: tx,
          userId: actor.id,
          action: "REQUEST_ATTACHMENT_UPLOADED",
          entityType: "REQUEST",
          entityId: id,
          details: {
            attachmentId: created.id,
            fileName: created.fileName,
            fileSize: file.size,
          },
        });

        return created;
      }
    );

    return serializeAttachment(attachment);
  } catch (error) {
    // Clean up the physical file if database work fails.
    await fs.unlink(filePath).catch(() => {});
    throw error;
  }
}

// ========================================
// LIST ATTACHMENTS
// ========================================

async function listAttachments(requestId, actor) {
  const id = positiveId(requestId, "Request ID");

  await getVisibleRequest(id, actor);

  const attachments =
    await prisma.requestAttachment.findMany({
      where: {
        requestId: id,
      },
      orderBy: {
        createdAt: "desc",
      },
      select: {
        id: true,
        requestId: true,
        uploadedById: true,
        fileName: true,
        mimeType: true,
        fileSize: true,
        createdAt: true,
        uploadedBy: {
          select: {
            id: true,
            firstName: true,
            lastName: true,
          },
        },
      },
    });

  return attachments.map(serializeAttachment);
}

// ========================================
// DOWNLOAD ATTACHMENT
// ========================================

async function downloadAttachment(
  requestId,
  attachmentId,
  actor
) {
  const id = positiveId(requestId, "Request ID");

  const attachmentIdNumber = positiveId(
    attachmentId,
    "Attachment ID"
  );

  await getVisibleRequest(id, actor);

  const attachment =
    await prisma.requestAttachment.findFirst({
      where: {
        id: attachmentIdNumber,
        requestId: id,
      },
    });

  if (!attachment) {
    throw httpError(404, "Attachment not found");
  }

  const filePath = getStoredFilePath(
    attachment.fileUrl
  );

  try {
    await fs.access(filePath);
  } catch {
    throw httpError(
      404,
      "Attachment file is missing from storage"
    );
  }

  return {
    filePath,
    fileName: attachment.fileName,
  };
}

// ========================================
// DELETE ATTACHMENT
// ========================================

async function deleteAttachment(
  requestId,
  attachmentId,
  actor
) {
  const id = positiveId(requestId, "Request ID");

  const attachmentIdNumber = positiveId(
    attachmentId,
    "Attachment ID"
  );

  const request = await getVisibleRequest(id, actor);

  requireDraftOwner(request, actor);

  const attachment =
    await prisma.requestAttachment.findFirst({
      where: {
        id: attachmentIdNumber,
        requestId: id,
      },
    });

  if (!attachment) {
    throw httpError(404, "Attachment not found");
  }

  const filePath = getStoredFilePath(
    attachment.fileUrl
  );

  await prisma.$transaction(async (tx) => {
    const currentRequest =
      await tx.request.findUnique({
        where: { id },
        select: {
          submittedById: true,
          status: true,
        },
      });

    if (!currentRequest) {
      throw httpError(404, "Request not found");
    }

    requireDraftOwner(currentRequest, actor);

    const deleted =
      await tx.requestAttachment.deleteMany({
        where: {
          id: attachmentIdNumber,
          requestId: id,
        },
      });

    if (deleted.count !== 1) {
      throw httpError(
        404,
        "Attachment not found"
      );
    }

    await recordActivity({
      db: tx,
      userId: actor.id,
      action: "REQUEST_ATTACHMENT_DELETED",
      entityType: "REQUEST",
      entityId: id,
      details: {
        attachmentId: attachment.id,
        fileName: attachment.fileName,
      },
    });
  });

  // Remove the physical file after database deletion.
  // Filesystem deletion is not part of a database transaction.
  await fs.unlink(filePath).catch((error) => {
    if (error.code !== "ENOENT") {
      console.error(
        "Attachment file cleanup failed:",
        error
      );
    }
  });

  return {
    id: attachmentIdNumber,
    requestId: id,
    deleted: true,
  };
}

module.exports = {
  uploadAttachment,
  listAttachments,
  downloadAttachment,
  deleteAttachment,
};