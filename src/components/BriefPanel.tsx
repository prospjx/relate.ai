import { explainPlan, explainSource, planRoute, prefersDevice } from "../lib/route.ts";
import type { DeskMode, ImageAttachment, NanoAvailability, Note } from "../lib/types.ts";

type BriefPanelProps = {
  note: Note | null;
  mode: DeskMode;
  onMode: (mode: DeskMode) => void;
  limit: number;
  cloudModel: string;
  remoteLabel: string;
  online: boolean;
  image: ImageAttachment | null;
  nano: NanoAvailability;
  progress: number | null;
  busy: boolean;
  preparing: boolean;
  error: string | null;
  onBrief: () => void;
  onPrepare: () => void;
};

const modes: { id: DeskMode; label: string }[] = [
  { id: "hybrid", label: "Hybrid" },
  { id: "device", label: "On device" },
  { id: "cloud", label: "Cloud" },
];

export function BriefPanel(props: BriefPanelProps) {
  const { note } = props;
  const charCount = note?.body.trim().length ?? 0;
  const plan = planRoute({
    deskMode: props.mode,
    charCount,
    limit: props.limit,
    online: props.online,
    image: props.image,
  });
  const deviceSide = prefersDevice(plan.mode);
  const canBrief = Boolean(note && (charCount > 0 || props.image) && !props.busy && !props.preparing);

  return (
    <aside className="brief">
      <div className="brief-block">
        <p className="eyebrow">Next brief</p>
        <div className="segmented" role="radiogroup" aria-label="Where to run the brief">
          {modes.map((item) => (
            <button
              key={item.id}
              type="button"
              role="radio"
              aria-checked={props.mode === item.id}
              className={props.mode === item.id ? "is-selected" : ""}
              onClick={() => props.onMode(item.id)}
            >
              {item.label}
            </button>
          ))}
        </div>
        <div className={deviceSide ? "meter is-device" : "meter is-cloud"}>
          <div className="meter-labels">
            <span>On this device</span>
            <span>Cloud</span>
          </div>
          <div className="meter-track" aria-hidden="true">
            <span className="meter-knob" />
          </div>
          <p className="meter-count">
            <strong>{charCount.toLocaleString("en-US")}</strong>
            <span> / {props.limit.toLocaleString("en-US")} on-device limit</span>
          </p>
        </div>
        <p className="plan-copy">{note ? explainPlan(plan, charCount, props.limit, props.cloudModel) : "Open a note to see where its brief will run."}</p>
        <p className="remote-copy">{props.remoteLabel}</p>
      </div>

      <div className="brief-actions">
        <button type="button" className="primary" disabled={!canBrief} onClick={props.onBrief}>
          {props.busy ? "Writing the brief…" : "Make a brief"}
        </button>
        <p className="shortcut">Ctrl Enter</p>
        {props.nano !== "available" && (
          <button
            type="button"
            className="secondary"
            disabled={props.preparing || props.busy}
            onClick={props.onPrepare}
          >
            {props.preparing
              ? props.progress == null
                ? "Preparing Gemini Nano…"
                : `Downloading Gemini Nano ${Math.round(props.progress * 100)}%`
              : "Prepare Gemini Nano"}
          </button>
        )}
        {props.error && (
          <p className="error" role="alert">
            {props.error}
          </p>
        )}
      </div>

      <div className="brief-result" aria-live="polite">
        {note?.brief && note.lastRun ? (
          <>
            <p className={note.lastRun.source === "on_device" ? "source-pill is-device" : "source-pill is-cloud"}>
              {note.lastRun.source === "on_device"
                ? "On this device · Gemini Nano"
                : note.lastRun.source === "in_cloud"
                  ? `Cloud · ${note.lastRun.cloudModel}`
                  : "Inference source unknown"}
            </p>
            <p className="source-detail">{explainSource(note.lastRun.source, note.lastRun.plannedMode)}</p>
            <p className="source-meta">
              {(note.lastRun.latencyMs / 1000).toFixed(1)}s · {note.lastRun.charCount.toLocaleString("en-US")} characters
            </p>
            <h3>{note.brief.title}</h3>
            <p className="summary">{note.brief.summary}</p>
            <p className={`sensitivity is-${note.brief.sensitivity}`}>{note.brief.sensitivity}</p>
            {note.brief.tags.length > 0 && (
              <ul className="tags">
                {note.brief.tags.map((tag) => (
                  <li key={tag}>{tag}</li>
                ))}
              </ul>
            )}
            <h4>Next steps</h4>
            {note.brief.actions.length > 0 ? (
              <ol>
                {note.brief.actions.map((action) => (
                  <li key={action}>{action}</li>
                ))}
              </ol>
            ) : (
              <p className="quiet">No next steps in this note.</p>
            )}
          </>
        ) : (
          <p className="quiet">
            A brief is a title, a short summary, tags, and the next steps already in the note. Hearth shows whether
            Gemini Nano or the cloud wrote it.
          </p>
        )}
      </div>
    </aside>
  );
}
