/**
 * runAppraisal コアロジック（06 §2.1 / 05 §3）。
 *
 * フロー:
 *   入力検証 → 冪等性（同一 requestId は再実行せず accepted）
 *   → 前提条件検証（appraisal ドキュメント存在 + 全 photo アップロード完了）
 *   → store 単位レート制限（10査定/分 + 日次上限）
 *   → 相場取得（fetchMarketPrice。失敗時は null = 相場参考なしモード）
 *   → プロンプト構築（prompts/appraisal_main.md フロントマターの model/temperature/maxOutputTokens を使用）
 *   → Gemini 構造化出力（responseSchema 指定、タイムアウト 45s）
 *   → 検証パイプライン（05 §3.3。BR-02 不一致は 1 回だけ自己修正リトライ）
 *   → 検証通過後のみ appraisals/{id}.aiResult + aiStatus 書込
 *
 * エラー契約:
 *   - 受理前（ドキュメント不在/画像未完/quota 超過）は CoreError を throw
 *     （index.ts で HttpsError: failed-precondition / resource-exhausted にマップ）
 *   - 受理後の失敗は aiStatus = { state:"failed", reason } を書き込み
 *     { accepted: true } を返す（05 §3.4: 結果は Firestore リスナーで受信）
 */

import * as path from "path";
import { CoreError, type AiFailureReason } from "../errors";
import { loadPrompt } from "../prompts";
import { GEMINI_TIMEOUT_MS, TimeoutError, withTimeout } from "../timeout";
import type {
  AppraisalRepository,
  AuditLogger,
  Clock,
  GeminiClient,
  GeminiStructuredResponse,
  MasterRepository,
  ResourcePaths,
  StorageGateway,
} from "../ports";
import type {
  AppraisalDocument,
  AppraisalResult,
  MarketPriceQuery,
  MarketPriceResult,
} from "../types";
import { loadSchema } from "../validation/schemaValidator";
import { validateAppraisalResult } from "../validation/appraisalResultValidator";
import {
  buildAppraisalPrompt,
  buildSelfCorrectionPrompt,
} from "./promptBuilder";
import type { RateLimiter } from "./rateLimiter";

export const APPRAISAL_PROMPT_ID = "appraisal_main";

export interface RunAppraisalInput {
  storeId: string;
  appraisalId: string;
  requestId: string;
  /** BR-04: 人間確定の修復歴。true でプロンプトへ前提として渡す */
  repairConfirmed?: boolean | null;
}

export interface RunAppraisalOutput {
  accepted: true;
  /** 冪等リプレイ（同一 requestId の再送）だった場合 true */
  deduplicated?: boolean;
}

/** fetchMarketPrice コアを合成した関数型（テストで差し替え可能） */
export type MarketFetcher = (
  query: MarketPriceQuery,
) => Promise<MarketPriceResult | null>;

export interface RunAppraisalDeps {
  appraisals: AppraisalRepository;
  storage: StorageGateway;
  gemini: GeminiClient;
  fetchMarket: MarketFetcher;
  masters: MasterRepository;
  rateLimiter: RateLimiter;
  clock: Clock;
  audit: AuditLogger;
  resources: ResourcePaths;
  /** 既定 45_000ms（05 §3.4）。テスト用に注入可能 */
  geminiTimeoutMs?: number;
}

function validateInput(input: RunAppraisalInput): void {
  if (!input.storeId || !input.appraisalId || !input.requestId) {
    throw new CoreError(
      "invalid-argument",
      "storeId, appraisalId and requestId are required",
    );
  }
}

async function assertAllPhotosUploaded(
  doc: AppraisalDocument,
  storage: StorageGateway,
): Promise<void> {
  if (doc.photos.length === 0) {
    throw new CoreError(
      "failed-precondition",
      "appraisal has no photos; photo upload must be completed before runAppraisal",
    );
  }
  const flags = await Promise.all(
    doc.photos.map((p) => storage.exists(p.storagePath)),
  );
  const missing = doc.photos
    .filter((_, i) => flags[i] !== true)
    .map((p) => p.photoId);
  if (missing.length > 0) {
    throw new CoreError(
      "failed-precondition",
      `photo upload incomplete: ${missing.join(", ")}`,
    );
  }
}

function marketQueryFor(
  doc: AppraisalDocument,
  input: RunAppraisalInput,
): MarketPriceQuery {
  const repairHistory =
    input.repairConfirmed ?? doc.repairConfirmedState === "confirmedYes";
  return {
    makerCode: doc.vehicle.makerCode,
    modelCode: doc.vehicle.modelCode,
    gradeCode: doc.vehicle.gradeCode ?? null,
    modelYear: doc.vehicle.modelYear ?? null,
    mileageKm: doc.vehicle.mileageKm,
    repairHistory: repairHistory === true,
  };
}

export async function runAppraisal(
  input: RunAppraisalInput,
  deps: RunAppraisalDeps,
): Promise<RunAppraisalOutput> {
  validateInput(input);
  const { storeId, appraisalId, requestId } = input;
  const startedMs = deps.clock.now().getTime();

  const doc = await deps.appraisals.get(storeId, appraisalId);
  if (doc === null) {
    throw new CoreError(
      "failed-precondition",
      `appraisal document not found: ${appraisalId}`,
    );
  }

  // 冪等性: 同一 requestId は再実行せず accepted を返す（06 §2.1）
  if (doc.aiStatus?.requestId === requestId) {
    return { accepted: true, deduplicated: true };
  }

  // 前提条件: 全 photo の Storage アップロード完了（06 §2.1）
  await assertAllPhotosUploaded(doc, deps.storage);

  // レート制限（05 §7）。冪等リプレイ・前提条件エラーでは消費させない
  await deps.rateLimiter.consume(storeId);

  const prompt = loadPrompt(deps.resources.promptsDir, APPRAISAL_PROMPT_ID);
  const startedAtIso = deps.clock.now().toISOString();

  // 受理: 実行状態を書き込む（以降の失敗は aiStatus=failed で通知）
  await deps.appraisals.update(storeId, appraisalId, {
    status: "aiRunning",
    aiStatus: {
      state: "running",
      requestId,
      promptVersion: prompt.version,
      startedAt: startedAtIso,
    },
  });

  const tokens = { input: 0, output: 0 };
  const audit = (validation: string, detail?: string): void => {
    void deps.audit.write({
      kind: "runAppraisal",
      requestId,
      storeId,
      appraisalId,
      promptVersion: prompt.version,
      tokens: { ...tokens },
      latencyMs: deps.clock.now().getTime() - startedMs,
      validation,
      ...(detail !== undefined ? { detail } : {}),
    });
  };

  const fail = async (
    reason: AiFailureReason | "internal",
    detail: string,
  ): Promise<RunAppraisalOutput> => {
    await deps.appraisals.update(storeId, appraisalId, {
      aiStatus: {
        state: "failed",
        reason,
        requestId,
        promptVersion: prompt.version,
        startedAt: startedAtIso,
        finishedAt: deps.clock.now().toISOString(),
      },
    });
    audit(reason, detail);
    return { accepted: true };
  };

  try {
    // 相場取得。プロバイダ全滅 + キャッシュなしなら null（相場参考なしモード）
    const market = await deps.fetchMarket(marketQueryFor(doc, input));

    const [checkItems, storeSettings] = await Promise.all([
      deps.masters.checkItems(),
      deps.masters.storeSettings(storeId),
    ]);

    const images = await Promise.all(
      doc.photos.map((p) => deps.storage.download(p.storagePath)),
    );

    const schemaFile = path.basename(
      prompt.responseSchema ?? "appraisal_result.schema.json",
    );
    const responseSchema = loadSchema(deps.resources.schemasDir, schemaFile);

    const builtPrompt = buildAppraisalPrompt(prompt.body, {
      vehicle: doc.vehicle,
      photos: doc.photos,
      market,
      store: storeSettings,
      checkItems,
      repairConfirmed: input.repairConfirmed ?? null,
    });

    const timeoutMs = deps.geminiTimeoutMs ?? GEMINI_TIMEOUT_MS;
    const config = {
      model: prompt.model,
      temperature: prompt.temperature,
      maxOutputTokens: prompt.maxOutputTokens,
      timeoutMs,
    };
    const callGemini = (p: string): Promise<GeminiStructuredResponse> =>
      withTimeout(
        deps.gemini.generateStructured(p, images, responseSchema, config),
        timeoutMs,
        "gemini.generateStructured",
      );

    const knownPhotoIds: ReadonlySet<string> = new Set(
      doc.photos.map((p) => p.photoId),
    );

    const first = await callGemini(builtPrompt);
    tokens.input += first.tokens.input;
    tokens.output += first.tokens.output;

    let outcome = validateAppraisalResult(
      first.json,
      knownPhotoIds,
      market,
      deps.resources.schemasDir,
    );

    // BR-02 不一致 → 1 回だけ自己修正リトライ（05 §3.3-2）
    if (!outcome.ok && outcome.retryable) {
      const correctionPrompt = buildSelfCorrectionPrompt(
        builtPrompt,
        first.json as AppraisalResult,
        outcome.detail,
      );
      const second = await callGemini(correctionPrompt);
      tokens.input += second.tokens.input;
      tokens.output += second.tokens.output;
      outcome = validateAppraisalResult(
        second.json,
        knownPhotoIds,
        market,
        deps.resources.schemasDir,
      );
    }

    if (!outcome.ok) {
      // schema 不適合・内訳不整合等 → aiInvalidResponse（02 §6）
      return await fail("aiInvalidResponse", `${outcome.code}: ${outcome.detail}`);
    }

    const finalResult: AppraisalResult = {
      ...outcome.result,
      needsReview: outcome.needsReview,
    };

    // 検証通過後にのみ Firestore 書き込み（05 §3.3-5）
    await deps.appraisals.update(storeId, appraisalId, {
      status: "aiCompleted",
      aiResult: finalResult,
      aiProposedPrice: finalResult.appraisedPrice,
      marketAveragePrice: market?.average ?? finalResult.marketAveragePrice,
      aiStatus: {
        state: "done",
        requestId,
        promptVersion: prompt.version,
        startedAt: startedAtIso,
        finishedAt: deps.clock.now().toISOString(),
      },
    });
    audit("ok", finalResult.needsReview ? "needsReview" : undefined);
    return { accepted: true };
  } catch (e) {
    if (e instanceof TimeoutError) {
      return fail("aiTimeout", e.message);
    }
    if (e instanceof CoreError) {
      return fail("internal", e.message);
    }
    return fail(
      "aiUnavailable",
      e instanceof Error ? e.message : "unknown error",
    );
  }
}
