import { useEffect, useState } from "react";
import { starterNotes } from "../lib/samples.ts";
import { probeNano } from "../lib/ai.ts";
import { DEFAULT_CLOUD_MODEL, DEFAULT_ON_DEVICE_CHAR_LIMIT } from "../lib/route.ts";
import type { DeskMode, ImageAttachment, NanoAvailability, Note } from "../lib/types.ts";
import { Desk } from "./Desk.tsx";

export function PreviewDesk() {
  const [notes, setNotes] = useState<Note[]>(() => starterNotes());
  const [activeId, setActiveId] = useState<string | null>("monday-standup");
  const [mode, setMode] = useState<DeskMode>("hybrid");
  const [online, setOnline] = useState(navigator.onLine);
  const [nano, setNano] = useState<NanoAvailability>("unknown");
  const [image, setImage] = useState<ImageAttachment | null>(null);
  const [imageError, setImageError] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    void probeNano().then(setNano);
  }, []);

  useEffect(() => {
    const goOnline = () => setOnline(true);
    const goOffline = () => setOnline(false);
    window.addEventListener("online", goOnline);
    window.addEventListener("offline", goOffline);
    return () => {
      window.removeEventListener("online", goOnline);
      window.removeEventListener("offline", goOffline);
    };
  }, []);

  return (
    <Desk
      notes={notes}
      activeId={activeId}
      accountLabel="Preview"
      signOutLabel="Leave preview"
      onSignOut={() => {
        window.location.href = window.location.pathname;
      }}
      onSelect={(id) => {
        setActiveId(id);
        setImage(null);
        setError(null);
      }}
      onCreate={() => {
        const now = Date.now();
        const note: Note = {
          id: crypto.randomUUID(),
          title: "",
          body: "",
          createdAt: now,
          updatedAt: now,
          brief: null,
          lastRun: null,
        };
        setNotes((current) => [note, ...current]);
        setActiveId(note.id);
      }}
      onDelete={(id) => {
        setNotes((current) => current.filter((note) => note.id !== id));
        setActiveId((current) => (current === id ? null : current));
      }}
      onChange={(patch) => {
        setNotes((current) =>
          current.map((note) =>
            note.id === activeId ? { ...note, ...patch, updatedAt: Date.now() } : note,
          ),
        );
      }}
      onBrief={() =>
        setError(
          "This is a local preview. Add your Firebase config to .env.local and restart, then Make a brief runs through Firebase AI Logic.",
        )
      }
      onPrepare={() =>
        setError(
          "Preparing Gemini Nano calls Firebase AI Logic. Add your Firebase config to .env.local and restart to download the on-device model.",
        )
      }
      busy={false}
      preparing={false}
      error={error}
      mode={mode}
      onMode={setMode}
      limit={DEFAULT_ON_DEVICE_CHAR_LIMIT}
      cloudModel={DEFAULT_CLOUD_MODEL}
      remoteLabel="Preview uses the built-in limit of 1,800. Remote Config supplies this after Firebase is connected."
      online={online}
      nano={nano}
      progress={null}
      image={image}
      onImage={setImage}
      imageError={imageError}
      onImageError={setImageError}
      banner="Preview only. The meter is live. Briefs start once Firebase AI Logic is configured."
    />
  );
}
