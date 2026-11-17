import { InferenceMode } from "firebase/ai";
import type { DeskMode, ImageAttachment, RouteReason } from "./types.ts";

export const DEFAULT_ON_DEVICE_CHAR_LIMIT = 1800;
export const DEFAULT_CLOUD_MODEL = "gemini-3.5-flash-lite";
const HEAVY_IMAGE_CHARS = 1_400_000;

export type RoutePlan = {
  mode: InferenceMode;
  reason: RouteReason;
};

export function sanitizeLimit(value: number): number {
  if (!Number.isFinite(value) || value < 280 || value > 12_000) {
    return DEFAULT_ON_DEVICE_CHAR_LIMIT;
  }
  return Math.round(value);
}

export function sanitizeModel(value: string): string {
  const model = value.trim();
  if (!/^gemini-[a-z0-9.-]+$/i.test(model)) return DEFAULT_CLOUD_MODEL;
  return model;
}

export function planRoute(input: {
  deskMode: DeskMode;
  charCount: number;
  limit: number;
  online: boolean;
  image: ImageAttachment | null;
}): RoutePlan {
  if (!input.online) {
    return { mode: InferenceMode.ONLY_ON_DEVICE, reason: "offline" };
  }
  if (input.deskMode === "device") {
    return { mode: InferenceMode.ONLY_ON_DEVICE, reason: "forced-device" };
  }
  if (input.deskMode === "cloud") {
    return { mode: InferenceMode.ONLY_IN_CLOUD, reason: "forced-cloud" };
  }
  if (input.charCount > input.limit) {
    return { mode: InferenceMode.ONLY_IN_CLOUD, reason: "over-limit" };
  }
  if (input.image && input.image.charLength > HEAVY_IMAGE_CHARS) {
    return { mode: InferenceMode.ONLY_IN_CLOUD, reason: "image-heavy" };
  }
  return { mode: InferenceMode.PREFER_ON_DEVICE, reason: "short-note" };
}

export function prefersDevice(mode: InferenceMode): boolean {
  return mode === InferenceMode.ONLY_ON_DEVICE || mode === InferenceMode.PREFER_ON_DEVICE;
}

export function explainPlan(
  plan: RoutePlan,
  charCount: number,
  limit: number,
  cloudModel: string,
): string {
  const count = charCount.toLocaleString("en-US");
  const cap = limit.toLocaleString("en-US");
  switch (plan.reason) {
    case "short-note":
      return `This note is ${count} characters, under the ${cap} character on-device limit from Remote Config. Hearth asks Firebase AI Logic to prefer Gemini Nano, and to use the cloud only if Nano isn't ready.`;
    case "over-limit":
      return `This note is ${count} characters, past the ${cap} character on-device limit from Remote Config. Hearth sends the brief to ${cloudModel}. Gemini Nano's context is about 9,216 tokens, so long pages are the cloud's job.`;
    case "image-heavy":
      return `The attached image is large for Gemini Nano's context window, so Hearth sends this brief to ${cloudModel}.`;
    case "forced-device":
      return "This brief is locked to the device. The note is not sent to the cloud. If Gemini Nano isn't available, the request stops instead of falling back.";
    case "forced-cloud":
      return `This brief is set to run in the cloud on ${cloudModel}.`;
    case "offline":
      return "This browser is offline, so the cloud is out of reach. Hearth will try Gemini Nano on this device.";
  }
}

export function explainSource(
  source: "on_device" | "in_cloud" | "unknown",
  plannedMode: string,
): string {
  if (source === "on_device") return "Firebase AI Logic ran this brief on this device with Gemini Nano.";
  if (source === "in_cloud" && plannedMode === InferenceMode.PREFER_ON_DEVICE) {
    return "Gemini Nano wasn't ready, so Firebase AI Logic used the cloud fallback.";
  }
  if (source === "in_cloud") return "Firebase AI Logic ran this brief in the cloud.";
  return "The SDK didn't report where this brief ran.";
}
