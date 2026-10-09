import type { ApiError, ErrorCode } from "@raiox/contracts";

export class AppError extends Error {
  constructor(
    readonly statusCode: number,
    readonly code: ErrorCode,
    message: string,
    readonly params?: Record<string, string>,
  ) {
    super(message);
  }

  toBody(): ApiError {
    return { error: { code: this.code, message: this.message, ...(this.params ? { params: this.params } : {}) } };
  }
}
