/**
 * GeminiClient の本番実装（fetch ベースの Gemini REST API 呼び出し）。
 *
 * 方針（要件 6）: @google/genai SDK は使用せず、REST API を直接叩く。
 * API キーは process.env.GEMINI_API_KEY。
 * 本番では Secret Manager（firebase-functions/params の defineSecret("GEMINI_API_KEY")）で
 * 注入する想定。コードへのハードコード禁止（AGENTS.md §秘密情報）。
 */

import type {
  GeminiClient,
  GeminiGenerationConfig,
  GeminiStructuredResponse,
  ImageContent,
} from "../core/ports";
import { toGeminiSchema } from "../core/gemini/geminiSchema";
import { CoreError } from "../core/errors";

const BASE_URL = "https://generativelanguage.googleapis.com/v1beta";

interface GenerateContentResponse {
  candidates?: Array<{
    content?: { parts?: Array<{ text?: string }> };
    finishReason?: string;
  }>;
  usageMetadata?: {
    promptTokenCount?: number;
    candidatesTokenCount?: number;
  };
}

export class GeminiRestClient implements GeminiClient {
  constructor(
    private readonly apiKey: string | undefined = process.env.GEMINI_API_KEY,
    private readonly fetchImpl: typeof fetch = fetch,
  ) {}

  async generateStructured(
    prompt: string,
    images: ImageContent[],
    schema: object,
    config: GeminiGenerationConfig,
  ): Promise<GeminiStructuredResponse> {
    if (!this.apiKey) {
      throw new CoreError(
        "internal",
        "GEMINI_API_KEY is not configured (expected via Secret Manager)",
      );
    }

    const parts: unknown[] = [{ text: prompt }];
    for (const image of images) {
      parts.push({
        inlineData: { mimeType: image.mimeType, data: image.base64Data },
      });
    }

    const body = {
      contents: [{ role: "user", parts }],
      generationConfig: {
        temperature: config.temperature,
        maxOutputTokens: config.maxOutputTokens,
        responseMimeType: "application/json",
        responseSchema: toGeminiSchema(schema),
      },
    };

    const controller = new AbortController();
    const timeoutMs = config.timeoutMs ?? 45_000;
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    let response: Response;
    try {
      response = await this.fetchImpl(
        `${BASE_URL}/models/${encodeURIComponent(config.model)}:generateContent`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "x-goog-api-key": this.apiKey,
          },
          body: JSON.stringify(body),
          signal: controller.signal,
        },
      );
    } finally {
      clearTimeout(timer);
    }

    if (!response.ok) {
      const text = await response.text().catch(() => "");
      throw new CoreError(
        "internal",
        `Gemini API error: HTTP ${response.status} ${text.slice(0, 500)}`,
      );
    }

    const payload = (await response.json()) as GenerateContentResponse;
    const text = payload.candidates?.[0]?.content?.parts?.[0]?.text;
    if (typeof text !== "string" || text.length === 0) {
      throw new CoreError("internal", "Gemini API returned no content");
    }

    let json: unknown;
    try {
      json = JSON.parse(text);
    } catch {
      throw new CoreError(
        "internal",
        "Gemini API returned non-JSON content despite responseSchema",
      );
    }

    return {
      json,
      tokens: {
        input: payload.usageMetadata?.promptTokenCount ?? 0,
        output: payload.usageMetadata?.candidatesTokenCount ?? 0,
      },
    };
  }
}
