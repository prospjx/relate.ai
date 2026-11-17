import type { FirebaseApp } from "firebase/app";
import {
  getAI,
  getGenerativeModel,
  GoogleAIBackend,
  InferenceMode,
  Schema,
  type AI,
  type InferenceSource,
} from "firebase/ai";
import type { Brief, ImageAttachment, RunStamp } from "./types.ts";
import type { RoutePlan } from "./route.ts";

const SYSTEM_INSTRUCTION = [
  "You brief private notes for the person who wrote them.",
  "Use only facts that appear in the note or the attached image.",
  "Do not invent people, dates, quotes, amounts, or tasks.",
  "The title is at most 8 words.",
  "The summary is two or three sentences.",
  "Tags are two to five short lowercase labels.",
  "Actions are next steps the note actually asks for. Use an empty list when there are none.",
  "Set sensitivity to personal for private life, work for a job or business, and public when the note is meant to be shared.",
].join(" ");

const briefSchema = Schema.object({
  properties: {
    title: Schema.string({ description: "At most 8 words." }),
    summary: Schema.string({ description: "Two or three sentences from the note." }),
    tags: Schema.array({
      items: Schema.string({ description: "Short lowercase label." }),
    }),
    actions: Schema.array({
      items: Schema.string({ description: "A next step stated or clearly promised in the note." }),
    }),
    sensitivity: Schema.enumString({
      enum: ["personal", "work", "public"],
      description: "personal, work, or public.",
    }),
  },
});

let ai: AI | null = null;

function logic(app: FirebaseApp): AI {
  if (!ai || ai.app !== app) {
    ai = getAI(app, { backend: new GoogleAIBackend() });
  }
  return ai;
}

function modelFor(app: FirebaseApp, plan: RoutePlan, cloudModel: string, image: ImageAttachment | null) {
  const inputs: { type: "text" | "image"; languages?: string[] }[] = [
    { type: "text", languages: ["en"] },
  ];
  if (image) inputs.push({ type: "image" });

  return getGenerativeModel(logic(app), {
    mode: plan.mode,
    inCloudParams: {
      model: cloudModel,
      systemInstruction: SYSTEM_INSTRUCTION,
      generationConfig: {
        maxOutputTokens: 1024,
        responseMimeType: "application/json",
        responseSchema: briefSchema,
      },
    },
    onDeviceParams: {
      createOptions: {
        expectedInputs: inputs,
        expectedOutputs: [{ type: "text", languages: ["en"] }],
        initialPrompts: [
          {
            role: "system",
            content: [{ type: "text", value: SYSTEM_INSTRUCTION }],
          },
        ],
      },
      promptOptions: {
        responseConstraint: briefSchema,
      },
    },
  });
}

function promptFor(body: string, image: ImageAttachment | null): string {
  const source = body.trim();
  if (source && image) {
    return `Brief this note. An image is attached. Mention the image only when it adds a fact the text does not.\n\n---\n${source}\n---`;
  }
  if (source) return `Brief this note.\n\n---\n${source}\n---`;
  return "Brief the attached image. Use only what is visible. If text in the image is unreadable, say so in the summary.";
}

export async function prepareDeviceModel(
  app: FirebaseApp,
  cloudModel: string,
  onProgress: (fraction: number) => void,
): Promise<void> {
  const model = modelFor(
    app,
    { mode: InferenceMode.ONLY_ON_DEVICE, reason: "forced-device" },
    cloudModel,
    null,
  );
  await model.initializeDeviceModel(onProgress);
}

export async function makeBrief(input: {
  app: FirebaseApp;
  body: string;
  image: ImageAttachment | null;
  plan: RoutePlan;
  cloudModel: string;
  onProgress: (fraction: number) => void;
}): Promise<{ brief: Brief; stamp: Omit<RunStamp, "at" | "charCount"> }> {
  const model = modelFor(input.app, input.plan, input.cloudModel, input.image);
  const wantsDevice =
    input.plan.mode === InferenceMode.ONLY_ON_DEVICE ||
    input.plan.mode === InferenceMode.PREFER_ON_DEVICE;
  // Start the on-device model inside the click, before any await, so Chrome
  // still counts this as a user gesture.
  const deviceReady = wantsDevice ? model.initializeDeviceModel(input.onProgress) : null;
  if (deviceReady) {
    const availability = await probeNano();
    const waitForDevice =
      input.plan.mode === InferenceMode.ONLY_ON_DEVICE || availability === "available";
    if (waitForDevice) {
      await deviceReady;
    } else {
      void deviceReady.catch(() => {
        // Nano can keep downloading. This request falls back to the cloud.
      });
    }
  }

  const prompt = promptFor(input.body, input.image);
  const request = input.image
    ? [
        prompt,
        {
          type: "inlineData" as const,
          inlineData: { data: input.image.data, mimeType: input.image.mimeType },
        },
      ]
    : prompt;

  const started = performance.now();
  const result = await model.generateContent(request);
  const latencyMs = Math.round(performance.now() - started);
  const brief = parseBrief(result.response.text());
  return {
    brief,
    stamp: {
      source: normalizeSource(result.response.inferenceSource),
      plannedMode: input.plan.mode,
      reason: input.plan.reason,
      cloudModel: input.cloudModel,
      latencyMs,
    },
  };
}

function normalizeSource(source: InferenceSource | undefined): RunStamp["source"] {
  if (source === "on_device") return "on_device";
  if (source === "in_cloud") return "in_cloud";
  return "unknown";
}

function parseBrief(raw: string): Brief {
  const trimmed = raw.trim().replace(/^```(?:json)?\s*/i, "").replace(/```$/, "").trim();
  let data: unknown;
  try {
    data = JSON.parse(trimmed);
  } catch {
    throw new Error("The model didn't return a brief JSON object.");
  }
  if (!data || typeof data !== "object") {
    throw new Error("The model didn't return a brief JSON object.");
  }
  const record = data as Record<string, unknown>;
  const sensitivity = record.sensitivity;
  if (typeof record.title !== "string" || typeof record.summary !== "string") {
    throw new Error("The brief was missing a title or summary.");
  }
  if (sensitivity !== "personal" && sensitivity !== "work" && sensitivity !== "public") {
    throw new Error("The brief used an unexpected sensitivity label.");
  }
  return {
    title: record.title.trim(),
    summary: record.summary.trim(),
    tags: stringList(record.tags),
    actions: stringList(record.actions),
    sensitivity,
  };
}

function stringList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((item): item is string => typeof item === "string" && item.trim().length > 0).slice(0, 8);
}

export async function probeNano(): Promise<
  "unknown" | "unsupported" | "unavailable" | "downloadable" | "downloading" | "available"
> {
  const languageModel = window.LanguageModel;
  if (!languageModel?.availability) return "unsupported";
  try {
    const value = await languageModel.availability();
    if (
      value === "available" ||
      value === "downloadable" ||
      value === "downloading" ||
      value === "unavailable"
    ) {
      return value;
    }
    return "unknown";
  } catch {
    return "unsupported";
  }
}
