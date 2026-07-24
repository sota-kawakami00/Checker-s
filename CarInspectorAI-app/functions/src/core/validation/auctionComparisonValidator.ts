/**
 * Phase 2: auction_comparison.schema.json への検証関数（05 §6）。
 * generateAuctionComparison 本体はスタブ（unimplemented）だが、
 * 出力契約の検証だけ先行実装しておく。
 */

import {
  validateAgainstSchema,
  type SchemaValidationResult,
} from "./schemaValidator";

export const AUCTION_COMPARISON_SCHEMA_FILE = "auction_comparison.schema.json";

export function validateAuctionComparison(
  raw: unknown,
  schemasDir: string,
): SchemaValidationResult {
  return validateAgainstSchema(schemasDir, AUCTION_COMPARISON_SCHEMA_FILE, raw);
}
