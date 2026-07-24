/**
 * generateAuctionComparison（06 §2.4 / 05 §6）。
 * Phase 2 機能のため v1 ではスタブ（unimplemented）。
 * 出力契約（auction_comparison.schema.json）への検証関数は
 * validation/auctionComparisonValidator.ts に先行実装済み。
 */

import { CoreError } from "../errors";

export interface GenerateAuctionComparisonInput {
  storeId: string;
  appraisalId: string;
  auctionSheetPhotoId: string;
}

export function generateAuctionComparison(
  _input: GenerateAuctionComparisonInput,
): never {
  throw new CoreError(
    "unimplemented",
    "generateAuctionComparison is a Phase 2 feature and is not implemented in v1",
  );
}
