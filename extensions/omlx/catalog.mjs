// Shared oMLX catalog mapping. Imported by pi-start.sh to seed models.json at
// container start, and by index.ts to refresh the catalog while Pi is running.

const CHAT_MODEL_TYPES = ["llm", "vlm", undefined, null];

// Mirrors Pi's built-in llama.cpp provider, which targets the same class of
// local OpenAI-compatible server. oMLX accepts max_tokens (ChatCompletionRequest
// aliases it with max_completion_tokens) and stream_options.include_usage.
const LOCAL_SERVER_COMPAT = {
  supportsStore: false,
  supportsDeveloperRole: false,
  supportsReasoningEffort: false,
  supportsUsageInStreaming: true,
  supportsStrictMode: false,
  maxTokensField: "max_tokens",
};

// oMLX's own server default. Guessing high would let Pi overrun the prompt size
// oMLX accepts; guessing low only makes Pi compact sooner than it needs to.
const DEFAULT_CONTEXT_WINDOW = 32768;
const DEFAULT_MAX_TOKENS = 16384;

export const STATUS_PATH = "/models/status";

const positive = (value) => (typeof value === "number" && value > 0 ? value : undefined);

// oMLX publishes profile variants as their own IDs (e.g. qwen3-8b:thinking);
// mirrors the detection in oMLX's own omlx/integrations/pi.py.
const isReasoning = (id) => /\b(thinking|o1|o3|r1)\b/.test(id.toLowerCase());

export function chatModels(payload) {
  const entries = payload?.models;
  if (!Array.isArray(entries)) {
    throw new Error("unexpected /v1/models/status payload; expected a models array");
  }
  // Embedding, reranker and audio models share the listing but cannot back a
  // coding agent. Absent model_type means an older oMLX that only served LLMs.
  const chat = entries.filter((model) => CHAT_MODEL_TYPES.includes(model.model_type));
  if (chat.length === 0) {
    throw new Error(
      "oMLX serves no llm or vlm models\n" +
        "hint: download a chat model in the oMLX admin panel",
    );
  }
  return chat;
}

// Entries are complete rather than minimal because Pi fills defaults only for
// models.json definitions; extension-supplied models are spread verbatim.
export function toProviderModels(chat) {
  return chat.map((model) => {
    const contextWindow = positive(model.max_context_window) ?? DEFAULT_CONTEXT_WINDOW;
    return {
      id: model.id,
      name: model.id,
      reasoning: isReasoning(model.id),
      input: model.model_type === "vlm" ? ["text", "image"] : ["text"],
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
      contextWindow,
      // An output budget cannot exceed the window it is drawn from, and a small
      // model plus the default would do exactly that.
      maxTokens: Math.min(positive(model.max_tokens) ?? DEFAULT_MAX_TOKENS, contextWindow),
      compat: { ...LOCAL_SERVER_COMPAT },
    };
  });
}

export function selectModel(chat, pin) {
  if (!pin) {
    return (chat.find((model) => model.loaded) ?? chat[0]).id;
  }
  if (!chat.some((model) => model.id === pin)) {
    throw new Error(
      `OMLX_MODEL "${pin}" is not served by oMLX as a chat model\n` +
        `available: ${chat.map((model) => model.id).join(", ")}\n` +
        "hint: unset OMLX_MODEL in spec.yaml to track whatever oMLX has loaded",
    );
  }
  return pin;
}

export async function fetchChatModels(baseUrl, signal) {
  const response = await fetch(`${baseUrl}${STATUS_PATH}`, { signal });
  if (!response.ok) {
    throw new Error(`oMLX returned HTTP ${response.status} for ${STATUS_PATH}`);
  }
  return chatModels(await response.json());
}
