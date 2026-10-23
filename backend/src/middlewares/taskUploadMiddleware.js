const multer = require("multer");

const MAX_FILE_SIZE = 10 * 1024 * 1024;

const ALLOWED_TYPES = new Map([
  [".pdf", "application/pdf"],
  [".jpg", "image/jpeg"],
  [".jpeg", "image/jpeg"],
  [".png", "image/png"],
  [".txt", "text/plain"],
]);

const path = require("path");

const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: MAX_FILE_SIZE,
    files: 1,
    fields: 0,
  },
  fileFilter(req, file, callback) {
    const extension = path.extname(
      file.originalname
    ).toLowerCase();

    const expectedType = ALLOWED_TYPES.get(extension);

    if (!expectedType || file.mimetype !== expectedType) {
      const error = new Error(
        "Only PDF, JPG, PNG, and TXT files are allowed"
      );

      error.statusCode = 400;
      return callback(error);
    }

    callback(null, true);
  },
}).single("file");

function taskUploadMiddleware(req, res, next) {
  upload(req, res, (error) => {
    if (!error) return next();

    if (error instanceof multer.MulterError) {
      return res.status(400).json({
        success: false,
        message:
          error.code === "LIMIT_FILE_SIZE"
            ? "File must not exceed 10 MB"
            : error.message,
      });
    }

    return res.status(error.statusCode || 400).json({
      success: false,
      message: error.message,
    });
  });
}

module.exports = taskUploadMiddleware;