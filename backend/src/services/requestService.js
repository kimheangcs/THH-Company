const { randomUUID } = require("node:crypto");
const prisma = require("../config/db");

const {
  positiveId,
  validateCreateRequest,
} = require("../validator/requestValidator");

const { recordActivity } = require("./activityLogService");
const { createNotification } = require("./notificationService");

function httpError(statusCode, message) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

const userSelect = {
  id: true,
  firstName: true,
  lastName: true,
  email: true,
  role: true,
};

const requestInclude = {
  submittedBy: {
    select: userSelect,
  },
  department: {
    select: {
      id: true,
      name: true,
      code: true,
    },
  },
  assignedApprover: {
    select: userSelect,
  },
  approvalSteps: {
    orderBy: {
      stepOrder: "asc",
    },
    include: {
      approver: {
        select: userSelect,
      },
    },
  },
  approvalActions: {
    orderBy: [
      { createdAt: "asc" },
      { id: "asc" },
    ],
    include: {
      actor: {
        select: userSelect,
      },
    },
  },
};

const REQUEST_STATUSES = [
  "DRAFT",
  "PENDING",
  "IN_REVIEW",
  "APPROVED",
  "REJECTED",
  "CANCELLED",
];

function visibilityFilter(actor) {
  if (actor.role === "ADMIN") {
    return {};
  }

  const conditions = [
    { submittedById: actor.id },
    { assignedApproverId: actor.id },
    {
      approvalSteps: {
        some: {
          approverId: actor.id,
        },
      },
    },
  ];

  if (
    actor.role === "MANAGER" &&
    actor.departmentId != null
  ) {
    conditions.push({
      departmentId: actor.departmentId,
    });
  }

  return { OR: conditions };
}

async function getVisibleRequest(id, actor) {
  const request = await prisma.request.findFirst({
    where: {
      AND: [
        { id: positiveId(id, "Request ID") },
        visibilityFilter(actor),
      ],
    },
    include: requestInclude,
  });

  if (!request) {
    throw httpError(404, "Request not found");
  }

  return request;
}

function validatePagination(query = {}) {
  const page = Number(query.page ?? 1);
  const limit = Number(query.limit ?? 20);

  if (
    !Number.isSafeInteger(page) ||
    page < 1 ||
    !Number.isSafeInteger(limit) ||
    limit < 1 ||
    limit > 100
  ) {
    throw httpError(400, "Invalid pagination parameters");
  }

  return { page, limit };
}

// --------------------------------------------------
// Create draft request
// --------------------------------------------------

async function create(body, actor) {
  const data = validateCreateRequest(body);

  const departmentId =
    actor.role === "ADMIN"
      ? (data.departmentId ?? actor.departmentId)
      : actor.departmentId;

  if (!departmentId) {
    throw httpError(
      400,
      "A department is required to create a request"
    );
  }

  const department = await prisma.department.findUnique({
    where: { id: departmentId },
  });

  if (!department || !department.isActive) {
    throw httpError(
      400,
      "Department is invalid or inactive"
    );
  }

  delete data.departmentId;

  return prisma.$transaction(async (tx) => {
    const request = await tx.request.create({
      data: {
        ...data,
        requestNo: `REQ-${randomUUID()}`,
        status: "DRAFT",
        submittedById: actor.id,
        departmentId,
      },
      include: requestInclude,
    });

    await recordActivity({
      db: tx,
      userId: actor.id,
      action: "APPROVAL_REQUEST_CREATED",
      entityType: "REQUEST",
      entityId: request.id,
      details: {
        requestNo: request.requestNo,
        type: request.type,
        departmentId,
      },
    });

    return request;
  });
}

// --------------------------------------------------
// List requests
// --------------------------------------------------

async function list(query, actor) {
  const { page, limit } = validatePagination(query);

  const filters = [visibilityFilter(actor)];

  if (query.status !== undefined) {
    if (!REQUEST_STATUSES.includes(query.status)) {
      throw httpError(400, "Invalid request status");
    }

    filters.push({ status: query.status });
  }

  const where = { AND: filters };

  const [requests, total] = await prisma.$transaction([
    prisma.request.findMany({
      where,
      include: requestInclude,
      orderBy: [
        { createdAt: "desc" },
        { id: "desc" },
      ],
      skip: (page - 1) * limit,
      take: limit,
    }),
    prisma.request.count({ where }),
  ]);

  return {
    requests,
    pagination: {
      page,
      limit,
      total,
      totalPages: Math.ceil(total / limit),
    },
  };
}

async function getById(id, actor) {
  return getVisibleRequest(id, actor);
}

// --------------------------------------------------
// Select eligible approver
// --------------------------------------------------

async function selectApprover(tx, request, actor) {
  if (actor.role === "EMPLOYEE") {
    const department = await tx.department.findUnique({
      where: { id: request.departmentId },
      select: {
        managerId: true,
      },
    });

    if (!department?.managerId) {
      throw httpError(
        400,
        "No department Manager is configured"
      );
    }

    const manager = await tx.user.findFirst({
      where: {
        id: department.managerId,
        role: "MANAGER",
        departmentId: request.departmentId,
        status: "ACTIVE",
        emailVerifiedAt: { not: null },
      },
      select: { id: true },
    });

    if (!manager || manager.id === actor.id) {
      throw httpError(
        400,
        "No eligible department Manager is available"
      );
    }

    return {
      approverId: manager.id,
      approverType: "DEPARTMENT_MANAGER",
    };
  }

  if (!["MANAGER", "ADMIN"].includes(actor.role)) {
    throw httpError(
      403,
      "Role cannot submit requests"
    );
  }

  const admin = await tx.user.findFirst({
    where: {
      id: { not: actor.id },
      role: "ADMIN",
      status: "ACTIVE",
      emailVerifiedAt: { not: null },
    },
    orderBy: { id: "asc" },
    select: { id: true },
  });

  if (!admin) {
    throw httpError(
      400,
      "No eligible Admin is available to approve this request"
    );
  }

  return {
    approverId: admin.id,
    approverType: "AUTHORIZED_ADMIN",
  };
}

// --------------------------------------------------
// Submit draft request
// --------------------------------------------------

async function submit(id, actor) {
  const requestId = positiveId(id, "Request ID");

  return prisma.$transaction(async (tx) => {
    const request = await tx.request.findUnique({
      where: { id: requestId },
    });

    if (!request) {
      throw httpError(404, "Request not found");
    }

    if (request.submittedById !== actor.id) {
      throw httpError(
        403,
        "Only the request creator can submit this request"
      );
    }

    if (request.status !== "DRAFT") {
      throw httpError(
        400,
        "Only draft requests can be submitted"
      );
    }

    const department = await tx.department.findUnique({
      where: { id: request.departmentId },
    });

    if (!department || !department.isActive) {
      throw httpError(
        400,
        "Request department is inactive or missing"
      );
    }

    const approver = await selectApprover(
      tx,
      request,
      actor
    );

    if (approver.approverId === actor.id) {
      throw httpError(
        403,
        "Self-approval is prohibited"
      );
    }

    const result = await tx.request.updateMany({
      where: {
        id: requestId,
        status: "DRAFT",
        submittedById: actor.id,
      },
      data: {
        status: "PENDING",
        submittedAt: new Date(),
        approverType: approver.approverType,
        assignedApproverId: approver.approverId,
      },
    });

    if (result.count !== 1) {
      throw httpError(
        409,
        "Request changed. Refresh and try again."
      );
    }

    const step = await tx.approvalStep.create({
      data: {
        requestId,
        stepOrder: 1,
        name: "Request approval",
        status: "PENDING",
        approverType: approver.approverType,
        approverId: approver.approverId,
      },
    });

    await createNotification({
      db: tx,
      userId: approver.approverId,
      type: "REQUEST_SUBMITTED",
      title: "New request awaiting approval",
      message: `Request "${request.title}" is awaiting your approval.`,
      targetUrl: `/requests/${requestId}`,
    });

    await recordActivity({
      db: tx,
      userId: actor.id,
      action: "APPROVAL_REQUEST_SUBMITTED",
      entityType: "REQUEST",
      entityId: requestId,
      details: {
        requestNo: request.requestNo,
        stepId: step.id,
        approverId: approver.approverId,
        approverType: approver.approverType,
        status: {
          before: "DRAFT",
          after: "PENDING",
        },
      },
    });

    return tx.request.findUnique({
      where: { id: requestId },
      include: requestInclude,
    });
  });
}

// --------------------------------------------------
// Pending approvals assigned to current user
// --------------------------------------------------

async function pendingApprovals(query, actor) {
  const { page, limit } = validatePagination(query);

  const where = {
    status: {
      in: ["PENDING", "IN_REVIEW"],
    },
    assignedApproverId: actor.id,
    submittedById: {
      not: actor.id,
    },
    approvalSteps: {
      some: {
        approverId: actor.id,
        status: "PENDING",
      },
    },
  };

  const [requests, total] = await prisma.$transaction([
    prisma.request.findMany({
      where,
      include: requestInclude,
      orderBy: [
        { submittedAt: "asc" },
        { id: "asc" },
      ],
      skip: (page - 1) * limit,
      take: limit,
    }),
    prisma.request.count({ where }),
  ]);

  return {
    requests,
    pagination: {
      page,
      limit,
      total,
      totalPages: Math.ceil(total / limit),
    },
  };
}

// --------------------------------------------------
// Validate approval decision body
// --------------------------------------------------

function validateDecisionBody(body, decision) {
  if (
    body == null ||
    typeof body !== "object" ||
    Array.isArray(body)
  ) {
    throw httpError(400, "Request body must be an object");
  }

  const keys = Object.keys(body);

  if (keys.some((key) => key !== "comment")) {
    throw httpError(
      400,
      "Only the comment field is allowed"
    );
  }

  const comment = body.comment ?? null;

  if (
    comment !== null &&
    (
      typeof comment !== "string" ||
      comment.length > 5000
    )
  ) {
    throw httpError(
      400,
      "Comment must be text with a maximum of 5000 characters"
    );
  }

  const cleaned = comment?.trim() || null;

  if (decision === "REJECTED" && !cleaned) {
    throw httpError(
      400,
      "A rejection reason is required"
    );
  }

  return { comment: cleaned };
}

// --------------------------------------------------
// Approve or reject an assigned request
// --------------------------------------------------

async function decide(id, decision, body, actor) {
  const requestId = positiveId(id, "Request ID");

  if (!["APPROVED", "REJECTED"].includes(decision)) {
    throw httpError(400, "Invalid approval decision");
  }

  const { comment } = validateDecisionBody(
    body,
    decision
  );

  return prisma.$transaction(async (tx) => {
    const request = await tx.request.findUnique({
      where: { id: requestId },
      include: {
        approvalSteps: {
          where: {
            status: "PENDING",
          },
          orderBy: {
            stepOrder: "asc",
          },
        },
      },
    });

    if (!request) {
      throw httpError(404, "Request not found");
    }

    if (
      !["PENDING", "IN_REVIEW"].includes(request.status)
    ) {
      throw httpError(
        409,
        "Request is not awaiting approval"
      );
    }

    if (request.submittedById === actor.id) {
      throw httpError(
        403,
        "You cannot approve or reject your own request"
      );
    }

    if (request.assignedApproverId !== actor.id) {
      throw httpError(
        403,
        "This request is assigned to another approver"
      );
    }

    if (!["ADMIN", "MANAGER"].includes(actor.role)) {
      throw httpError(
        403,
        "Your role cannot approve requests"
      );
    }

    const step = request.approvalSteps[0];

    if (
      !step ||
      step.approverId !== actor.id ||
      step.approverType !== request.approverType
    ) {
      throw httpError(
        409,
        "Approval step is missing or no longer assigned to you"
      );
    }

    const user = await tx.user.findUnique({
      where: { id: actor.id },
      select: {
        role: true,
        status: true,
        emailVerifiedAt: true,
        departmentId: true,
      },
    });

    if (
      !user ||
      user.status !== "ACTIVE" ||
      !user.emailVerifiedAt
    ) {
      throw httpError(
        403,
        "Approver account is not active and verified"
      );
    }

    if (request.approverType === "AUTHORIZED_ADMIN") {
      if (user.role !== "ADMIN") {
        throw httpError(
          403,
          "This request requires Admin approval"
        );
      }
    } else if (
      request.approverType === "DEPARTMENT_MANAGER"
    ) {
      const department = await tx.department.findUnique({
        where: { id: request.departmentId },
        select: {
          managerId: true,
          isActive: true,
        },
      });

      if (
        user.role !== "MANAGER" ||
        user.departmentId !== request.departmentId ||
        !department?.isActive ||
        department.managerId !== actor.id
      ) {
        throw httpError(
          403,
          "You are no longer the authorized department Manager"
        );
      }
    } else {
      throw httpError(
        409,
        "Request has an invalid approver type"
      );
    }

    const now = new Date();

    // Conditional updates protect against duplicate decisions.
    const stepResult = await tx.approvalStep.updateMany({
      where: {
        id: step.id,
        requestId,
        approverId: actor.id,
        status: "PENDING",
      },
      data: {
        status: decision,
        decidedAt: now,
      },
    });

    if (stepResult.count !== 1) {
      throw httpError(
        409,
        "Approval was already processed"
      );
    }

    const requestResult = await tx.request.updateMany({
      where: {
        id: requestId,
        status: {
          in: ["PENDING", "IN_REVIEW"],
        },
        assignedApproverId: actor.id,
      },
      data: {
        status: decision,
        completedAt: now,
        assignedApproverId: null,
      },
    });

    if (requestResult.count !== 1) {
      throw httpError(
        409,
        "Request state changed. Refresh and try again."
      );
    }

    const action = await tx.approvalAction.create({
      data: {
        requestId,
        stepId: step.id,
        actorId: actor.id,
        action: decision,
        comment,
      },
    });

    const approved = decision === "APPROVED";

    await createNotification({
      db: tx,
      userId: request.submittedById,
      type: approved
        ? "REQUEST_APPROVED"
        : "REQUEST_REJECTED",
      title: approved
        ? "Your request was approved"
        : "Your request was rejected",
      message: approved
        ? `Your request "${request.title}" has been approved.`
        : `Your request "${request.title}" was rejected. Check the approval history for details.`,
      targetUrl: `/requests/${requestId}`,
    });

    await recordActivity({
      db: tx,
      userId: actor.id,
      action: approved
        ? "APPROVAL_REQUEST_APPROVED"
        : "APPROVAL_REQUEST_REJECTED",
      entityType: "REQUEST",
      entityId: requestId,
      details: {
        requestNo: request.requestNo,
        stepId: step.id,
        approvalActionId: action.id,
        approverId: actor.id,
        decision,
        status: {
          before: request.status,
          after: decision,
        },
        // The rejection reason is stored in ApprovalAction,
        // not duplicated in the activity log.
      },
    });

    return tx.request.findUnique({
      where: { id: requestId },
      include: requestInclude,
    });
  });
}

async function approve(id, body, actor) {
  return decide(id, "APPROVED", body, actor);
}

async function reject(id, body, actor) {
  return decide(id, "REJECTED", body, actor);
}

// ========================================
// UPDATE DRAFT REQUEST
// ========================================

async function updateDraft(id, body, actor) {
  const requestId = positiveId(id, "Request ID");

  return prisma.$transaction(async (tx) => {
    const request = await tx.request.findUnique({
      where: { id: requestId },
    });

    if (!request) {
      throw httpError(404, "Request not found");
    }

    if (request.submittedById !== actor.id) {
      throw httpError(
        403,
        "Only the request creator can edit this request"
      );
    }

    if (request.status !== "DRAFT") {
      throw httpError(
        409,
        "Only draft requests can be edited"
      );
    }

    const {
      validateUpdateRequest,
    } = require("../validator/requestValidator");

    const data = validateUpdateRequest(body, request);

    if (data.departmentId !== undefined) {
      if (actor.role !== "ADMIN") {
        throw httpError(
          403,
          "Only an Admin can change the request department"
        );
      }

      const department = await tx.department.findUnique({
        where: { id: data.departmentId },
        select: { isActive: true },
      });

      if (!department?.isActive) {
        throw httpError(
          400,
          "Selected department is invalid or inactive"
        );
      }
    }

    const result = await tx.request.updateMany({
      where: {
        id: requestId,
        submittedById: actor.id,
        status: "DRAFT",
      },
      data,
    });

    if (result.count !== 1) {
      throw httpError(
        409,
        "Request changed. Refresh and try again."
      );
    }

    await recordActivity({
      db: tx,
      userId: actor.id,
      action: "APPROVAL_REQUEST_UPDATED",
      entityType: "REQUEST",
      entityId: requestId,
      details: {
        requestNo: request.requestNo,
        changedFields: Object.keys(data),
      },
    });

    return tx.request.findUnique({
      where: { id: requestId },
      include: requestInclude,
    });
  });
}

// ========================================
// CANCEL REQUEST
// ========================================

async function cancel(id, actor) {
  const requestId = positiveId(id, "Request ID");

  return prisma.$transaction(async (tx) => {
    const request = await tx.request.findUnique({
      where: { id: requestId },
      include: {
        approvalSteps: {
          where: { status: "PENDING" },
        },
      },
    });

    if (!request) {
      throw httpError(404, "Request not found");
    }

    if (request.submittedById !== actor.id) {
      throw httpError(
        403,
        "Only the request creator can cancel this request"
      );
    }

    const cancellable = [
      "DRAFT",
      "PENDING",
      "IN_REVIEW",
    ];

    if (!cancellable.includes(request.status)) {
      throw httpError(
        409,
        "This request can no longer be cancelled"
      );
    }

    const now = new Date();

    const result = await tx.request.updateMany({
      where: {
        id: requestId,
        submittedById: actor.id,
        status: {
          in: cancellable,
        },
      },
      data: {
        status: "CANCELLED",
        assignedApproverId: null,
        completedAt: now,
      },
    });

    if (result.count !== 1) {
      throw httpError(
        409,
        "Request changed. Refresh and try again."
      );
    }

    // Close pending steps. SKIPPED is the existing
    // ApprovalDecision enum value for an unused step.
    await tx.approvalStep.updateMany({
      where: {
        requestId,
        status: "PENDING",
      },
      data: {
        status: "SKIPPED",
        decidedAt: now,
      },
    });

    if (
      request.assignedApproverId &&
      request.assignedApproverId !== actor.id
    ) {
      await createNotification({
        db: tx,
        userId: request.assignedApproverId,
        type: "REQUEST_CANCELLED",
        title: "Request cancelled",
        message: `Request "${request.title}" has been cancelled by its creator.`,
        targetUrl: `/requests/${requestId}`,
      });
    }

    await recordActivity({
      db: tx,
      userId: actor.id,
      action: "APPROVAL_REQUEST_CANCELLED",
      entityType: "REQUEST",
      entityId: requestId,
      details: {
        requestNo: request.requestNo,
        previousApproverId: request.assignedApproverId,
        status: {
          before: request.status,
          after: "CANCELLED",
        },
      },
    });

    return tx.request.findUnique({
      where: { id: requestId },
      include: requestInclude,
    });
  });
}

// ========================================
// VIEW REQUEST APPROVAL HISTORY
// ========================================

async function getHistory(id, actor) {
  const request = await getVisibleRequest(id, actor);

  return {
    request: {
      id: request.id,
      requestNo: request.requestNo,
      title: request.title,
      type: request.type,
      status: request.status,
      submittedAt: request.submittedAt,
      completedAt: request.completedAt,
      createdAt: request.createdAt,
      updatedAt: request.updatedAt,
    },
    approvalSteps: request.approvalSteps,
    approvalActions: request.approvalActions,
  };
}

module.exports = {
  create,
  list,
  getById,
  submit,
  pendingApprovals,
  approve,
  reject,
  updateDraft,
  cancel,
  getHistory,
};