/**
 * runAppraisal コアのユニットテスト（08 §3）。
 * AI 出力は録画リプレイ方式: examples/appraisal_result.example.json を
 * モック Gemini が返す（08 §1）。
 */

import { describe, expect, it } from "vitest";
import {
  runAppraisal,
  type RunAppraisalDeps,
} from "../src/core/appraisal/runAppraisal";
import {
  RateLimiter,
  type RateLimitConfig,
} from "../src/core/appraisal/rateLimiter";
import { CoreError } from "../src/core/errors";
import type { MarketPriceResult } from "../src/core/types";
import {
  CapturingAuditLogger,
  FakeClock,
  InMemoryAppraisalRepository,
  InMemoryQuotaStore,
  InMemoryStorageGateway,
  MockGeminiClient,
  StubMasterRepository,
  testResources,
} from "./helpers/fakes";
import {
  APPRAISAL_ID,
  STORE_ID,
  exampleAppraisalResult,
  makeAppraisalDoc,
  normalMarket,
} from "./helpers/fixtures";

interface HarnessOptions {
  rateLimit?: RateLimitConfig;
  market?: MarketPriceResult | null;
  geminiTimeoutMs?: number;
}

function makeHarness(options: HarnessOptions = {}) {
  const clock = new FakeClock();
  const appraisals = new InMemoryAppraisalRepository();
  const storage = new InMemoryStorageGateway();
  const gemini = new MockGeminiClient();
  const audit = new CapturingAuditLogger();
  const rateLimiter = new RateLimiter(
    new InMemoryQuotaStore(),
    clock,
    options.rateLimit ?? { perMinute: 10, perDay: 200 },
  );

  const doc = makeAppraisalDoc();
  appraisals.seed(STORE_ID, APPRAISAL_ID, doc);
  storage.addFiles(...doc.photos.map((p) => p.storagePath));

  const market = options.market === undefined ? normalMarket() : options.market;
  const deps: RunAppraisalDeps = {
    appraisals,
    storage,
    gemini,
    fetchMarket: () => Promise.resolve(market),
    masters: new StubMasterRepository(),
    rateLimiter,
    clock,
    audit,
    resources: testResources,
    ...(options.geminiTimeoutMs !== undefined
      ? { geminiTimeoutMs: options.geminiTimeoutMs }
      : {}),
  };

  const run = (requestId = "req_001") =>
    runAppraisal({ storeId: STORE_ID, appraisalId: APPRAISAL_ID, requestId }, deps);
  const currentDoc = () => appraisals.docs.get(`${STORE_ID}/${APPRAISAL_ID}`);

  return { clock, appraisals, storage, gemini, audit, deps, run, currentDoc };
}

describe("runAppraisal 正常系（録画リプレイ）", () => {
  it("examples の JSON で検証を通過し aiResult + aiStatus が書き込まれる", async () => {
    const h = makeHarness();
    h.gemini.enqueueJson(exampleAppraisalResult());

    const output = await h.run("req_ok");
    expect(output).toEqual({ accepted: true });

    const doc = h.currentDoc();
    expect(doc?.status).toBe("aiCompleted");
    expect(doc?.aiResult?.appraisedPrice).toBe(1820000);
    expect(doc?.aiResult?.needsReview).toBe(false);
    expect(doc?.aiProposedPrice).toBe(1820000);
    expect(doc?.marketAveragePrice).toBe(1810000);
    expect(doc?.aiStatus?.state).toBe("done");
    expect(doc?.aiStatus?.requestId).toBe("req_ok");
    expect(doc?.aiStatus?.promptVersion).toBe("1.0.0");
    expect(doc?.aiStatus?.finishedAt).toBeDefined();
  });

  it("プロンプトはフロントマター（model/temperature/maxOutputTokens）どおりに構成される", async () => {
    const h = makeHarness();
    h.gemini.enqueueJson(exampleAppraisalResult());
    await h.run();

    expect(h.gemini.calls).toHaveLength(1);
    const call = h.gemini.calls[0];
    if (!call) throw new Error("gemini not called");
    // prompts/appraisal_main.md フロントマター
    expect(call.config.model).toBe("gemini-flash-latest");
    expect(call.config.temperature).toBe(0.2);
    expect(call.config.maxOutputTokens).toBe(4096);
    expect(call.config.timeoutMs).toBe(45_000);
    // 構造化出力: responseSchema 指定
    expect(call.schema).toMatchObject({ title: "AppraisalResult" });
    // 画像は全 photo 分添付
    expect(call.images).toHaveLength(6);
    // 本文 + 入力データ展開
    expect(call.prompt).toContain("あなたは日本の中古車市場に精通したベテラン査定士AI");
    expect(call.prompt).toContain('"makerCode":"toyota"');
    expect(call.prompt).toContain("ph_front_001");
  });

  it("監査ログに requestId / storeId / promptVersion / tokens / latency / 検証結果が残る", async () => {
    const h = makeHarness();
    h.gemini.enqueueJson(exampleAppraisalResult(), { input: 1234, output: 567 });
    await h.run("req_audit");

    expect(h.audit.entries).toHaveLength(1);
    const entry = h.audit.entries[0];
    if (!entry) throw new Error("no audit entry");
    expect(entry.kind).toBe("runAppraisal");
    expect(entry.requestId).toBe("req_audit");
    expect(entry.storeId).toBe(STORE_ID);
    expect(entry.promptVersion).toBe("1.0.0");
    expect(entry.tokens).toEqual({ input: 1234, output: 567 });
    expect(typeof entry.latencyMs).toBe("number");
    expect(entry.validation).toBe("ok");
  });

  it("相場 null（相場参考なしモード）でも査定は続行される", async () => {
    const h = makeHarness({ market: null });
    h.gemini.enqueueJson(exampleAppraisalResult());
    const output = await h.run();
    expect(output).toEqual({ accepted: true });
    const doc = h.currentDoc();
    expect(doc?.aiStatus?.state).toBe("done");
    // 相場なしなので乖離チェックはスキップ（needsReview 付与なし）
    expect(doc?.aiResult?.needsReview).toBe(false);
    const call = h.gemini.calls[0];
    expect(call?.prompt).toContain("### market\nnull");
  });
});

describe("runAppraisal 冪等性（06 §2.1）", () => {
  it("同一 requestId 2 連投で実行は 1 回のみ、2 回目は accepted を返す", async () => {
    const h = makeHarness();
    h.gemini.enqueueJson(exampleAppraisalResult());

    const first = await h.run("req_dup");
    const second = await h.run("req_dup");

    expect(first).toEqual({ accepted: true });
    expect(second).toEqual({ accepted: true, deduplicated: true });
    expect(h.gemini.calls).toHaveLength(1);
  });

  it("失敗した requestId の再送も再実行しない（新 requestId でのみ再試行）", async () => {
    const h = makeHarness();
    h.gemini.enqueueError(new Error("gemini down"));
    await h.run("req_failed");
    expect(h.currentDoc()?.aiStatus?.state).toBe("failed");

    const replay = await h.run("req_failed");
    expect(replay).toEqual({ accepted: true, deduplicated: true });
    expect(h.gemini.calls).toHaveLength(1);

    // 新しい requestId なら再実行される
    h.gemini.enqueueJson(exampleAppraisalResult());
    await h.run("req_retry_new");
    expect(h.gemini.calls).toHaveLength(2);
    expect(h.currentDoc()?.aiStatus?.state).toBe("done");
  });
});

describe("runAppraisal 前提条件（failed-precondition）", () => {
  it("appraisal ドキュメントが存在しない → failed-precondition", async () => {
    const h = makeHarness();
    await expect(
      runAppraisal(
        { storeId: STORE_ID, appraisalId: "apr_missing", requestId: "r1" },
        h.deps,
      ),
    ).rejects.toMatchObject({ code: "failed-precondition" });
    expect(h.gemini.calls).toHaveLength(0);
  });

  it("画像アップロード未完 → failed-precondition（Gemini 呼び出しなし）", async () => {
    const h = makeHarness();
    const doc = makeAppraisalDoc();
    // 1 枚だけ Storage 未アップロード
    const missing = doc.photos[0];
    if (!missing) throw new Error("fixture broken");
    h.storage.files.delete(missing.storagePath);

    await expect(h.run()).rejects.toMatchObject({
      code: "failed-precondition",
    });
    const err = await h.run().catch((e: unknown) => e);
    expect(err).toBeInstanceOf(CoreError);
    expect((err as CoreError).message).toContain(missing.photoId);
    expect(h.gemini.calls).toHaveLength(0);
    // aiStatus は書き込まれない（受理前のエラー）
    expect(h.currentDoc()?.aiStatus).toBeUndefined();
  });

  it("photos が空 → failed-precondition", async () => {
    const h = makeHarness();
    const doc = makeAppraisalDoc();
    doc.photos = [];
    h.appraisals.seed(STORE_ID, APPRAISAL_ID, doc);
    await expect(h.run()).rejects.toMatchObject({
      code: "failed-precondition",
    });
  });

  it("入力不備 → invalid-argument", async () => {
    const h = makeHarness();
    await expect(
      runAppraisal(
        { storeId: STORE_ID, appraisalId: APPRAISAL_ID, requestId: "" },
        h.deps,
      ),
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });
});

describe("runAppraisal レート制限（05 §7）", () => {
  it("分間上限超過 → resource-exhausted", async () => {
    const h = makeHarness({ rateLimit: { perMinute: 2, perDay: 100 } });
    h.gemini.enqueueJson(exampleAppraisalResult());
    h.gemini.enqueueJson(exampleAppraisalResult());

    await h.run("req_1");
    await h.run("req_2");
    await expect(h.run("req_3")).rejects.toMatchObject({
      code: "resource-exhausted",
    });
    expect(h.gemini.calls).toHaveLength(2);
  });

  it("日次上限超過 → resource-exhausted", async () => {
    const h = makeHarness({ rateLimit: { perMinute: 100, perDay: 2 } });
    h.gemini.enqueueJson(exampleAppraisalResult());
    h.gemini.enqueueJson(exampleAppraisalResult());

    await h.run("req_1");
    h.clock.advanceMs(5 * 60 * 1000); // 分バケットは跨ぐが日は同じ
    await h.run("req_2");
    h.clock.advanceMs(5 * 60 * 1000);
    await expect(h.run("req_3")).rejects.toMatchObject({
      code: "resource-exhausted",
    });
  });

  it("冪等リプレイは quota を消費しない", async () => {
    const h = makeHarness({ rateLimit: { perMinute: 1, perDay: 100 } });
    h.gemini.enqueueJson(exampleAppraisalResult());
    await h.run("req_only");
    // 同一 requestId の再送は上限 1 でも accepted
    const replay = await h.run("req_only");
    expect(replay.deduplicated).toBe(true);
  });
});

describe("runAppraisal 検証パイプライン（05 §3.3）", () => {
  it("BR-02 不一致 → 1 回だけ自己修正リトライ → 成功", async () => {
    const h = makeHarness();
    const broken = exampleAppraisalResult();
    broken.appraisedPrice = 1830000; // 内訳合計 1,820,000 と不一致
    h.gemini.enqueueJson(broken);
    h.gemini.enqueueJson(exampleAppraisalResult()); // 修正版

    const output = await h.run("req_br02");
    expect(output).toEqual({ accepted: true });
    expect(h.gemini.calls).toHaveLength(2);

    const retryCall = h.gemini.calls[1];
    expect(retryCall?.prompt).toContain("自己修正指示");
    expect(retryCall?.prompt).toContain("BR-02");

    const doc = h.currentDoc();
    expect(doc?.aiStatus?.state).toBe("done");
    expect(doc?.aiResult?.appraisedPrice).toBe(1820000);
  });

  it("BR-02 不一致がリトライ後も継続 → aiInvalidResponse（リトライは 1 回のみ）", async () => {
    const h = makeHarness();
    const broken = exampleAppraisalResult();
    broken.appraisedPrice = 1830000;
    h.gemini.enqueueJson(broken);
    h.gemini.enqueueJson(broken); // 修正されずまた不一致

    const output = await h.run("req_br02_ng");
    expect(output).toEqual({ accepted: true });
    expect(h.gemini.calls).toHaveLength(2); // 3 回目は呼ばれない

    const doc = h.currentDoc();
    expect(doc?.aiResult).toBeUndefined();
    expect(doc?.aiStatus?.state).toBe("failed");
    expect(doc?.aiStatus?.reason).toBe("aiInvalidResponse");
    const entry = h.audit.entries[0];
    expect(entry?.validation).toBe("aiInvalidResponse");
    expect(entry?.detail).toContain("BR-02");
  });

  it("BR-01 違反（万未満端数）→ aiInvalidResponse（自己修正リトライなし）", async () => {
    const h = makeHarness();
    const broken = exampleAppraisalResult();
    broken.appraisedPrice = 1815000;
    const last = broken.adjustments[broken.adjustments.length - 1];
    if (!last) throw new Error("fixture broken");
    last.amount -= 5000; // BR-02 は成立させ BR-01 のみ破る
    h.gemini.enqueueJson(broken);

    const output = await h.run("req_br01");
    expect(output).toEqual({ accepted: true });
    expect(h.gemini.calls).toHaveLength(1); // BR-02 以外はリトライしない

    const doc = h.currentDoc();
    expect(doc?.aiResult).toBeUndefined();
    expect(doc?.aiStatus?.state).toBe("failed");
    expect(doc?.aiStatus?.reason).toBe("aiInvalidResponse");
  });

  it("evidencePhotoId が実在しない → aiInvalidResponse", async () => {
    const h = makeHarness();
    const broken = exampleAppraisalResult();
    const first = broken.adjustments[0];
    if (!first) throw new Error("fixture broken");
    first.evidencePhotoIds = ["ph_ghost_999"];
    h.gemini.enqueueJson(broken);

    await h.run("req_evidence");
    const doc = h.currentDoc();
    expect(doc?.aiStatus?.state).toBe("failed");
    expect(doc?.aiStatus?.reason).toBe("aiInvalidResponse");
    expect(h.audit.entries[0]?.detail).toContain("ph_ghost_999");
    expect(h.gemini.calls).toHaveLength(1);
  });

  it("相場平均の 1.7 倍超 → needsReview=true を付与して書き込む", async () => {
    const market = { ...normalMarket(), average: 1000000 }; // 1.82 倍
    const h = makeHarness({ market });
    h.gemini.enqueueJson(exampleAppraisalResult());

    await h.run("req_review");
    const doc = h.currentDoc();
    expect(doc?.aiStatus?.state).toBe("done");
    expect(doc?.aiResult?.needsReview).toBe(true);
    expect(doc?.aiResult?.appraisedPrice).toBe(1820000);
  });

  it("schema 不適合 → aiInvalidResponse（リトライなし）", async () => {
    const h = makeHarness();
    h.gemini.enqueueJson({ totally: "wrong" });
    await h.run("req_schema");
    expect(h.gemini.calls).toHaveLength(1);
    const doc = h.currentDoc();
    expect(doc?.aiStatus?.state).toBe("failed");
    expect(doc?.aiStatus?.reason).toBe("aiInvalidResponse");
  });
});

describe("runAppraisal 失敗時挙動（05 §3.4）", () => {
  it("Gemini タイムアウト（45s 相当）→ aiStatus failed / reason=aiTimeout", async () => {
    const h = makeHarness({ geminiTimeoutMs: 30 });
    h.gemini.enqueueNever();

    const output = await h.run("req_timeout");
    expect(output).toEqual({ accepted: true });
    const doc = h.currentDoc();
    expect(doc?.aiStatus?.state).toBe("failed");
    expect(doc?.aiStatus?.reason).toBe("aiTimeout");
  });

  it("Gemini 障害 → aiStatus failed / reason=aiUnavailable", async () => {
    const h = makeHarness();
    h.gemini.enqueueError(new Error("503 service unavailable"));

    const output = await h.run("req_down");
    expect(output).toEqual({ accepted: true });
    const doc = h.currentDoc();
    expect(doc?.aiStatus?.state).toBe("failed");
    expect(doc?.aiStatus?.reason).toBe("aiUnavailable");
    expect(h.audit.entries[0]?.validation).toBe("aiUnavailable");
  });
});
