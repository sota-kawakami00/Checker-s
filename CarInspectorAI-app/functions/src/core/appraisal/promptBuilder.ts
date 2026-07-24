/**
 * prompts/appraisal_main.md 本文 + 入力データ（05 §3.1）から
 * Gemini へ渡す最終プロンプト文字列を構築する。
 * プロンプト本文は prompts/ が正であり、ここでは改変しない（AGENTS.md Docs First）。
 */

import type {
  AppraisalVehicle,
  AppraisalPhotoMeta,
  CheckItemMaster,
  MarketPriceResult,
  StoreSettings,
} from "../types";
import type { AppraisalResult } from "../types";

export interface AppraisalPromptInput {
  vehicle: AppraisalVehicle;
  photos: AppraisalPhotoMeta[];
  market: MarketPriceResult | null;
  store: StoreSettings | null;
  checkItems: CheckItemMaster[];
  repairConfirmed: boolean | null;
}

/** プロンプトへ展開する photos メタ（storagePath 等の内部情報は渡さない） */
function photoMetaForPrompt(photos: AppraisalPhotoMeta[]): object[] {
  return photos.map((p) => ({
    photoId: p.photoId,
    angle: p.angle,
    damageTag: p.damageTag ?? null,
    memo: p.memo ?? null,
  }));
}

export function buildAppraisalPrompt(
  promptBody: string,
  input: AppraisalPromptInput,
): string {
  const sections = [
    promptBody,
    "",
    "## 入力データ",
    "",
    "### vehicle",
    JSON.stringify(input.vehicle),
    "",
    "### photos（画像は添付順に対応。photoId を厳守）",
    JSON.stringify(photoMetaForPrompt(input.photos)),
    "",
    "### market",
    JSON.stringify(input.market),
    "",
    "### store",
    JSON.stringify(input.store),
    "",
    "### checkItems",
    JSON.stringify(input.checkItems),
    "",
    "### repairConfirmed",
    JSON.stringify(input.repairConfirmed),
  ];
  return sections.join("\n");
}

/**
 * BR-02 不一致時の自己修正リトライ用プロンプト（05 §3.3-2）。
 * 前回出力と不一致内容を提示し、内訳整合の修正のみを求める。
 */
export function buildSelfCorrectionPrompt(
  originalPrompt: string,
  previousOutput: AppraisalResult,
  detail: string,
): string {
  return [
    originalPrompt,
    "",
    "## 自己修正指示（再出力）",
    "",
    "前回のあなたの出力は次の検証に失敗しました:",
    detail,
    "",
    "前回出力:",
    JSON.stringify(previousOutput),
    "",
    "`basePrice + Σ adjustments.amount = appraisedPrice` が厳密に成立し、",
    "`appraisedPrice` が 10,000 円単位になるよう内訳を修正した完全な JSON を再出力してください。",
    "出力は responseSchema 準拠の JSON のみ。他の内容は一切変更しないでください。",
  ].join("\n");
}
