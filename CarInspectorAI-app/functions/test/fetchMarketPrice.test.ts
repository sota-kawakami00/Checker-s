/**
 * fetchMarketPrice コアのユニットテスト（08 §3:
 * キャッシュヒット / 期限切れ再取得 / stale 応答 / プロバイダ障害フォールバック）。
 */

import { describe, expect, it } from "vitest";
import {
  buildCacheKey,
  fetchMarketPrice,
  mileageBand,
  MARKET_CACHE_TTL_MS,
} from "../src/core/market/fetchMarketPrice";
import type { MarketPriceQuery } from "../src/core/types";
import {
  FakeClock,
  InMemoryMarketCacheRepository,
  StubMarketPriceProvider,
} from "./helpers/fakes";

const QUERY: MarketPriceQuery = {
  makerCode: "toyota",
  modelCode: "prius",
  gradeCode: null,
  modelYear: 2019,
  mileageKm: 38500,
  repairHistory: false,
};

const PROVIDER_RESULT = {
  average: 1810000,
  median: 1800000,
  sampleCount: 42,
  range: { p25: 1700000, p75: 1900000 },
  trend30d: -0.01,
};

function makeHarness() {
  const clock = new FakeClock(new Date("2026-07-24T09:00:00.000Z"));
  const cache = new InMemoryMarketCacheRepository();
  const provider = new StubMarketPriceProvider(PROVIDER_RESULT);
  const deps = { provider, cache, clock };
  return { clock, cache, provider, deps };
}

describe("cacheKey（maker_model_grade_year_mileageBand_repair）", () => {
  it("走行距離は 10,000km バンドへ正規化される", () => {
    expect(mileageBand(38500)).toBe("30k");
    expect(mileageBand(9999)).toBe("0k");
    expect(mileageBand(100000)).toBe("100k");
  });

  it("キー構成", () => {
    expect(buildCacheKey(QUERY)).toBe("toyota_prius_any_2019_30k_r0");
    expect(
      buildCacheKey({ ...QUERY, gradeCode: "S", repairHistory: true }),
    ).toBe("toyota_prius_S_2019_30k_r1");
    expect(buildCacheKey({ ...QUERY, modelYear: null })).toBe(
      "toyota_prius_any_any_30k_r0",
    );
  });
});

describe("fetchMarketPrice", () => {
  it("キャッシュヒット（24h 以内）: プロバイダを呼ばず stale:false で返す", async () => {
    const h = makeHarness();
    const fetchedAt = "2026-07-24T08:00:00.000Z"; // 1時間前
    await h.cache.set({
      key: buildCacheKey(QUERY),
      payload: { ...PROVIDER_RESULT, fetchedAt },
      fetchedAt,
    });

    const result = await fetchMarketPrice(QUERY, h.deps);
    expect(result).toEqual({ ...PROVIDER_RESULT, fetchedAt, stale: false });
    expect(h.provider.calls).toHaveLength(0);
  });

  it("キャッシュ期限切れ（24h 超）: プロバイダ再取得 + キャッシュ更新", async () => {
    const h = makeHarness();
    const oldFetchedAt = new Date(
      h.clock.now().getTime() - MARKET_CACHE_TTL_MS - 1000,
    ).toISOString();
    await h.cache.set({
      key: buildCacheKey(QUERY),
      payload: { ...PROVIDER_RESULT, average: 1700000, fetchedAt: oldFetchedAt },
      fetchedAt: oldFetchedAt,
    });

    const result = await fetchMarketPrice(QUERY, h.deps);
    expect(h.provider.calls).toHaveLength(1);
    expect(result?.average).toBe(1810000); // 新値
    expect(result?.stale).toBe(false);
    expect(result?.fetchedAt).toBe(h.clock.now().toISOString());
    // キャッシュも更新されている
    const entry = h.cache.entries.get(buildCacheKey(QUERY));
    expect(entry?.payload.average).toBe(1810000);
  });

  it("キャッシュなし: プロバイダ取得結果を保存して返す", async () => {
    const h = makeHarness();
    const result = await fetchMarketPrice(QUERY, h.deps);
    expect(result?.average).toBe(1810000);
    expect(result?.stale).toBe(false);
    expect(h.cache.entries.size).toBe(1);
  });

  it("プロバイダ障害 + 期限切れキャッシュあり: stale:true でキャッシュを返す（06 §3）", async () => {
    const h = makeHarness();
    h.provider.failing = true;
    const oldFetchedAt = new Date(
      h.clock.now().getTime() - 2 * MARKET_CACHE_TTL_MS,
    ).toISOString();
    await h.cache.set({
      key: buildCacheKey(QUERY),
      payload: { ...PROVIDER_RESULT, fetchedAt: oldFetchedAt },
      fetchedAt: oldFetchedAt,
    });

    const result = await fetchMarketPrice(QUERY, h.deps);
    expect(result?.stale).toBe(true);
    expect(result?.average).toBe(1810000);
    expect(result?.fetchedAt).toBe(oldFetchedAt);
  });

  it("プロバイダ障害 + キャッシュなし: null（相場参考なしモード）", async () => {
    const h = makeHarness();
    h.provider.failing = true;
    const result = await fetchMarketPrice(QUERY, h.deps);
    expect(result).toBeNull();
  });

  it("不正入力 → invalid-argument", async () => {
    const h = makeHarness();
    await expect(
      fetchMarketPrice({ ...QUERY, mileageKm: -1 }, h.deps),
    ).rejects.toMatchObject({ code: "invalid-argument" });
    await expect(
      fetchMarketPrice({ ...QUERY, makerCode: "" }, h.deps),
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });
});
