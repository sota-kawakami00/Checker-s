/**
 * Cloud Functions エントリポイント（薄いラッパー。06 §2）。
 * コアロジックは src/core/（純粋モジュール・DI）にあり、
 * ここでは認証・依存の合成・エラーマッピングのみを行う。
 *
 * すべて HTTPS Callable。認証必須（Firebase Auth + App Check）。
 * エラーは functions.https.HttpsError の code をクライアントで AppError にマップ（06 §2）。
 */

import * as path from "path";
import {
  onCall,
  HttpsError,
  type CallableRequest,
} from "firebase-functions/v2/https";
import { setGlobalOptions } from "firebase-functions/v2";
import * as logger from "firebase-functions/logger";
import { initializeApp, getApps } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";

import { isCoreError } from "./core/errors";
import type { AuditLogger, ResourcePaths } from "./core/ports";
import { systemClock } from "./core/ports";
import {
  runAppraisal as runAppraisalCore,
  type RunAppraisalDeps,
} from "./core/appraisal/runAppraisal";
import { RateLimiter } from "./core/appraisal/rateLimiter";
import { checkPhotoQuality as checkPhotoQualityCore } from "./core/photo/checkPhotoQuality";
import { fetchMarketPrice as fetchMarketPriceCore } from "./core/market/fetchMarketPrice";
import { generateAuctionComparison as generateAuctionComparisonCore } from "./core/auction/generateAuctionComparison";
import type { MarketPriceQuery, PhotoAngle } from "./core/types";
import {
  CloudStorageGateway,
  FirestoreAppraisalRepository,
  FirestoreMarketCacheRepository,
  FirestoreMasterRepository,
  FirestoreQuotaStore,
} from "./infra/firebase";
import { GeminiRestClient } from "./infra/geminiRestClient";
import { UnconfiguredMarketPriceProvider } from "./infra/marketProvider";

// CF 全体タイムアウト 55s（05 §3.4。Gemini 45s + マージン。クライアント NFR-02 の 60s と整合）
setGlobalOptions({ timeoutSeconds: 55 });

// prompts/ と schemas/ はデプロイパッケージに同梱（05 §8）。lib/ から 1 つ上がパッケージルート
const resources: ResourcePaths = {
  promptsDir: path.resolve(__dirname, "..", "prompts"),
  schemasDir: path.resolve(__dirname, "..", "schemas"),
};

const auditLogger: AuditLogger = {
  write: (entry) => logger.info("audit", entry),
};

function mapError(e: unknown): never {
  if (e instanceof HttpsError) throw e;
  if (isCoreError(e)) {
    // CoreErrorCode は FunctionsErrorCode のサブセット（1:1 マップ）
    throw new HttpsError(e.code, e.message);
  }
  logger.error("unhandled error", e);
  throw new HttpsError("internal", "internal error");
}

/**
 * 認証・認可（06 §4）。storeId は Auth カスタムクレームが正。
 * クレーム未設定のユーザーは店舗に所属していないため拒否する。
 */
function requireStoreId(request: CallableRequest<unknown>): string {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "authentication required");
  }
  const storeId = (request.auth.token as { storeId?: unknown }).storeId;
  if (typeof storeId !== "string" || storeId.length === 0) {
    throw new HttpsError(
      "permission-denied",
      "storeId custom claim is required",
    );
  }
  return storeId;
}

interface ProdDeps {
  runAppraisalDeps: RunAppraisalDeps;
  appraisals: FirestoreAppraisalRepository;
  storage: CloudStorageGateway;
  gemini: GeminiRestClient;
  marketCache: FirestoreMarketCacheRepository;
  marketProvider: UnconfiguredMarketPriceProvider;
}

let cachedDeps: ProdDeps | null = null;

function prodDeps(): ProdDeps {
  if (cachedDeps) return cachedDeps;
  if (getApps().length === 0) initializeApp();
  const db = getFirestore();
  const appraisals = new FirestoreAppraisalRepository(db);
  const storage = new CloudStorageGateway(getStorage());
  const marketCache = new FirestoreMarketCacheRepository(db);
  // GEMINI_API_KEY は Secret Manager で注入する想定
  // （firebase-functions/params の defineSecret("GEMINI_API_KEY") + onCall({ secrets: [...] })。
  //  コードへのハードコード禁止: AGENTS.md §秘密情報）
  const gemini = new GeminiRestClient(process.env.GEMINI_API_KEY);
  const marketProvider = new UnconfiguredMarketPriceProvider();

  const runAppraisalDeps: RunAppraisalDeps = {
    appraisals,
    storage,
    gemini,
    fetchMarket: (query) =>
      fetchMarketPriceCore(query, {
        provider: marketProvider,
        cache: marketCache,
        clock: systemClock,
      }),
    masters: new FirestoreMasterRepository(db),
    rateLimiter: new RateLimiter(new FirestoreQuotaStore(db), systemClock),
    clock: systemClock,
    audit: auditLogger,
    resources,
  };
  cachedDeps = {
    runAppraisalDeps,
    appraisals,
    storage,
    gemini,
    marketCache,
    marketProvider,
  };
  return cachedDeps;
}

// ---------------------------------------------------------------------------
// 2.1 runAppraisal
// ---------------------------------------------------------------------------

interface RunAppraisalRequest {
  appraisalId?: string;
  requestId?: string;
  repairConfirmed?: boolean;
}

export const runAppraisal = onCall(
  { enforceAppCheck: true },
  async (request: CallableRequest<RunAppraisalRequest>) => {
    const storeId = requireStoreId(request);
    const { appraisalId, requestId, repairConfirmed } = request.data ?? {};
    if (typeof appraisalId !== "string" || typeof requestId !== "string") {
      throw new HttpsError(
        "invalid-argument",
        "appraisalId and requestId are required",
      );
    }
    try {
      return await runAppraisalCore(
        {
          storeId,
          appraisalId,
          requestId,
          repairConfirmed: repairConfirmed ?? null,
        },
        prodDeps().runAppraisalDeps,
      );
    } catch (e) {
      mapError(e);
    }
  },
);

// ---------------------------------------------------------------------------
// 2.2 checkPhotoQuality
// ---------------------------------------------------------------------------

interface CheckPhotoQualityRequest {
  photoId?: string;
  appraisalId?: string;
  angle?: PhotoAngle;
}

export const checkPhotoQuality = onCall(
  { enforceAppCheck: true },
  async (request: CallableRequest<CheckPhotoQualityRequest>) => {
    const storeId = requireStoreId(request);
    const { photoId, appraisalId, angle } = request.data ?? {};
    if (
      typeof photoId !== "string" ||
      typeof appraisalId !== "string" ||
      typeof angle !== "string"
    ) {
      throw new HttpsError(
        "invalid-argument",
        "photoId, appraisalId and angle are required",
      );
    }
    const deps = prodDeps();
    try {
      return await checkPhotoQualityCore(
        { storeId, appraisalId, photoId, angle },
        {
          appraisals: deps.appraisals,
          storage: deps.storage,
          gemini: deps.gemini,
          clock: systemClock,
          audit: auditLogger,
          resources,
        },
      );
    } catch (e) {
      mapError(e);
    }
  },
);

// ---------------------------------------------------------------------------
// 2.3 fetchMarketPrice
// ---------------------------------------------------------------------------

interface FetchMarketPriceRequest {
  makerCode?: string;
  modelCode?: string;
  gradeCode?: string | null;
  modelYear?: number | null;
  mileageKm?: number;
  repairHistory?: boolean;
}

export const fetchMarketPrice = onCall(
  { enforceAppCheck: true },
  async (request: CallableRequest<FetchMarketPriceRequest>) => {
    requireStoreId(request);
    const data = request.data ?? {};
    if (
      typeof data.makerCode !== "string" ||
      typeof data.modelCode !== "string" ||
      typeof data.mileageKm !== "number" ||
      typeof data.repairHistory !== "boolean"
    ) {
      throw new HttpsError(
        "invalid-argument",
        "makerCode, modelCode, mileageKm and repairHistory are required",
      );
    }
    const query: MarketPriceQuery = {
      makerCode: data.makerCode,
      modelCode: data.modelCode,
      gradeCode: data.gradeCode ?? null,
      modelYear: data.modelYear ?? null,
      mileageKm: data.mileageKm,
      repairHistory: data.repairHistory,
    };
    const deps = prodDeps();
    try {
      // null = 相場参考なしモード（06 §3。エラーではない）
      return await fetchMarketPriceCore(query, {
        provider: deps.marketProvider,
        cache: deps.marketCache,
        clock: systemClock,
      });
    } catch (e) {
      mapError(e);
    }
  },
);

// ---------------------------------------------------------------------------
// 2.4 generateAuctionComparison（Phase 2 スタブ: unimplemented）
// ---------------------------------------------------------------------------

interface GenerateAuctionComparisonRequest {
  appraisalId?: string;
  auctionSheetPhotoId?: string;
}

export const generateAuctionComparison = onCall(
  { enforceAppCheck: true },
  (request: CallableRequest<GenerateAuctionComparisonRequest>) => {
    const storeId = requireStoreId(request);
    const { appraisalId, auctionSheetPhotoId } = request.data ?? {};
    if (
      typeof appraisalId !== "string" ||
      typeof auctionSheetPhotoId !== "string"
    ) {
      throw new HttpsError(
        "invalid-argument",
        "appraisalId and auctionSheetPhotoId are required",
      );
    }
    try {
      return generateAuctionComparisonCore({
        storeId,
        appraisalId,
        auctionSheetPhotoId,
      });
    } catch (e) {
      mapError(e);
    }
  },
);
