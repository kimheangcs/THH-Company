const service = require(
  "../services/taskAttachmentService"
);

function handleError(error, next) {
  if (error.code === "P2025") {
    error.statusCode = 404;
    error.message = "Attachment not found";
  }

  next(error);
}

async function upload(req, res, next) {
  try {
    const data = await service.uploadAttachment(
      req.params.taskId,
      req.file,
      req.user
    );

    return res.status(201).json({
      success: true,
      message: "Attachment uploaded successfully",
      data,
    });
  } catch (error) {
    handleError(error, next);
  }
}

async function list(req, res, next) {
  try {
    const data = await service.listAttachments(
      req.params.taskId,
      req.user
    );

    return res.json({
      success: true,
      data,
    });
  } catch (error) {
    handleError(error, next);
  }
}

async function download(req, res, next) {
  try {
    const file = await service.downloadAttachment(
      req.params.taskId,
      req.params.attachmentId,
      req.user
    );

    res.setHeader("X-Content-Type-Options", "nosniff");
    res.setHeader("Cache-Control", "private, no-store");
    res.setHeader(
      "Content-Security-Policy",
      "default-src 'none'; sandbox"
    );

    res.type("application/octet-stream");

    return res.download(
      file.filePath,
      file.fileName,
      (error) => {
        if (error) {
          if (!res.headersSent) {
            next(error);
          } else {
            res.destroy();
          }
        }
      }
    );
  } catch (error) {
    handleError(error, next);
  }
}

async function remove(req, res, next) {
  try {
    const data = await service.deleteAttachment(
      req.params.taskId,
      req.params.attachmentId,
      req.user
    );

    return res.json({
      success: true,
      message: "Attachment deleted successfully",
      data,
    });
  } catch (error) {
    handleError(error, next);
  }
}

module.exports = {
  upload,
  list,
  download,
  remove,
};