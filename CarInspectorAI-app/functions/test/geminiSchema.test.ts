/**
 * JSON Schema → Gemini responseSchema 変換のユニットテスト。
 * 除去された制約（multipleOf = BR-01 等）は CF 検証パイプラインで担保される前提。
 */

import { describe, expect, it } from "vitest";
import { toGeminiSchema } from "../src/core/gemini/geminiSchema";
import { loadSchema } from "../src/core/validation/schemaValidator";
import { testResources } from "./helpers/fakes";

describe("toGeminiSchema", () => {
  it("$schema/$id/additionalProperties/multipleOf を除去する", () => {
    const schema = loadSchema(
      testResources.schemasDir,
      "appraisal_result.schema.json",
    );
    const converted = toGeminiSchema(schema) as Record<string, any>;
    expect(converted["$schema"]).toBeUndefined();
    expect(converted["$id"]).toBeUndefined();
    expect(converted["additionalProperties"]).toBeUndefined();
    expect(converted["properties"].appraisedPrice.multipleOf).toBeUndefined();
    // required や description は保持
    expect(converted["required"]).toContain("appraisedPrice");
    expect(converted["type"]).toBe("object");
  });

  it('type: ["object","null"] → nullable へ正規化する', () => {
    const converted = toGeminiSchema({
      type: "object",
      properties: {
        metrics: {
          type: ["object", "null"],
          properties: { value: { type: ["number", "null"] } },
        },
      },
    }) as Record<string, any>;
    const metrics = converted["properties"].metrics;
    expect(metrics.type).toBe("object");
    expect(metrics.nullable).toBe(true);
    expect(metrics.properties.value).toEqual({
      type: "number",
      nullable: true,
    });
  });

  it("ネストした items / properties も再帰変換される", () => {
    const schema = loadSchema(
      testResources.schemasDir,
      "photo_quality.schema.json",
    );
    const converted = toGeminiSchema(schema) as Record<string, any>;
    const issueItem = converted["properties"].issues.items;
    expect(issueItem.additionalProperties).toBeUndefined();
    expect(issueItem.properties.code.enum).toContain("angleMatch");
  });
});
