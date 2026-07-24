/**
 * テストフィクスチャ。
 * AI 出力は録画リプレイ方式: examples/ の固定 JSON をモック Gemini が返す（08 §1）。
 */

import * as fs from "fs";
import * as path from "path";
import type {
  AppraisalDocument,
  AppraisalResult,
  MarketPriceResult,
  PhotoQualityResult,
} from "../../src/core/types";
import { EXAMPLES_DIR } from "./fakes";

export function loadExample<T>(fileName: string): T {
  return JSON.parse(
    fs.readFileSync(path.join(EXAMPLES_DIR, fileName), "utf8"),
  ) as T;
}

export function exampleAppraisalResult(): AppraisalResult {
  return loadExample<AppraisalResult>("appraisal_result.example.json");
}

export function examplePhotoQuality(): PhotoQualityResult {
  return loadExample<PhotoQualityResult>("photo_quality.example.json");
}

export const STORE_ID = "store_001";
export const APPRAISAL_ID = "apr_001";

/**
 * examples/appraisal_result.example.json が参照する全 photoId を含む査定ドキュメント。
 * （evidencePhotoIds 実在チェックを通すため）
 */
export function makeAppraisalDoc(): AppraisalDocument {
  const photo = (photoId: string, angle: AppraisalDocument["photos"][number]["angle"]) => ({
    photoId,
    angle,
    storagePath: `stores/${STORE_ID}/appraisals/${APPRAISAL_ID}/photos/${photoId}.jpg`,
  });
  return {
    staffId: "staff_001",
    status: "draft",
    vehicle: {
      makerCode: "toyota",
      modelCode: "prius",
      gradeCode: "S",
      modelYear: 2019,
      mileageKm: 38500,
      colorCode: "070",
      equipments: ["navi", "etc"],
    },
    photos: [
      photo("ph_front_001", "front"),
      photo("ph_left_003", "left"),
      photo("ph_fl_005", "frontLeft"),
      photo("ph_intf_009", "interiorFront"),
      photo("ph_intr_010", "interiorRear"),
      photo("ph_dmg_013", "damage"),
    ],
    repairConfirmedState: "none",
    checkedItems: [],
  };
}

/** example の marketAveragePrice(1,810,000) と整合する相場（needsReview にならない） */
export function normalMarket(): MarketPriceResult {
  return {
    average: 1810000,
    median: 1800000,
    sampleCount: 42,
    range: { p25: 1700000, p75 : 1900000 },
    trend30d: -0.01,
    fetchedAt: "2026-07-24T08:00:00.000Z",
    stale: false,
  };
}
