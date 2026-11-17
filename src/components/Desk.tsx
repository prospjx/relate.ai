import { useEffect, useRef } from "react";
import { BriefPanel } from "./BriefPanel.tsx";
import { Editor } from "./Editor.tsx";
import { Sidebar } from "./Sidebar.tsx";
import type { DeskMode, ImageAttachment, NanoAvailability, Note } from "../lib/types.ts";

export type DeskProps = {
  notes: Note[];
  activeId: string | null;
  accountLabel: string;
  onSignOut: () => void;
  signOutLabel?: string;
  onSelect: (id: string) => void;
  onCreate: () => void;
  onDelete: (id: string) => void;
  onChange: (patch: { title?: string; body?: string }) => void;
  onBrief: () => void;
  onPrepare: () => void;
  busy: boolean;
  preparing: boolean;
  error: string | null;
  mode: DeskMode;
  onMode: (mode: DeskMode) => void;
  limit: number;
  cloudModel: string;
  remoteLabel: string;
  online: boolean;
  nano: NanoAvailability;
  progress: number | null;
  image: ImageAttachment | null;
  onImage: (image: ImageAttachment | null) => void;
  imageError: string | null;
  onImageError: (message: string | null) => void;
  banner?: string;
};

export function Desk(props: DeskProps) {
  const note = props.notes.find((item) => item.id === props.activeId) ?? null;
  const onBrief = useRef(props.onBrief);

  useEffect(() => {
    onBrief.current = props.onBrief;
  }, [props.onBrief]);

  useEffect(() => {
    function onKey(event: KeyboardEvent) {
      if (event.key === "Enter" && (event.ctrlKey || event.metaKey)) {
        event.preventDefault();
        onBrief.current();
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  return (
    <div className="shell">
      <header className="topbar">
        <div className="brand">
          <Flame />
          <div>
            <p className="wordmark">Hearth</p>
            <p className="tagline">Short notes stay on this device.</p>
          </div>
        </div>
        <div className="topbar-actions">
          <p className={nanoClass(props.nano)}>{nanoLabel(props.nano, props.progress)}</p>
          {!props.online && <p className="status-pill is-offline">Offline</p>}
          <p className="account">{props.accountLabel}</p>
          <button type="button" className="text-button" onClick={props.onSignOut}>
            {props.signOutLabel ?? "Sign out"}
          </button>
        </div>
      </header>
      {props.banner && <p className="banner">{props.banner}</p>}
      <main className="desk">
        <Sidebar
          notes={props.notes}
          activeId={props.activeId}
          onSelect={props.onSelect}
          onCreate={props.onCreate}
        />
        <Editor
          note={note}
          image={props.image}
          imageError={props.imageError}
          onChange={props.onChange}
          onImage={props.onImage}
          onImageError={props.onImageError}
          onDelete={() => note && props.onDelete(note.id)}
        />
        <BriefPanel
          note={note}
          mode={props.mode}
          onMode={props.onMode}
          limit={props.limit}
          cloudModel={props.cloudModel}
          remoteLabel={props.remoteLabel}
          online={props.online}
          image={props.image}
          nano={props.nano}
          progress={props.progress}
          busy={props.busy}
          preparing={props.preparing}
          error={props.error}
          onBrief={props.onBrief}
          onPrepare={props.onPrepare}
        />
      </main>
    </div>
  );
}

function nanoClass(nano: NanoAvailability): string {
  if (nano === "available") return "status-pill is-device";
  if (nano === "downloading") return "status-pill is-downloading";
  return "status-pill";
}

function nanoLabel(nano: NanoAvailability, progress: number | null): string {
  switch (nano) {
    case "available":
      return "Gemini Nano ready";
    case "downloading":
      return progress == null ? "Downloading Gemini Nano" : `Downloading Nano ${Math.round(progress * 100)}%`;
    case "downloadable":
      return "Gemini Nano not downloaded";
    case "unavailable":
      return "Gemini Nano unavailable";
    case "unsupported":
      return "No on-device model in this browser";
    default:
      return "Checking for Gemini Nano";
  }
}

function Flame() {
  return (
    <svg className="flame" viewBox="0 0 32 32" aria-hidden="true">
      <rect width="32" height="32" rx="10" fill="#241c16" />
      <path d="M16 6c2.1 3.6 6 5.6 6 10.2a6 6 0 1 1-12 0C10 11.6 13.9 9.6 16 6z" fill="#f0b56b" />
      <path d="M16 14.2c1 1.8 2.7 2.7 2.7 4.8a2.7 2.7 0 1 1-5.4 0c0-2.1 1.7-3 2.7-4.8z" fill="#c24d24" />
    </svg>
  );
}
