/**
 * 外部依存の抽象（ポート）。
 * コアロジックは本ファイルの interface のみに依存し、
 * Firestore / Storage / Gemini / 相場プロバイダ / 時刻 は全て注入される（DI）。
 * 本番実装は src/infra/、テスト実装は test/helpers/fakes.ts。
 */

import type {
  AppraisalDocument,
  AuditLogEntry,
  MarketCacheEntry,
  MarketPriceQuery,
  MarketPriceResult,
  PhotoQualityResult,
  CheckItemMaster,
  StoreSettings,
} from "./types";

// ---------------------------------------------------------------------------
// 時刻
// ---------------------------------------------------------------------------

export interface Clock {
  now(): Date;
}

export const systemClock: Clock = { now: () => new Date() };

// ---------------------------------------------------------------------------
// Firestore（stores/{storeId}/appraisals/{appraisalId} ほか）
// ---------------------------------------------------------------------------

export interface AppraisalRepository {
  get(storeId: string, appraisalId: string): Promise<AppraisalDocument | null>;
  /** 部分更新（Firestore の update に相当。undefined のフィールドは触らない） */
  update(
    storeId: string,
    appraisalId: string,
    patch: Partial<AppraisalDocument>,
  ): Promise<void>;
  /** photos 配列内の該当 photoId の cloudQuality を更新する */
  updatePhotoCloudQuality(
    storeId: string,
    appraisalId: string,
    photoId: string,
    quality: PhotoQualityResult,
  ): Promise<void>;
}

export interface MasterRepository {
  /** masters/checkItems（05 §5） */
  checkItems(): Promise<CheckItemMaster[]>;
  /** stores/{storeId}.settings */
  storeSettings(storeId: string): Promise<StoreSettings | null>;
}

export interface MarketCacheRepository {
  get(cacheKey: string): Promise<MarketCacheEntry | null>;
  set(entry: MarketCacheEntry): Promise<void>;
}

// ---------------------------------------------------------------------------
// Storage
// ---------------------------------------------------------------------------

export interface ImageContent {
  /** base64 エンコード済み画像データ */
  base64Data: string;
  mimeType: string;
}

export interface StorageGateway {
  exists(storagePath: string): Promise<boolean>;
  download(storagePath: string): Promise<ImageContent>;
}

// ---------------------------------------------------------------------------
// Gemini（クライアント抽象。本番は REST 実装、テストはモック）
// ---------------------------------------------------------------------------

export interface GeminiGenerationConfig {
  model: string;
  temperature: number;
  maxOutputTokens: number;
  /** ミリ秒。呼び出し側の既定は 45_000（05 §3.4） */
  timeoutMs?: number;
}

export interface GeminiStructuredResponse {
  /** パース済み JSON（スキーマ適合は呼び出し側で検証する） */
  json: unknown;
  tokens: { input: number; output: number };
}

export interface GeminiClient {
  generateStructured(
    prompt: string,
    images: ImageContent[],
    schema: object,
    config: GeminiGenerationConfig,
  ): Promise<GeminiStructuredResponse>;
}

// ---------------------------------------------------------------------------
// 相場プロバイダ（06 §3: v1 は単一プロバイダ。差異はこの interface で吸収）
// ---------------------------------------------------------------------------

/** プロバイダ生応答を正規化した形（stale はキャッシュ層の関心なので含まない） */
export type MarketPriceProviderResult = Omit<
  MarketPriceResult,
  "stale" | "fetchedAt"
>;

export interface MarketPriceProvider {
  fetch(query: MarketPriceQuery): Promise<MarketPriceProviderResult>;
}

// ---------------------------------------------------------------------------
// レート制限（05 §7: store 単位 10査定/分 + 日次上限）
// ---------------------------------------------------------------------------

export interface QuotaCounters {
  minuteCount: number;
  dayCount: number;
}

/**
 * 分/日バケットのカウンタを原子的にインクリメントして返す。
 * 本番実装は Firestore トランザクション、テストはインメモリ。
 */
export interface QuotaStore {
  increment(
    storeId: string,
    minuteBucket: string,
    dayBucket: string,
  ): Promise<QuotaCounters>;
}

// ---------------------------------------------------------------------------
// 監査ログ（05 §3.4/§8: requestId, storeId, promptVersion, tokens, latency, 検証結果）
// ---------------------------------------------------------------------------

export interface AuditLogger {
  write(entry: AuditLogEntry): void | Promise<void>;
}

// ---------------------------------------------------------------------------
// バンドルリソース（prompts/ と schemas/ は CF デプロイ時に同梱される。05 §8）
// ---------------------------------------------------------------------------

export interface ResourcePaths {
  promptsDir: string;
  schemasDir: string;
}
