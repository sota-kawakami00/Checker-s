/**
 * fetchMarketPrice コアロジック（06 §2.3 / §3）。
 * - MarketPriceProvider interface でプロバイダ差異を吸収（v1 は単一プロバイダ）
 * - 24h キャッシュ（marketCache/{cacheKey}, key = maker_model_grade_year_mileageBand_repair）
 * - プロバイダ障害時: キャッシュがあれば stale:true で返却
 * - キャッシュもない場合は null（査定は「相場参考なし」モードで続行。
 *   confidence 減点はプロンプト側で指示済み）
 */

import type {
  Clock,
  MarketCacheRepository,
  MarketPriceProvider,
} from "../ports";
import type { MarketPriceQuery, MarketPriceResult } from "../types";
import { CoreError } from "../errors";

export const MARKET_CACHE_TTL_MS = 24 * 60 * 60 * 1000;

/** 走行距離バンド: 10,000km 刻み（例 38,500km → "30k"） */
export function mileageBand(mileageKm: number): string {
  return `${Math.floor(mileageKm / 10000) * 10}k`;
}

/** cacheKey = maker_model_grade_year_mileageBand_repair */
export function buildCacheKey(query: MarketPriceQuery): string {
  const grade = query.gradeCode ?? "any";
  const year = query.modelYear ?? "any";
  const repair = query.repairHistory ? "r1" : "r0";
  return [
    query.makerCode,
    query.modelCode,
    grade,
    year,
    mileageBand(query.mileageKm),
    repair,
  ].join("_");
}

export interface FetchMarketPriceDeps {
  provider: MarketPriceProvider;
  cache: MarketCacheRepository;
  clock: Clock;
}

function validateQuery(query: MarketPriceQuery): void {
  if (!query.makerCode || !query.modelCode) {
    throw new CoreError(
      "invalid-argument",
      "makerCode and modelCode are required",
    );
  }
  if (
    !Number.isInteger(query.mileageKm) ||
    query.mileageKm < 0 ||
    query.mileageKm > 999999
  ) {
    throw new CoreError(
      "invalid-argument",
      "mileageKm must be an integer in 0..999999",
    );
  }
}

/**
 * 相場を取得する。戻り値 null は「相場参考なし」モード（エラーではない）。
 */
export async function fetchMarketPrice(
  query: MarketPriceQuery,
  deps: FetchMarketPriceDeps,
): Promise<MarketPriceResult | null> {
  validateQuery(query);
  const cacheKey = buildCacheKey(query);
  const now = deps.clock.now();
  const cached = await deps.cache.get(cacheKey);

  // キャッシュヒット（24h 以内）: プロバイダを呼ばない
  if (cached !== null) {
    const age = now.getTime() - Date.parse(cached.fetchedAt);
    if (age >= 0 && age < MARKET_CACHE_TTL_MS) {
      return { ...cached.payload, stale: false };
    }
  }

  // 期限切れ or キャッシュなし → プロバイダへ
  try {
    const fresh = await deps.provider.fetch(query);
    const fetchedAt = now.toISOString();
    const payload = { ...fresh, fetchedAt };
    await deps.cache.set({ key: cacheKey, payload, fetchedAt });
    return { ...payload, stale: false };
  } catch {
    // プロバイダ障害: 期限切れでもキャッシュがあれば stale:true で返す（06 §3）
    if (cached !== null) {
      return { ...cached.payload, stale: true };
    }
    // キャッシュもない → 相場参考なしモード
    return null;
  }
}
