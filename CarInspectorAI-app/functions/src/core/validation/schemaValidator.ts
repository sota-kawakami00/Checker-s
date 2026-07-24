/**
 * ajv による JSON Schema（draft 2020-12）検証（05 §3.3-1 / 08 §3）。
 * schemas/*.schema.json は docs/standerd/schemas/ から同梱コピーしたもの。
 */

import * as fs from "fs";
import * as path from "path";
import Ajv2020 from "ajv/dist/2020";
import type { ValidateFunction } from "ajv/dist/2020";
import addFormats from "ajv-formats";

const ajv = new Ajv2020({ allErrors: true, strict: false });
addFormats(ajv);

const validatorCache = new Map<string, ValidateFunction>();

export interface SchemaValidationResult {
  valid: boolean;
  /** ajv エラーの人間可読サマリ（監査ログ・aiStatus.reason 用） */
  errors: string[];
}

export function loadSchema(schemasDir: string, fileName: string): object {
  const filePath = path.join(schemasDir, fileName);
  return JSON.parse(fs.readFileSync(filePath, "utf8")) as object;
}

function compileFor(schemasDir: string, fileName: string): ValidateFunction {
  const filePath = path.join(schemasDir, fileName);
  const cached = validatorCache.get(filePath);
  if (cached) return cached;
  const schema = loadSchema(schemasDir, fileName);
  const validate = ajv.compile(schema);
  validatorCache.set(filePath, validate);
  return validate;
}

export function validateAgainstSchema(
  schemasDir: string,
  schemaFileName: string,
  data: unknown,
): SchemaValidationResult {
  const validate = compileFor(schemasDir, schemaFileName);
  const valid = validate(data) as boolean;
  if (valid) return { valid: true, errors: [] };
  const errors = (validate.errors ?? []).map(
    (e) => `${e.instancePath || "/"} ${e.message ?? "invalid"}`,
  );
  return { valid: false, errors };
}
