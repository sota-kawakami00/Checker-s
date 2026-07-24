/**
 * コア層のエラーモデル。
 * firebase-functions に依存しない純粋な形で保持し、src/index.ts で
 * functions.https.HttpsError の code へ 1:1 マップする（06 §2）。
 */

export type CoreErrorCode =
  | "invalid-argument"
  | "failed-precondition"
  | "resource-exhausted"
  | "unauthenticated"
  | "permission-denied"
  | "unimplemented"
  | "internal";

/** AI 失敗理由（02 §6 AppError と対応。aiStatus.reason に記録される） */
export type AiFailureReason =
  | "aiInvalidResponse"
  | "aiTimeout"
  | "aiUnavailable";

export class CoreError extends Error {
  readonly code: CoreErrorCode;
  readonly details?: unknown;

  constructor(code: CoreErrorCode, message: string, details?: unknown) {
    super(message);
    this.name = "CoreError";
    this.code = code;
    this.details = details;
  }
}

export function isCoreError(e: unknown): e is CoreError {
  return e instanceof CoreError;
}
