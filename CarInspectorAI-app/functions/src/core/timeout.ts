/**
 * タイムアウトユーティリティ。
 * Gemini 呼び出しは 45s、CF 全体は 55s（05 §3.4）。
 */

export class TimeoutError extends Error {
  constructor(operation: string, ms: number) {
    super(`${operation} timed out after ${ms}ms`);
    this.name = "TimeoutError";
  }
}

export const GEMINI_TIMEOUT_MS = 45_000;

export async function withTimeout<T>(
  promise: Promise<T>,
  ms: number,
  operation: string,
): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      promise,
      new Promise<never>((_, reject) => {
        timer = setTimeout(() => reject(new TimeoutError(operation, ms)), ms);
      }),
    ]);
  } finally {
    if (timer !== undefined) clearTimeout(timer);
  }
}
