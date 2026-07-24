/**
 * prompts/*.md のロードとフロントマターのパース（05 §8）。
 * フロントマター: version / model / temperature / maxOutputTokens / responseSchema。
 * バージョンは監査ログに記録される。
 */

import * as fs from "fs";
import * as path from "path";
import { CoreError } from "./errors";

export interface PromptDefinition {
  id: string;
  version: string;
  model: string;
  temperature: number;
  maxOutputTokens: number;
  /** 例: "schemas/appraisal_result.schema.json" */
  responseSchema: string | null;
  /** フロントマターを除いた本文 */
  body: string;
}

const FRONTMATTER_DELIMITER = "---";

/** `key: value` 行の素朴な YAML サブセットをパースする */
function parseFrontmatter(block: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const rawLine of block.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (line === "" || line.startsWith("#")) continue;
    const idx = line.indexOf(":");
    if (idx <= 0) continue;
    const key = line.slice(0, idx).trim();
    const value = line.slice(idx + 1).trim();
    out[key] = value;
  }
  return out;
}

export function parsePromptMarkdown(
  markdown: string,
  fallbackId: string,
): PromptDefinition {
  const lines = markdown.split(/\r?\n/);
  if (lines[0]?.trim() !== FRONTMATTER_DELIMITER) {
    throw new CoreError(
      "internal",
      `prompt "${fallbackId}" is missing frontmatter`,
    );
  }
  const endIdx = lines.findIndex(
    (l, i) => i > 0 && l.trim() === FRONTMATTER_DELIMITER,
  );
  if (endIdx < 0) {
    throw new CoreError(
      "internal",
      `prompt "${fallbackId}" has an unterminated frontmatter block`,
    );
  }
  const meta = parseFrontmatter(lines.slice(1, endIdx).join("\n"));
  const body = lines.slice(endIdx + 1).join("\n").trim();

  const temperature = Number(meta["temperature"]);
  const maxOutputTokens = Number(meta["maxOutputTokens"]);
  const model = meta["model"];
  if (!model || Number.isNaN(temperature) || Number.isNaN(maxOutputTokens)) {
    throw new CoreError(
      "internal",
      `prompt "${fallbackId}" frontmatter must define model/temperature/maxOutputTokens`,
    );
  }
  return {
    id: meta["id"] ?? fallbackId,
    version: meta["version"] ?? "0.0.0",
    model,
    temperature,
    maxOutputTokens,
    responseSchema: meta["responseSchema"] ?? null,
    body,
  };
}

const promptCache = new Map<string, PromptDefinition>();

/** prompts/{id}.md をロードする（プロセス内キャッシュあり） */
export function loadPrompt(promptsDir: string, id: string): PromptDefinition {
  const filePath = path.join(promptsDir, `${id}.md`);
  const cached = promptCache.get(filePath);
  if (cached) return cached;
  let markdown: string;
  try {
    markdown = fs.readFileSync(filePath, "utf8");
  } catch {
    throw new CoreError("internal", `prompt file not found: ${filePath}`);
  }
  const def = parsePromptMarkdown(markdown, id);
  promptCache.set(filePath, def);
  return def;
}
