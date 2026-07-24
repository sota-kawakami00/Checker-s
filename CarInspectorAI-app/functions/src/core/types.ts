/**
 * ドメイン型定義。
 * schemas/*.schema.json が唯一の契約であり、本ファイルはその TypeScript 写像。
 * （AGENTS.md「Schema is Law」— フィールドの追加・削除・型変更は破壊的変更）
 */

// ---------------------------------------------------------------------------
// appraisal_result.schema.json
// ---------------------------------------------------------------------------

export interface AdjustmentItem {
  code: string;
  label: string;
  /** 円。加点は正、減点は負 */
  amount: number;
  rationale: string;
  evidencePhotoIds: string[];
}

export type RepairEvidenceType =
  | "toolMarks"
  | "colorMismatch"
  | "panelGap"
  | "weldSpots"
  | "sealant";

export interface NormalizedRegion {
  x: number;
  y: number;
  w: number;
  h: number;
}

export interface RepairEvidence {
  photoId: string;
  type: RepairEvidenceType;
  region: NormalizedRegion;
  note: string;
}

export interface RepairFinding {
  probability: number;
  evidences: RepairEvidence[];
}

export interface UncheckedItem {
  code: string;
  label: string;
  hint: string;
}

export interface Completeness {
  score: number;
  uncheckedItems: UncheckedItem[];
}

export interface AppraisalResult {
  appraisedPrice: number;
  tradeInReference: number;
  basePrice: number;
  adjustments: AdjustmentItem[];
  marketAveragePrice: number;
  confidence: number;
  /** CF付与: 相場乖離大等（05 §3.3-4）。Gemini出力時は省略可 */
  needsReview?: boolean;
  repairFinding: RepairFinding;
  completeness: Completeness;
}

// ---------------------------------------------------------------------------
// photo_quality.schema.json
// ---------------------------------------------------------------------------

export type PhotoQualityIssueCode =
  | "focus"
  | "brightness"
  | "framing"
  | "tilt"
  | "angleMatch"
  | "reflection"
  | "obstruction"
  | "coverage"
  | "unjudgeable";

export interface PhotoQualityIssue {
  code: PhotoQualityIssueCode;
  message: string;
  suggestion: string;
  blocking: boolean;
}

export interface PhotoQualityResult {
  photoId: string;
  source: "onDevice" | "cloud";
  passed: boolean;
  issues: PhotoQualityIssue[];
  metrics?: {
    laplacianVariance?: number | null;
    brightnessMedian?: number | null;
    tiltDegrees?: number | null;
    vehicleBBox?: NormalizedRegion | null;
  } | null;
}

// ---------------------------------------------------------------------------
// fetchMarketPrice（06 §2.3 / appraisal_request.schema.json market）
// ---------------------------------------------------------------------------

export interface MarketPriceRange {
  p25: number;
  p75: number;
}

/** fetchMarketPrice の正規化結果（プロバイダ差異はここで吸収済み） */
export interface MarketPriceResult {
  average: number;
  median: number;
  sampleCount: number;
  range: MarketPriceRange;
  /** 30日変化率。-0.02 = 2%下落 */
  trend30d: number;
  /** ISO 8601 date-time */
  fetchedAt: string;
  /** true = プロバイダ障害時に期限切れキャッシュで応答した */
  stale: boolean;
}

export interface MarketPriceQuery {
  makerCode: string;
  modelCode: string;
  gradeCode?: string | null;
  modelYear: number | null;
  mileageKm: number;
  repairHistory: boolean;
}

// ---------------------------------------------------------------------------
// Firestore ドキュメント（schemas/firestore_collections.md）
// ---------------------------------------------------------------------------

export type PhotoAngle =
  | "front"
  | "rear"
  | "left"
  | "right"
  | "frontLeft"
  | "frontRight"
  | "rearLeft"
  | "rearRight"
  | "interiorFront"
  | "interiorRear"
  | "meter"
  | "engineRoom"
  | "damage";

export interface AppraisalPhotoMeta {
  photoId: string;
  angle: PhotoAngle;
  damageTag?: string | null;
  memo?: string | null;
  storagePath: string;
  qualityPassed?: boolean;
  cloudQuality?: PhotoQualityResult | null;
}

export interface AppraisalVehicle {
  vinMasked?: string | null;
  makerCode: string;
  modelCode: string;
  gradeCode?: string | null;
  modelYear?: number | null;
  firstRegistrationYM?: string | null;
  mileageKm: number;
  colorCode: string;
  inspectionExpiry?: string | null;
  equipments?: string[];
}

export type AiState = "running" | "done" | "failed";

export interface AiStatus {
  state: AiState;
  reason?: string;
  requestId: string;
  promptVersion: string;
  startedAt: string;
  finishedAt?: string;
}

export interface AppraisalDocument {
  staffId: string;
  status:
    | "draft"
    | "aiRunning"
    | "aiCompleted"
    | "confirmed"
    | "won"
    | "lost"
    | "expired";
  vehicle: AppraisalVehicle;
  photos: AppraisalPhotoMeta[];
  aiStatus?: AiStatus | null;
  aiResult?: AppraisalResult | null;
  aiProposedPrice?: number | null;
  marketAveragePrice?: number | null;
  repairConfirmedState?: "none" | "confirmedYes" | "confirmedNo" | "unknown";
  checkedItems?: string[];
}

export interface CheckItemMaster {
  code: string;
  label: string;
  weight: number;
  hint?: string;
}

export interface StoreSettings {
  targetMarginRate?: number | null;
  promptVariant?: string | null;
}

// ---------------------------------------------------------------------------
// marketCache/{cacheKey}（firestore_collections.md）
// ---------------------------------------------------------------------------

export interface MarketCacheEntry {
  key: string;
  payload: Omit<MarketPriceResult, "stale">;
  /** ISO 8601。TTL 24h は CF 側で判定 */
  fetchedAt: string;
}

// ---------------------------------------------------------------------------
// 監査ログ（05 §3.4 / §8）
// ---------------------------------------------------------------------------

export interface AuditLogEntry {
  kind: "runAppraisal" | "checkPhotoQuality" | "fetchMarketPrice";
  requestId?: string;
  storeId: string;
  appraisalId?: string;
  promptVersion?: string;
  tokens?: { input: number; output: number };
  latencyMs: number;
  /** ok / 失敗理由コード */
  validation: string;
  detail?: string;
}
