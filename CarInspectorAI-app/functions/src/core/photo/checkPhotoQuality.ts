/**
 * checkPhotoQuality コアロジック（06 §2.2 / 05 §2 二次判定）。
 * Storage 画像 → Gemini（photo_quality.schema.json 構造化出力）
 * → photo ドキュメントの cloudQuality 更新。
 * 二次判定は非同期・撮影をブロックしない前提のため、AI 失敗は internal で返す。
 */

import * as path from "path";
import { CoreError } from "../errors";
import { loadPrompt } from "../prompts";
import { GEMINI_TIMEOUT_MS, withTimeout } from "../timeout";
import type {
  AppraisalRepository,
  AuditLogger,
  Clock,
  GeminiClient,
  ResourcePaths,
  StorageGateway,
} from "../ports";
import type { PhotoAngle, PhotoQualityResult } from "../types";
import {
  loadSchema,
  validateAgainstSchema,
} from "../validation/schemaValidator";

export const PHOTO_QUALITY_PROMPT_ID = "photo_quality";
export const PHOTO_QUALITY_SCHEMA_FILE = "photo_quality.schema.json";

export interface CheckPhotoQualityInput {
  storeId: string;
  appraisalId: string;
  photoId: string;
  angle: PhotoAngle;
}

export interface CheckPhotoQualityDeps {
  appraisals: AppraisalRepository;
  storage: StorageGateway;
  gemini: GeminiClient;
  clock: Clock;
  audit: AuditLogger;
  resources: ResourcePaths;
  geminiTimeoutMs?: number;
}

export async function checkPhotoQuality(
  input: CheckPhotoQualityInput,
  deps: CheckPhotoQualityDeps,
): Promise<PhotoQualityResult> {
  const { storeId, appraisalId, photoId } = input;
  if (!storeId || !appraisalId || !photoId || !input.angle) {
    throw new CoreError(
      "invalid-argument",
      "storeId, appraisalId, photoId and angle are required",
    );
  }
  const startedMs = deps.clock.now().getTime();

  const doc = await deps.appraisals.get(storeId, appraisalId);
  if (doc === null) {
    throw new CoreError(
      "failed-precondition",
      `appraisal document not found: ${appraisalId}`,
    );
  }
  const photo = doc.photos.find((p) => p.photoId === photoId);
  if (photo === undefined) {
    throw new CoreError(
      "failed-precondition",
      `photo not found in appraisal: ${photoId}`,
    );
  }

  const prompt = loadPrompt(deps.resources.promptsDir, PHOTO_QUALITY_PROMPT_ID);
  const schemaFile = path.basename(
    prompt.responseSchema ?? PHOTO_QUALITY_SCHEMA_FILE,
  );
  const responseSchema = loadSchema(deps.resources.schemasDir, schemaFile);

  const image = await deps.storage.download(photo.storagePath);
  const fullPrompt = [
    prompt.body,
    "",
    "## 入力",
    "",
    `photoId: ${photoId}`,
    `angle（期待アングル）: ${input.angle}`,
  ].join("\n");

  const timeoutMs = deps.geminiTimeoutMs ?? GEMINI_TIMEOUT_MS;
  const response = await withTimeout(
    deps.gemini.generateStructured(fullPrompt, [image], responseSchema, {
      model: prompt.model,
      temperature: prompt.temperature,
      maxOutputTokens: prompt.maxOutputTokens,
      timeoutMs,
    }),
    timeoutMs,
    "gemini.generateStructured",
  );

  const schemaResult = validateAgainstSchema(
    deps.resources.schemasDir,
    schemaFile,
    response.json,
  );
  if (!schemaResult.valid) {
    void deps.audit.write({
      kind: "checkPhotoQuality",
      storeId,
      appraisalId,
      promptVersion: prompt.version,
      tokens: response.tokens,
      latencyMs: deps.clock.now().getTime() - startedMs,
      validation: "aiInvalidResponse",
      detail: schemaResult.errors.join("; "),
    });
    throw new CoreError(
      "internal",
      `aiInvalidResponse: ${schemaResult.errors.join("; ")}`,
    );
  }

  // photoId / source はサーバー側が正（モデル出力の取り違えを防ぐ）
  const quality: PhotoQualityResult = {
    ...(response.json as PhotoQualityResult),
    photoId,
    source: "cloud",
  };

  await deps.appraisals.updatePhotoCloudQuality(
    storeId,
    appraisalId,
    photoId,
    quality,
  );

  void deps.audit.write({
    kind: "checkPhotoQuality",
    storeId,
    appraisalId,
    promptVersion: prompt.version,
    tokens: response.tokens,
    latencyMs: deps.clock.now().getTime() - startedMs,
    validation: "ok",
  });
  return quality;
}
