/**
 * ユニットテスト用フェイク実装（08 §1: ネットワーク到達禁止）。
 * コアの ports.ts interface をインメモリで実装する。
 */

import * as path from "path";
import type {
  AppraisalRepository,
  AuditLogger,
  Clock,
  GeminiClient,
  GeminiGenerationConfig,
  GeminiStructuredResponse,
  ImageContent,
  MarketCacheRepository,
  MarketPriceProvider,
  MarketPriceProviderResult,
  MasterRepository,
  QuotaCounters,
  QuotaStore,
  ResourcePaths,
  StorageGateway,
} from "../../src/core/ports";
import type {
  AppraisalDocument,
  AuditLogEntry,
  CheckItemMaster,
  MarketCacheEntry,
  MarketPriceQuery,
  PhotoQualityResult,
  StoreSettings,
} from "../../src/core/types";

export const PACKAGE_ROOT = path.resolve(__dirname, "..", "..");

export const testResources: ResourcePaths = {
  promptsDir: path.join(PACKAGE_ROOT, "prompts"),
  schemasDir: path.join(PACKAGE_ROOT, "schemas"),
};

export const EXAMPLES_DIR = path.join(PACKAGE_ROOT, "examples");

// ---------------------------------------------------------------------------

export class FakeClock implements Clock {
  constructor(private current: Date = new Date("2026-07-24T09:00:00.000Z")) {}
  now(): Date {
    return new Date(this.current.getTime());
  }
  set(date: Date): void {
    this.current = date;
  }
  advanceMs(ms: number): void {
    this.current = new Date(this.current.getTime() + ms);
  }
}

// ---------------------------------------------------------------------------

export class InMemoryAppraisalRepository implements AppraisalRepository {
  readonly docs = new Map<string, AppraisalDocument>();

  private key(storeId: string, appraisalId: string): string {
    return `${storeId}/${appraisalId}`;
  }

  seed(storeId: string, appraisalId: string, doc: AppraisalDocument): void {
    this.docs.set(this.key(storeId, appraisalId), doc);
  }

  get(storeId: string, appraisalId: string): Promise<AppraisalDocument | null> {
    return Promise.resolve(
      this.docs.get(this.key(storeId, appraisalId)) ?? null,
    );
  }

  update(
    storeId: string,
    appraisalId: string,
    patch: Partial<AppraisalDocument>,
  ): Promise<void> {
    const key = this.key(storeId, appraisalId);
    const current = this.docs.get(key);
    if (!current) return Promise.reject(new Error(`no document: ${key}`));
    this.docs.set(key, { ...current, ...patch });
    return Promise.resolve();
  }

  updatePhotoCloudQuality(
    storeId: string,
    appraisalId: string,
    photoId: string,
    quality: PhotoQualityResult,
  ): Promise<void> {
    const key = this.key(storeId, appraisalId);
    const current = this.docs.get(key);
    if (!current) return Promise.reject(new Error(`no document: ${key}`));
    this.docs.set(key, {
      ...current,
      photos: current.photos.map((p) =>
        p.photoId === photoId ? { ...p, cloudQuality: quality } : p,
      ),
    });
    return Promise.resolve();
  }
}

// ---------------------------------------------------------------------------

export class InMemoryStorageGateway implements StorageGateway {
  readonly files = new Set<string>();

  addFiles(...paths: string[]): void {
    for (const p of paths) this.files.add(p);
  }

  exists(storagePath: string): Promise<boolean> {
    return Promise.resolve(this.files.has(storagePath));
  }

  download(storagePath: string): Promise<ImageContent> {
    if (!this.files.has(storagePath)) {
      return Promise.reject(new Error(`no such file: ${storagePath}`));
    }
    return Promise.resolve({
      base64Data: Buffer.from(`fake:${storagePath}`).toString("base64"),
      mimeType: "image/jpeg",
    });
  }
}

// ---------------------------------------------------------------------------

export interface GeminiCall {
  prompt: string;
  images: ImageContent[];
  schema: object;
  config: GeminiGenerationConfig;
}

/** 録画リプレイ方式モック（08 §1: examples/ の固定 JSON を返す） */
export class MockGeminiClient implements GeminiClient {
  readonly calls: GeminiCall[] = [];
  private readonly queue: Array<() => Promise<GeminiStructuredResponse>> = [];

  /** 次の呼び出しで JSON を返すよう積む */
  enqueueJson(json: unknown, tokens = { input: 1000, output: 500 }): void {
    this.queue.push(() => Promise.resolve({ json, tokens }));
  }

  /** 次の呼び出しで失敗するよう積む */
  enqueueError(error: Error): void {
    this.queue.push(() => Promise.reject(error));
  }

  /** 次の呼び出しが解決しない（タイムアウト検証用） */
  enqueueNever(): void {
    this.queue.push(
      () =>
        new Promise<GeminiStructuredResponse>((resolve) => {
          setTimeout(
            () =>
              resolve({ json: {}, tokens: { input: 0, output: 0 } }),
            60_000,
          ).unref?.();
        }),
    );
  }

  generateStructured(
    prompt: string,
    images: ImageContent[],
    schema: object,
    config: GeminiGenerationConfig,
  ): Promise<GeminiStructuredResponse> {
    this.calls.push({ prompt, images, schema, config });
    const next = this.queue.shift();
    if (!next) {
      return Promise.reject(new Error("MockGeminiClient: no queued response"));
    }
    return next();
  }
}

// ---------------------------------------------------------------------------

export class InMemoryMarketCacheRepository implements MarketCacheRepository {
  readonly entries = new Map<string, MarketCacheEntry>();

  get(cacheKey: string): Promise<MarketCacheEntry | null> {
    return Promise.resolve(this.entries.get(cacheKey) ?? null);
  }

  set(entry: MarketCacheEntry): Promise<void> {
    this.entries.set(entry.key, entry);
    return Promise.resolve();
  }
}

export class StubMarketPriceProvider implements MarketPriceProvider {
  calls: MarketPriceQuery[] = [];
  private result: MarketPriceProviderResult | null;
  failing = false;

  constructor(result: MarketPriceProviderResult | null = null) {
    this.result = result;
  }

  setResult(result: MarketPriceProviderResult): void {
    this.result = result;
    this.failing = false;
  }

  fetch(query: MarketPriceQuery): Promise<MarketPriceProviderResult> {
    this.calls.push(query);
    if (this.failing || this.result === null) {
      return Promise.reject(new Error("provider unavailable"));
    }
    return Promise.resolve(this.result);
  }
}

// ---------------------------------------------------------------------------

export class InMemoryQuotaStore implements QuotaStore {
  private readonly counters = new Map<string, number>();

  increment(
    storeId: string,
    minuteBucket: string,
    dayBucket: string,
  ): Promise<QuotaCounters> {
    const minuteKey = `${storeId}|m|${minuteBucket}`;
    const dayKey = `${storeId}|d|${dayBucket}`;
    const minuteCount = (this.counters.get(minuteKey) ?? 0) + 1;
    const dayCount = (this.counters.get(dayKey) ?? 0) + 1;
    this.counters.set(minuteKey, minuteCount);
    this.counters.set(dayKey, dayCount);
    return Promise.resolve({ minuteCount, dayCount });
  }
}

// ---------------------------------------------------------------------------

export class CapturingAuditLogger implements AuditLogger {
  readonly entries: AuditLogEntry[] = [];
  write(entry: AuditLogEntry): void {
    this.entries.push(entry);
  }
}

// ---------------------------------------------------------------------------

export class StubMasterRepository implements MasterRepository {
  constructor(
    private readonly items: CheckItemMaster[] = [
      { code: "spareKey", label: "スペアキー", weight: 1 },
      { code: "maintenanceBook", label: "整備手帳", weight: 1 },
      { code: "underbody", label: "下回り", weight: 2 },
    ],
    private readonly settings: StoreSettings | null = {
      targetMarginRate: 0.12,
    },
  ) {}

  checkItems(): Promise<CheckItemMaster[]> {
    return Promise.resolve(this.items);
  }

  storeSettings(_storeId: string): Promise<StoreSettings | null> {
    return Promise.resolve(this.settings);
  }
}
