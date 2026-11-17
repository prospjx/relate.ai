import { useRef } from "react";
import type { ImageAttachment, Note } from "../lib/types.ts";

type EditorProps = {
  note: Note | null;
  image: ImageAttachment | null;
  imageError: string | null;
  onChange: (patch: { title?: string; body?: string }) => void;
  onImage: (image: ImageAttachment | null) => void;
  onImageError: (message: string | null) => void;
  onDelete: () => void;
};

export function Editor({
  note,
  image,
  imageError,
  onChange,
  onImage,
  onImageError,
  onDelete,
}: EditorProps) {
  const inputRef = useRef<HTMLInputElement>(null);

  if (!note) {
    return (
      <section className="editor editor-empty">
        <p>Choose a note, or start a new one.</p>
      </section>
    );
  }

  return (
    <section className="editor">
      <div className="editor-toolbar">
        <span className="editor-kicker">Private note</span>
        <button type="button" className="text-button danger" onClick={onDelete}>
          Delete
        </button>
      </div>
      <label className="sr-only" htmlFor="note-title">
        Title
      </label>
      <input
        id="note-title"
        className="title-input"
        value={note.title}
        placeholder="Untitled"
        onChange={(event) => onChange({ title: event.target.value })}
      />
      <label className="sr-only" htmlFor="note-body">
        Note
      </label>
      <textarea
        id="note-body"
        className="body-input"
        value={note.body}
        placeholder="Write something you'd rather not send to a server unless you have to."
        onChange={(event) => onChange({ body: event.target.value })}
      />
      <div className="editor-foot">
        <button type="button" className="text-button" onClick={() => inputRef.current?.click()}>
          Attach JPEG or PNG
        </button>
        <input
          ref={inputRef}
          className="sr-only"
          type="file"
          accept="image/jpeg,image/png"
          aria-label="Image file"
          tabIndex={-1}
          onChange={(event) => {
            const file = event.target.files?.[0];
            event.target.value = "";
            if (file) void readImage(file, onImage, onImageError);
          }}
        />
        {image && (
          <span className="image-chip">
            {image.name}
            <button type="button" onClick={() => onImage(null)} aria-label="Remove image">
              Remove
            </button>
          </span>
        )}
        {imageError && <span className="inline-error">{imageError}</span>}
      </div>
    </section>
  );
}

async function readImage(
  file: File,
  onImage: (image: ImageAttachment | null) => void,
  onImageError: (message: string | null) => void,
) {
  const mimeType =
    file.type === "image/png"
      ? "image/png"
      : file.type === "image/jpeg" || file.type === "image/jpg"
        ? "image/jpeg"
        : null;
  if (!mimeType) {
    onImageError("Attach a JPEG or PNG. Those are the image types Gemini Nano can read.");
    return;
  }
  if (file.size > 4 * 1024 * 1024) {
    onImageError("Choose an image under 4 MB.");
    return;
  }
  const dataUrl = await file.arrayBuffer().then((buffer) => {
    const bytes = new Uint8Array(buffer);
    let binary = "";
    const chunk = 0x8000;
    for (let index = 0; index < bytes.length; index += chunk) {
      binary += String.fromCharCode(...bytes.subarray(index, index + chunk));
    }
    return btoa(binary);
  });
  onImageError(null);
  onImage({
    name: file.name || "attachment",
    mimeType,
    data: dataUrl,
    charLength: dataUrl.length,
  });
}
