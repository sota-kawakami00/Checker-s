/**
 * 相場プロバイダの本番実装（06 §3）。
 * v1 は単一プロバイダ想定。プロバイダ API 仕様が確定し次第、
 * MarketPriceProvider 実装を差し替える（コアは interface のみに依存）。
 *
 * 現時点では接続先が未契約のため、常に失敗する実装を置く。
 * fetchMarketPrice コアはプロバイダ障害時に
 *   キャッシュあり → stale:true / キャッシュなし → null（相場参考なしモード）
 * へフォールバックするため、この実装でもシステムは安全に動作する。
 */

import type {
  MarketPriceProvider,
  MarketPriceProviderResult,
} from "../core/ports";
import type { MarketPriceQuery } from "../core/types";

export class UnconfiguredMarketPriceProvider implements MarketPriceProvider {
  fetch(_query: MarketPriceQuery): Promise<MarketPriceProviderResult> {
    return Promise.reject(
      new Error("market price provider is not configured (v1: 単一プロバイダ契約待ち)"),
    );
  }
}
