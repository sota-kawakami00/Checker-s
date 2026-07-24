/**
 * プロンプト運用（05 §8）: フロントマター（version/model/temperature/maxOutputTokens）の
 * パースと同梱プロンプトのロード検証。
 */

import { describe, expect, it } from "vitest";
import { loadPrompt, parsePromptMarkdown } from "../src/core/prompts";
import { testResources } from "./helpers/fakes";

describe("loadPrompt（同梱 prompts/）", () => {
  it("appraisal_main のフロントマターを正しくパースする", () => {
    const def = loadPrompt(testResources.promptsDir, "appraisal_main");
    expect(def.id).toBe("appraisal_main");
    expect(def.version).toBe("1.0.0");
    expect(def.model).toBe("gemini-flash-latest");
    expect(def.temperature).toBe(0.2);
    expect(def.maxOutputTokens).toBe(4096);
    expect(def.responseSchema).toBe("schemas/appraisal_result.schema.json");
    expect(def.body).toContain("# メイン査定プロンプト");
    expect(def.body).not.toContain("---\nid:");
  });

  it("photo_quality のフロントマター", () => {
    const def = loadPrompt(testResources.promptsDir, "photo_quality");
    expect(def.temperature).toBe(0.1);
    expect(def.maxOutputTokens).toBe(1024);
    expect(def.responseSchema).toBe("schemas/photo_quality.schema.json");
  });

  it("同梱プロンプト全件がロード可能", () => {
    for (const id of [
      "appraisal_main",
      "photo_quality",
      "repair_history",
      "completeness_check",
      "auction_sheet_ocr",
    ]) {
      const def = loadPrompt(testResources.promptsDir, id);
      expect(def.model.length).toBeGreaterThan(0);
      expect(def.body.length).toBeGreaterThan(0);
    }
  });

  it("存在しないプロンプト → internal エラー", () => {
    expect(() => loadPrompt(testResources.promptsDir, "no_such_prompt")).toThrow(
      /prompt file not found/,
    );
  });
});

describe("parsePromptMarkdown", () => {
  it("フロントマターなし → エラー", () => {
    expect(() => parsePromptMarkdown("# 本文だけ", "x")).toThrow(
      /missing frontmatter/,
    );
  });

  it("必須メタ欠落 → エラー", () => {
    const md = ["---", "id: x", "version: 1.0.0", "---", "body"].join("\n");
    expect(() => parsePromptMarkdown(md, "x")).toThrow(
      /model\/temperature\/maxOutputTokens/,
    );
  });

  it("数値フィールドは number へ変換される", () => {
    const md = [
      "---",
      "id: t",
      "version: 2.1.0",
      "model: gemini-flash-latest",
      "temperature: 0.35",
      "maxOutputTokens: 2048",
      "---",
      "本文",
    ].join("\n");
    const def = parsePromptMarkdown(md, "t");
    expect(def.version).toBe("2.1.0");
    expect(def.temperature).toBe(0.35);
    expect(def.maxOutputTokens).toBe(2048);
    expect(def.body).toBe("本文");
  });
});
