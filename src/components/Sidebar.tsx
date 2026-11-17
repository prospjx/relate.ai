import type { Note } from "../lib/types.ts";

type SidebarProps = {
  notes: Note[];
  activeId: string | null;
  onSelect: (id: string) => void;
  onCreate: () => void;
};

export function Sidebar({ notes, activeId, onSelect, onCreate }: SidebarProps) {
  return (
    <aside className="sidebar">
      <div className="sidebar-head">
        <h2>Notes</h2>
        <button type="button" className="text-button" onClick={onCreate}>
          New note
        </button>
      </div>
      <ul className="note-list">
        {notes.map((note) => {
          const title = note.title.trim() || "Untitled";
          const preview = note.body.trim().split("\n").find((line) => line.trim()) ?? "Empty note";
          return (
            <li key={note.id}>
              <button
                type="button"
                className={note.id === activeId ? "note-link is-active" : "note-link"}
                onClick={() => onSelect(note.id)}
              >
                <span className="note-link-title">{title}</span>
                <span className="note-link-preview">{preview}</span>
                <span className="note-link-meta">{formatWhen(note.updatedAt)}</span>
              </button>
            </li>
          );
        })}
      </ul>
      {notes.length === 0 && <p className="empty-copy">No notes yet.</p>}
    </aside>
  );
}

function formatWhen(ms: number): string {
  return new Intl.DateTimeFormat("en", { month: "short", day: "numeric" }).format(ms);
}
