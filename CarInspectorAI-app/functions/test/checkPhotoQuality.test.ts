/**
 * checkPhotoQuality コアのユニットテスト（06 §2.2: photo_quality schema 構造化出力
 * → photo の cloudQuality 更新）。
 */

import { describe, expect, it } from "vitest";
import {
  checkPhotoQuality,
  type CheckPhotoQualityDeps,
} from "../src/core/photo/checkPhotoQuality";
import {
  CapturingAuditLogger,
  FakeClock,
  InMemoryAppraisalRepository,
  InMemoryStorageGateway,
  MockGeminiClient,
  testResources,
} from "./helpers/fakes";
import {
  APPRAISAL_ID,
  STORE_ID,
  examplePhotoQuality,
  makeAppraisalDoc,
} from "./helpers/fixtures";

function makeHarness() {
  const appraisals = new InMemoryAppraisalRepository();
  const storage = new InMemoryStorageGateway();
  const gemini = new MockGeminiClient();
  const audit = new CapturingAuditLogger();
  const doc = makeAppraisalDoc();
  appraisals.seed(STORE_ID, APPRAISAL_ID, doc);
  storage.addFiles(...doc.photos.map((p) => p.storagePath));

  const deps: CheckPhotoQualityDeps = {
    appraisals,
    storage,
    gemini,
    clock: new FakeClock(),
    audit,
    resources: testResources,
  };
  const run = (photoId = "ph_front_001") =>
    checkPhotoQuality(
      { storeId: STORE_ID, appraisalId: APPRAISAL_ID, photoId, angle: "front" },
      deps,
    );
  return { appraisals, storage, gemini, audit, deps, run };
}

describe("checkPhotoQuality", () => {
  it("Gemini 構造化出力（photo_quality schema）で cloudQuality が更新される", async () => {
    const h = makeHarness();
    h.gemini.enqueueJson(examplePhotoQuality());

    const result = await h.run("ph_front_001");

    // photoId / source はサーバー側で正規化される（source は必ず cloud）
    expect(result.photoId).toBe("ph_front_001");
    expect(result.source).toBe("cloud");
    expect(result.passed).toBe(false);
    expect(result.issues[0]?.code).toBe("framing");

    const doc = h.appraisals.docs.get(`${STORE_ID}/${APPRAISAL_ID}`);
    const photo = doc?.photos.find((p) => p.photoId === "ph_front_001");
    expect(photo?.cloudQuality).toEqual(result);
    // 他の photo は変更されない
    const other = doc?.photos.find((p) => p.photoId === "ph_left_003");
    expect(other?.cloudQuality).toBeUndefined();
  });

  it("プロンプトは prompts/photo_quality.md のフロントマターで構成される", async () => {
    const h = makeHarness();
    h.gemini.enqueueJson(examplePhotoQuality());
    await h.run();

    const call = h.gemini.calls[0];
    if (!call) throw new Error("gemini not called");
    expect(call.config.model).toBe("gemini-flash-latest");
    expect(call.config.temperature).toBe(0.1);
    expect(call.config.maxOutputTokens).toBe(1024);
    expect(call.images).toHaveLength(1); // 対象 1 枚のみ
    expect(call.prompt).toContain("angle（期待アングル）: front");
    expect(call.schema).toMatchObject({ title: "PhotoQualityResult" });
  });

  it("schema 不適合の出力 → internal（aiInvalidResponse）", async () => {
    const h = makeHarness();
    h.gemini.enqueueJson({ nonsense: true });

    await expect(h.run()).rejects.toMatchObject({ code: "internal" });
    // cloudQuality は書き込まれない
    const doc = h.appraisals.docs.get(`${STORE_ID}/${APPRAISAL_ID}`);
    const photo = doc?.photos.find((p) => p.photoId === "ph_front_001");
    expect(photo?.cloudQuality).toBeUndefined();
    expect(h.audit.entries[0]?.validation).toBe("aiInvalidResponse");
  });

  it("存在しない photoId → failed-precondition", async () => {
    const h = makeHarness();
    await expect(h.run("ph_unknown")).rejects.toMatchObject({
      code: "failed-precondition",
    });
    expect(h.gemini.calls).toHaveLength(0);
  });

  it("存在しない appraisal → failed-precondition", async () => {
    const h = makeHarness();
    await expect(
      checkPhotoQuality(
        {
          storeId: STORE_ID,
          appraisalId: "apr_missing",
          photoId: "ph_front_001",
          angle: "front",
        },
        h.deps,
      ),
    ).rejects.toMatchObject({ code: "failed-precondition" });
  });

  it("正常時は監査ログに ok が残る", async () => {
    const h = makeHarness();
    h.gemini.enqueueJson(examplePhotoQuality());
    await h.run();
    expect(h.audit.entries[0]?.kind).toBe("checkPhotoQuality");
    expect(h.audit.entries[0]?.validation).toBe("ok");
  });
});
