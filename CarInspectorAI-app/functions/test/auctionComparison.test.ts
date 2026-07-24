/**
 * generateAuctionComparison（Phase 2 スタブ）と
 * auction_comparison.schema.json 検証関数のテスト（05 §6）。
 */

import { describe, expect, it } from "vitest";
import { generateAuctionComparison } from "../src/core/auction/generateAuctionComparison";
import { validateAuctionComparison } from "../src/core/validation/auctionComparisonValidator";
import { testResources } from "./helpers/fakes";

describe("generateAuctionComparison（Phase 2）", () => {
  it("v1 では unimplemented を throw する", () => {
    expect(() =>
      generateAuctionComparison({
        storeId: "store_001",
        appraisalId: "apr_001",
        auctionSheetPhotoId: "ph_sheet_001",
      }),
    ).toThrowError(
      expect.objectContaining({ code: "unimplemented" }),
    );
  });
});

describe("validateAuctionComparison（出力契約の先行検証）", () => {
  const validPayload = {
    sheet: {
      overallGrade: "4",
      exteriorGrade: "B",
      interiorGrade: "B",
      marks: [
        { partCode: "rightFrontFender", symbol: "A2", unreadable: false },
        { partCode: "rearBumper", symbol: null, unreadable: true },
      ],
    },
    diffs: [
      {
        partCode: "rightFrontFender",
        kind: "worse",
        sheetSymbol: "A2",
        currentFinding: "A3",
        message: "右フェンダー: 出品票A2 → 今回A3（傷が増えています）。現車をご確認ください。",
      },
    ],
    summary: "外装は出品票時点より軽微な悪化が1件あります。",
  };

  it("正例が schema に適合する", () => {
    const result = validateAuctionComparison(
      validPayload,
      testResources.schemasDir,
    );
    expect(result.errors).toEqual([]);
    expect(result.valid).toBe(true);
  });

  it("不正な partCode / kind を拒否する", () => {
    const broken = structuredClone(validPayload) as Record<string, any>;
    broken["sheet"].marks[0].partCode = "unknownPart";
    expect(
      validateAuctionComparison(broken, testResources.schemasDir).valid,
    ).toBe(false);

    const brokenKind = structuredClone(validPayload) as Record<string, any>;
    brokenKind["diffs"][0].kind = "different";
    expect(
      validateAuctionComparison(brokenKind, testResources.schemasDir).valid,
    ).toBe(false);
  });

  it("必須フィールド欠落を拒否する", () => {
    const { summary: _summary, ...noSummary } = validPayload;
    expect(
      validateAuctionComparison(noSummary, testResources.schemasDir).valid,
    ).toBe(false);
  });
});
