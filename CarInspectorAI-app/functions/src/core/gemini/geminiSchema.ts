/**
 * JSON Schema (draft 2020-12) → Gemini responseSchema（OpenAPI 3.0 サブセット）変換。
 *
 * Gemini の構造化出力は JSON Schema の全キーワードをサポートしないため、
 * 未対応キーワード（$schema/$id/additionalProperties/multipleOf 等）を除去し、
 * type: ["x","null"] を nullable へ正規化する。
 * 除去された制約（multipleOf = BR-01 等）は CF 側の検証パイプラインで担保する（05 §3.3）。
 */

type JsonObject = Record<string, unknown>;

const UNSUPPORTED_KEYS = new Set([
  "$schema",
  "$id",
  "additionalProperties",
  "multipleOf",
  "default",
  "title",
  "pattern",
  "format",
]);

function isObject(v: unknown): v is JsonObject {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

export function toGeminiSchema(schema: object): JsonObject {
  return convert(schema as JsonObject);
}

function convert(node: JsonObject): JsonObject {
  const out: JsonObject = {};

  // type: ["string","null"] → { type: "string", nullable: true }
  const type = node["type"];
  if (Array.isArray(type)) {
    const nonNull = type.filter((t) => t !== "null");
    out["type"] = nonNull[0] ?? "string";
    if (type.includes("null")) out["nullable"] = true;
  } else if (typeof type === "string") {
    out["type"] = type;
  }

  for (const [key, value] of Object.entries(node)) {
    if (key === "type" || UNSUPPORTED_KEYS.has(key)) continue;
    if (key === "properties" && isObject(value)) {
      const props: JsonObject = {};
      for (const [propName, propSchema] of Object.entries(value)) {
        if (isObject(propSchema)) props[propName] = convert(propSchema);
      }
      out["properties"] = props;
      continue;
    }
    if (key === "items" && isObject(value)) {
      out["items"] = convert(value);
      continue;
    }
    out[key] = value;
  }
  return out;
}
