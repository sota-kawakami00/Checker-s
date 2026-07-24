/**
 * メイン査定出力の検証パイプライン（05 §3.3。順序厳守）:
 *   1. JSON Schema 適合（ajv / appraisal_result.schema.json）
 *   2. BR-02: basePrice + Σadjustments.amount == appraisedPrice
 *      （不一致 → 呼び出し側が 1 回だけ自己修正リトライ → なお不一致なら aiInvalidResponse）
 *   3. BR-01: appraisedPrice が 10,000 円単位
 *   4. evidencePhotoIds が実在する photoId を指すこと
 *   5. 相場平均の 0.3〜1.7 倍の外なら needsReview=true 付与（エラーではない）
 */

import type { AppraisalResult, MarketPriceResult } from "../types";
import { validateAgainstSchema } from "./schemaValidator";

export const APPRAISAL_RESULT_SCHEMA_FILE = "appraisal_result.schema.json";

/** 相場乖離レンジ（05 §3.3-4） */
export const MARKET_DEVIATION_MIN_RATIO = 0.3;
export const MARKET_DEVIATION_MAX_RATIO = 1.7;

export type AppraisalValidationFailureCode =
  | "schemaViolation"
  | "BR-02"
  | "BR-01"
  | "unknownEvidencePhotoId";

export type AppraisalValidationOutcome =
  | { ok: true; result: AppraisalResult; needsReview: boolean }
  | {
      ok: false;
      code: AppraisalValidationFailureCode;
      /** true = BR-02 不一致。1 回だけ自己修正リトライ可能（05 §3.3-2） */
      retryable: boolean;
      detail: string;
    };

/** 検証 2: BR-02 価格内訳整合 */
export function checkBR02(result: AppraisalResult): boolean {
  const sum = result.adjustments.reduce((acc, a) => acc + a.amount, 0);
  return result.basePrice + sum === result.appraisedPrice;
}

/** 検証 3: BR-01 1万円単位 */
export function checkBR01(result: AppraisalResult): boolean {
  return (
    Number.isInteger(result.appraisedPrice) &&
    result.appraisedPrice % 10000 === 0
  );
}

/** 検証 4: 存在しない photoId への参照を列挙する */
export function findUnknownEvidencePhotoIds(
  result: AppraisalResult,
  knownPhotoIds: ReadonlySet<string>,
): string[] {
  const unknown = new Set<string>();
  for (const adj of result.adjustments) {
    for (const id of adj.evidencePhotoIds) {
      if (!knownPhotoIds.has(id)) unknown.add(id);
    }
  }
  for (const ev of result.repairFinding.evidences) {
    if (!knownPhotoIds.has(ev.photoId)) unknown.add(ev.photoId);
  }
  return [...unknown];
}

/** 検証 5: 相場乖離。true なら needsReview 付与 */
export function isMarketDeviation(
  appraisedPrice: number,
  market: Pick<MarketPriceResult, "average"> | null,
): boolean {
  if (market === null || market.average <= 0) return false;
  const ratio = appraisedPrice / market.average;
  return (
    ratio < MARKET_DEVIATION_MIN_RATIO || ratio > MARKET_DEVIATION_MAX_RATIO
  );
}

/**
 * 検証 1〜5 を順に実行する。
 * BR-01 は schema の multipleOf でも守られるが、CF 側の独立検証として明示チェックする
 * （appraisal_result.schema.json の記述「BR-01はCF側で丸め検証」）。
 */
export function validateAppraisalResult(
  raw: unknown,
  knownPhotoIds: ReadonlySet<string>,
  market: Pick<MarketPriceResult, "average"> | null,
  schemasDir: string,
): AppraisalValidationOutcome {
  // (1) JSON Schema 適合
  const schemaResult = validateAgainstSchema(
    schemasDir,
    APPRAISAL_RESULT_SCHEMA_FILE,
    raw,
  );
  if (!schemaResult.valid) {
    return {
      ok: false,
      code: "schemaViolation",
      retryable: false,
      detail: `schema violation: ${schemaResult.errors.join("; ")}`,
    };
  }
  const result = raw as AppraisalResult;

  // (2) BR-02 内訳整合（不一致は 1 回だけ自己修正リトライ対象）
  if (!checkBR02(result)) {
    const sum = result.adjustments.reduce((acc, a) => acc + a.amount, 0);
    return {
      ok: false,
      code: "BR-02",
      retryable: true,
      detail: `BR-02 violation: basePrice(${result.basePrice}) + adjustments(${sum}) != appraisedPrice(${result.appraisedPrice})`,
    };
  }

  // (3) BR-01 1万円単位
  if (!checkBR01(result)) {
    return {
      ok: false,
      code: "BR-01",
      retryable: false,
      detail: `BR-01 violation: appraisedPrice(${result.appraisedPrice}) is not a multiple of 10000`,
    };
  }

  // (4) evidencePhotoIds 実在チェック
  const unknownIds = findUnknownEvidencePhotoIds(result, knownPhotoIds);
  if (unknownIds.length > 0) {
    return {
      ok: false,
      code: "unknownEvidencePhotoId",
      retryable: false,
      detail: `unknown evidencePhotoIds: ${unknownIds.join(", ")}`,
    };
  }

  // (5) 相場乖離 → needsReview 付与
  const needsReview =
    result.needsReview === true ||
    isMarketDeviation(result.appraisedPrice, market);

  return { ok: true, result, needsReview };
}
