/**
 * store 単位レート制限のユニットテスト（05 §7: 10査定/分 + 日次上限）。
 */

import { describe, expect, it } from "vitest";
import {
  DEFAULT_RATE_LIMIT,
  RateLimiter,
  dayBucket,
  minuteBucket,
} from "../src/core/appraisal/rateLimiter";
import { FakeClock, InMemoryQuotaStore } from "./helpers/fakes";

function makeLimiter(config = DEFAULT_RATE_LIMIT) {
  const clock = new FakeClock(new Date("2026-07-24T09:00:30.000Z"));
  const limiter = new RateLimiter(new InMemoryQuotaStore(), clock, config);
  return { clock, limiter };
}

describe("バケットキー", () => {
  it("分/日バケットは UTC ベース", () => {
    const d = new Date("2026-07-24T09:00:30.000Z");
    expect(minuteBucket(d)).toBe("2026-07-24T09:00");
    expect(dayBucket(d)).toBe("2026-07-24");
  });
});

describe("RateLimiter", () => {
  it("既定 10査定/分: 10 回まで許可、11 回目で resource-exhausted", async () => {
    const { limiter } = makeLimiter();
    for (let i = 0; i < 10; i++) {
      await expect(limiter.consume("store_A")).resolves.toBeUndefined();
    }
    await expect(limiter.consume("store_A")).rejects.toMatchObject({
      code: "resource-exhausted",
    });
  });

  it("1 分経過で分カウンタはリセットされる", async () => {
    const { clock, limiter } = makeLimiter({ perMinute: 2, perDay: 100 });
    await limiter.consume("store_A");
    await limiter.consume("store_A");
    await expect(limiter.consume("store_A")).rejects.toMatchObject({
      code: "resource-exhausted",
    });

    clock.advanceMs(60_000);
    await expect(limiter.consume("store_A")).resolves.toBeUndefined();
  });

  it("日次上限は分バケットを跨いでも積算される", async () => {
    const { clock, limiter } = makeLimiter({ perMinute: 100, perDay: 3 });
    await limiter.consume("store_A");
    clock.advanceMs(10 * 60_000);
    await limiter.consume("store_A");
    clock.advanceMs(10 * 60_000);
    await limiter.consume("store_A");
    clock.advanceMs(10 * 60_000);
    await expect(limiter.consume("store_A")).rejects.toMatchObject({
      code: "resource-exhausted",
    });

    // 翌日（UTC 日付が変わる）にはリセット
    clock.set(new Date("2026-07-25T00:00:01.000Z"));
    await expect(limiter.consume("store_A")).resolves.toBeUndefined();
  });

  it("store 単位で独立してカウントされる", async () => {
    const { limiter } = makeLimiter({ perMinute: 1, perDay: 100 });
    await limiter.consume("store_A");
    await expect(limiter.consume("store_A")).rejects.toMatchObject({
      code: "resource-exhausted",
    });
    // 別 store は影響を受けない
    await expect(limiter.consume("store_B")).resolves.toBeUndefined();
  });

  it("超過エラーは aiQuotaExceeded として識別可能なメッセージを持つ", async () => {
    const { limiter } = makeLimiter({ perMinute: 0, perDay: 100 });
    const err = await limiter.consume("store_A").catch((e: unknown) => e);
    expect(err).toMatchObject({ code: "resource-exhausted" });
    expect((err as Error).message).toContain("aiQuotaExceeded");
  });
});
