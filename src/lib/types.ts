export type DeskMode = "hybrid" | "device" | "cloud";

export type NanoAvailability =
  | "unknown"
  | "unsupported"
  | "unavailable"
  | "downloadable"
  | "downloading"
  | "available";

export type ImageAttachment = {
  name: string;
  mimeType: "image/jpeg" | "image/png";
  data: string;
  charLength: number;
};

export type Sensitivity = "personal" | "work" | "public";

export type Brief = {
  title: string;
  summary: string;
  tags: string[];
  actions: string[];
  sensitivity: Sensitivity;
};

export type RouteReason =
  | "short-note"
  | "over-limit"
  | "image-heavy"
  | "forced-device"
  | "forced-cloud"
  | "offline";

export type RunStamp = {
  source: "on_device" | "in_cloud" | "unknown";
  plannedMode: string;
  reason: RouteReason;
  cloudModel: string;
  latencyMs: number;
  charCount: number;
  at: number;
};

export type Note = {
  id: string;
  title: string;
  body: string;
  createdAt: number;
  updatedAt: number;
  brief: Brief | null;
  lastRun: RunStamp | null;
};
