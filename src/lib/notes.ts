import {
  collection,
  deleteDoc,
  doc,
  getDocs,
  setDoc,
  type Firestore,
} from "firebase/firestore";
import type { Brief, Note, RunStamp, Sensitivity } from "./types.ts";
import { starterNotes } from "./samples.ts";

const seeding = new Set<string>();

export async function seedIfEmpty(db: Firestore, uid: string): Promise<void> {
  const key = `hearth-seeded-${uid}`;
  if (localStorage.getItem(key) || seeding.has(uid)) return;
  const existing = await getDocs(collection(db, "users", uid, "notes"));
  if (!existing.empty) {
    localStorage.setItem(key, "1");
    return;
  }
  seeding.add(uid);
  localStorage.setItem(key, "1");
  try {
    await Promise.all(starterNotes().map((note) => persistNote(db, uid, note)));
  } catch (error) {
    localStorage.removeItem(key);
    throw error;
  } finally {
    seeding.delete(uid);
  }
}

export async function persistNote(db: Firestore, uid: string, note: Note): Promise<void> {
  await setDoc(doc(db, "users", uid, "notes", note.id), {
    title: note.title,
    body: note.body,
    createdAt: note.createdAt,
    updatedAt: note.updatedAt,
    brief: note.brief,
    lastRun: note.lastRun,
  });
}

export async function removeNote(db: Firestore, uid: string, id: string): Promise<void> {
  await deleteDoc(doc(db, "users", uid, "notes", id));
}

export function noteFromSnapshot(id: string, data: Record<string, unknown>): Note {
  return {
    id,
    title: typeof data.title === "string" ? data.title : "",
    body: typeof data.body === "string" ? data.body : "",
    createdAt: typeof data.createdAt === "number" ? data.createdAt : Date.now(),
    updatedAt: typeof data.updatedAt === "number" ? data.updatedAt : Date.now(),
    brief: briefFromUnknown(data.brief),
    lastRun: runFromUnknown(data.lastRun),
  };
}

function briefFromUnknown(value: unknown): Brief | null {
  if (!value || typeof value !== "object") return null;
  const record = value as Record<string, unknown>;
  const sensitivity = record.sensitivity;
  if (typeof record.title !== "string" || typeof record.summary !== "string") return null;
  if (!isSensitivity(sensitivity)) return null;
  return {
    title: record.title,
    summary: record.summary,
    tags: stringList(record.tags),
    actions: stringList(record.actions),
    sensitivity,
  };
}

function runFromUnknown(value: unknown): RunStamp | null {
  if (!value || typeof value !== "object") return null;
  const record = value as Record<string, unknown>;
  const source = record.source;
  const reason = record.reason;
  if (source !== "on_device" && source !== "in_cloud" && source !== "unknown") return null;
  if (!isReason(reason)) return null;
  if (typeof record.plannedMode !== "string" || typeof record.cloudModel !== "string") return null;
  if (typeof record.latencyMs !== "number" || typeof record.charCount !== "number") return null;
  if (typeof record.at !== "number") return null;
  return {
    source,
    plannedMode: record.plannedMode,
    reason,
    cloudModel: record.cloudModel,
    latencyMs: record.latencyMs,
    charCount: record.charCount,
    at: record.at,
  };
}

function isSensitivity(value: unknown): value is Sensitivity {
  return value === "personal" || value === "work" || value === "public";
}

function isReason(value: unknown): value is RunStamp["reason"] {
  return (
    value === "short-note" ||
    value === "over-limit" ||
    value === "image-heavy" ||
    value === "forced-device" ||
    value === "forced-cloud" ||
    value === "offline"
  );
}

function stringList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((item): item is string => typeof item === "string");
}

export function blankNote(): Note {
  const now = Date.now();
  return {
    id: crypto.randomUUID(),
    title: "",
    body: "",
    createdAt: now,
    updatedAt: now,
    brief: null,
    lastRun: null,
  };
}
