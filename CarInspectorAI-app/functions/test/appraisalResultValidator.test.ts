/**
 * 検証パイプライン単体テスト（05 §3.3 / 08 §2.1 ケース表）。
 */

import { describe, expect, it } from "vitest";
import {
  checkBR01,
  checkBR02,
  findUnknownEvidencePhotoIds,
  isMarketDeviation,
  validateAppraisalResult,
} from "../src/core/validation/appraisalResultValidator";
import type { AppraisalResult } from "../src/core/types";
import { testResources } from "./helpers/fakes";
import { exampleAppraisalResult } from "./helpers/fixtures";

const KNOWN_IDS: ReadonlySet<string> = new Set([
  "ph_front_001",
  "ph_left_003",
  "ph_fl_005",
  "ph_intf_009",
  "ph_intr_010",
  "ph_dmg_013",
]);

const MARKET = { average: 1810000 };

function validate(result: unknown, market = MARKET) {
  return validateAppraisalResult(
    result,
    KNOWN_IDS,
    market,
    testResources.schemasDir,
  );
}

describe("BR-02 価格内訳整合", () => {
  it("UT-BR02-01: base 1,810,000 + (+50k+30k-40k-20k-10k) = 1,820,000 → 検証OK", () => {
    const result = exampleAppraisalResult();
    expect(checkBR02(result)).toBe(true);
    const outcome = validate(result);
    expect(outcome.ok).toBe(true);
  });

  it("UT-BR02-02: 内訳合計と価格が不一致 → BR-02（リトライ可能）", () => {
    const result = exampleAppraisalResult();
    result.appraisedPrice = 1830000; // 内訳合計は 1,820,000
    expect(checkBR02(result)).toBe(false);
    const outcome = validate(result);
    expect(outcome.ok).toBe(false);
    if (!outcome.ok) {
      expect(outcome.code).toBe("BR-02");
      expect(outcome.retryable).toBe(true);
    }
  });

  it("UT-BR02-03: adjustments 空 + base == price → 検証OK", () => {
    const result = exampleAppraisalResult();
    result.adjustments = [];
    result.basePrice = 1820000;
    // appraisedPrice は 1,820,000 のまま
    const outcome = validate(result);
    expect(outcome.ok).toBe(true);
  });

  it("UT-BR02-04: evidencePhotoId が存在しない ID を参照 → unknownEvidencePhotoId", () => {
    const result = exampleAppraisalResult();
    const first = result.adjustments[0];
    if (!first) throw new Error("fixture broken");
    first.evidencePhotoIds = ["ph_ghost_999"];
    const outcome = validate(result);
    expect(outcome.ok).toBe(false);
    if (!outcome.ok) {
      expect(outcome.code).toBe("unknownEvidencePhotoId");
      expect(outcome.retryable).toBe(false);
      expect(outcome.detail).toContain("ph_ghost_999");
    }
  });

  it("repairFinding.evidences の photoId も実在チェック対象", () => {
    const result = exampleAppraisalResult();
    const evidence = result.repairFinding.evidences[0];
    if (!evidence) throw new Error("fixture broken");
    evidence.photoId = "ph_missing_777";
    expect(findUnknownEvidencePhotoIds(result, KNOWN_IDS)).toEqual([
      "ph_missing_777",
    ]);
    const outcome = validate(result);
    expect(outcome.ok).toBe(false);
    if (!outcome.ok) expect(outcome.code).toBe("unknownEvidencePhotoId");
  });
});

describe("BR-01 1万円単位", () => {
  it("UT-BR01-01: 1,813,000 円（万未満端数）→ 丸め検証NG", () => {
    const result = exampleAppraisalResult();
    result.appraisedPrice = 1813000;
    expect(checkBR01(result)).toBe(false);
  });

  it("1,820,000 円 → OK", () => {
    expect(checkBR01(exampleAppraisalResult())).toBe(true);
  });

  it("パイプライン上は schema(multipleOf) が先に検知し aiInvalidResponse となる", () => {
    const result = exampleAppraisalResult();
    // BR-02 は成立させたまま BR-01 のみ破る
    result.appraisedPrice = 1815000;
    const last = result.adjustments[result.adjustments.length - 1];
    if (!last) throw new Error("fixture broken");
    last.amount -= 5000; // -10,000 → -15,000: 合計 +5,000 で 1,815,000
    expect(checkBR02(result)).toBe(true);
    const outcome = validate(result);
    expect(outcome.ok).toBe(false);
    if (!outcome.ok) {
      expect(outcome.code).toBe("schemaViolation");
      expect(outcome.retryable).toBe(false);
    }
  });
});

describe("schema 適合（05 §3.3-1）", () => {
  it("必須フィールド欠落 → schemaViolation", () => {
    const result = exampleAppraisalResult() as Partial<AppraisalResult>;
    delete result.completeness;
    const outcome = validate(result);
    expect(outcome.ok).toBe(false);
    if (!outcome.ok) expect(outcome.code).toBe("schemaViolation");
  });

  it("additionalProperties 拒否", () => {
    const result = exampleAppraisalResult() as AppraisalResult &
      Record<string, unknown>;
    result["extraField"] = "not allowed";
    const outcome = validate(result);
    expect(outcome.ok).toBe(false);
  });
});

describe("相場乖離 → needsReview（05 §3.3-4）", () => {
  it("相場平均の 1.7 倍超 → needsReview 付与", () => {
    expect(isMarketDeviation(1820000, { average: 1000000 })).toBe(true);
    const outcome = validate(exampleAppraisalResult(), { average: 1000000 });
    expect(outcome.ok).toBe(true);
    if (outcome.ok) expect(outcome.needsReview).toBe(true);
  });

  it("相場平均の 0.3 倍未満 → needsReview 付与", () => {
    expect(isMarketDeviation(1820000, { average: 10000000 })).toBe(true);
  });

  it("レンジ内 → needsReview なし", () => {
    const outcome = validate(exampleAppraisalResult());
    expect(outcome.ok).toBe(true);
    if (outcome.ok) expect(outcome.needsReview).toBe(false);
  });

  it("相場 null（相場参考なしモード）→ 乖離判定はスキップ", () => {
    expect(isMarketDeviation(1820000, null)).toBe(false);
  });

  it("境界値: ちょうど 0.3 倍 / 1.7 倍は乖離ではない", () => {
    expect(isMarketDeviation(300000, { average: 1000000 })).toBe(false);
    expect(isMarketDeviation(1700000, { average: 1000000 })).toBe(false);
  });
});
