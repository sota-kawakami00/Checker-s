/**
 * CI ゲート（08 §3）: examples/*.example.json が対応する schema に全件適合すること。
 */

import * as fs from "fs";
import * as path from "path";
import { describe, expect, it } from "vitest";
import { validateAgainstSchema } from "../src/core/validation/schemaValidator";
import { EXAMPLES_DIR, testResources } from "./helpers/fakes";

/** example ファイル名 → 対応 schema ファイル名 */
const EXAMPLE_TO_SCHEMA: Record<string, string> = {
  "appraisal_result.example.json": "appraisal_result.schema.json",
  "photo_quality.example.json": "photo_quality.schema.json",
  "repair_history.example.json": "repair_history.schema.json",
};

describe("schemas × examples（CIゲート 08 §3）", () => {
  const exampleFiles = fs
    .readdirSync(EXAMPLES_DIR)
    .filter((f) => f.endsWith(".example.json"));

  it("examples ディレクトリの全ファイルが対応 schema を持つ", () => {
    for (const file of exampleFiles) {
      expect(
        EXAMPLE_TO_SCHEMA[file],
        `unmapped example file: ${file}`,
      ).toBeDefined();
    }
    expect(exampleFiles.length).toBeGreaterThan(0);
  });

  for (const [exampleFile, schemaFile] of Object.entries(EXAMPLE_TO_SCHEMA)) {
    it(`${exampleFile} は ${schemaFile} に適合する`, () => {
      const data: unknown = JSON.parse(
        fs.readFileSync(path.join(EXAMPLES_DIR, exampleFile), "utf8"),
      );
      const result = validateAgainstSchema(
        testResources.schemasDir,
        schemaFile,
        data,
      );
      expect(result.errors).toEqual([]);
      expect(result.valid).toBe(true);
    });
  }

  it("同梱 schema が全件コンパイル可能（不正データを正しく拒否する）", () => {
    const schemaFiles = fs
      .readdirSync(testResources.schemasDir)
      .filter((f) => f.endsWith(".schema.json"));
    expect(schemaFiles.length).toBe(6);
    for (const schemaFile of schemaFiles) {
      const result = validateAgainstSchema(
        testResources.schemasDir,
        schemaFile,
        { clearly: "invalid" },
      );
      expect(result.valid, `${schemaFile} should reject junk`).toBe(false);
    }
  });
});
