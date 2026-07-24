/**
 * store 単位レート制限（05 §7 / NFR-12）。
 * 既定: 10査定/分 + 日次上限。超過は resource-exhausted（クライアントは aiQuotaExceeded にマップ）。
 * カウンタの永続化は QuotaStore に委譲（本番: Firestore トランザクション、テスト: インメモリ）。
 */

import type { Clock, QuotaStore } from "../ports";
import { CoreError } from "../errors";

export interface RateLimitConfig {
  /** 1分あたりの査定実行上限（05 §7 例: 10査定/分） */
  perMinute: number;
  /** 日次上限 */
  perDay: number;
}

export const DEFAULT_RATE_LIMIT: RateLimitConfig = {
  perMinute: 10,
  perDay: 200,
};

/** UTC 基準の分バケットキー（例: 2026-07-24T10:31） */
export function minuteBucket(now: Date): string {
  return now.toISOString().slice(0, 16);
}

/** UTC 基準の日バケットキー（例: 2026-07-24） */
export function dayBucket(now: Date): string {
  return now.toISOString().slice(0, 10);
}

export class RateLimiter {
  constructor(
    private readonly store: QuotaStore,
    private readonly clock: Clock,
    private readonly config: RateLimitConfig = DEFAULT_RATE_LIMIT,
  ) {}

  /**
   * 1 実行分を消費する。上限超過なら resource-exhausted を throw。
   * （冪等リプレイや前提条件エラーでは呼ばないこと — 消費させない）
   */
  async consume(storeId: string): Promise<void> {
    const now = this.clock.now();
    const counters = await this.store.increment(
      storeId,
      minuteBucket(now),
      dayBucket(now),
    );
    if (counters.minuteCount > this.config.perMinute) {
      throw new CoreError(
        "resource-exhausted",
        `aiQuotaExceeded: per-minute limit (${this.config.perMinute}/min) exceeded for store ${storeId}`,
      );
    }
    if (counters.dayCount > this.config.perDay) {
      throw new CoreError(
        "resource-exhausted",
        `aiQuotaExceeded: daily limit (${this.config.perDay}/day) exceeded for store ${storeId}`,
      );
    }
  }
}
