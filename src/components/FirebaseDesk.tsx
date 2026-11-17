import { useEffect, useMemo, useRef, useState } from "react";
import {
  createUserWithEmailAndPassword,
  onAuthStateChanged,
  signInAnonymously,
  signInWithEmailAndPassword,
  signOut,
  type User,
} from "firebase/auth";
import { collection, onSnapshot, orderBy, query } from "firebase/firestore";
import { fetchAndActivate, getValue } from "firebase/remote-config";
import { makeBrief, prepareDeviceModel, probeNano } from "../lib/ai.ts";
import type { FirebaseWebConfig } from "../lib/config.ts";
import { explainAi, explainAuth, explainFirestore } from "../lib/errors.ts";
import { initFirebase } from "../lib/firebase.ts";
import { blankNote, noteFromSnapshot, persistNote, removeNote, seedIfEmpty } from "../lib/notes.ts";
import {
  DEFAULT_CLOUD_MODEL,
  DEFAULT_ON_DEVICE_CHAR_LIMIT,
  planRoute,
  sanitizeLimit,
  sanitizeModel,
} from "../lib/route.ts";
import type { DeskMode, ImageAttachment, NanoAvailability, Note } from "../lib/types.ts";
import { AuthScreen, Splash } from "./AuthScreen.tsx";
import { Desk } from "./Desk.tsx";

type Dirty = { id: string; title: string; body: string; updatedAt: number };

export function FirebaseDesk({ config }: { config: FirebaseWebConfig }) {
  const services = useMemo(() => initFirebase(config), [config]);
  const [user, setUser] = useState<User | null | undefined>(undefined);
  const [notes, setNotes] = useState<Note[]>([]);
  const [activeId, setActiveId] = useState<string | null>(null);
  const [mode, setMode] = useState<DeskMode>("hybrid");
  const [limit, setLimit] = useState(DEFAULT_ON_DEVICE_CHAR_LIMIT);
  const [cloudModel, setCloudModel] = useState(DEFAULT_CLOUD_MODEL);
  const [remoteLabel, setRemoteLabel] = useState("Using the built-in limit until Remote Config loads.");
  const [online, setOnline] = useState(navigator.onLine);
  const [nano, setNano] = useState<NanoAvailability>("unknown");
  const [progress, setProgress] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);
  const [preparing, setPreparing] = useState(false);
  const [authBusy, setAuthBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [authError, setAuthError] = useState<string | null>(null);
  const [image, setImage] = useState<ImageAttachment | null>(null);
  const [imageError, setImageError] = useState<string | null>(null);

  const dirty = useRef<Dirty | null>(null);
  const latest = useRef<Note | null>(null);
  const timer = useRef<number | null>(null);
  const queue = useRef(Promise.resolve());
  const notesRef = useRef(notes);
  useEffect(() => {
    notesRef.current = notes;
  }, [notes]);

  useEffect(() => onAuthStateChanged(services.auth, setUser), [services.auth]);

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

  useEffect(() => {
    void probeNano().then(setNano);
  }, []);

  useEffect(() => {
    let cancelled = false;
    void fetchAndActivate(services.remoteConfig)
      .then(() => {
        if (cancelled) return;
        const nextLimit = sanitizeLimit(getValue(services.remoteConfig, "on_device_char_limit").asNumber());
        const nextModel = sanitizeModel(getValue(services.remoteConfig, "cloud_model").asString());
        setLimit(nextLimit);
        setCloudModel(nextModel);
        setRemoteLabel(`Remote Config limit ${nextLimit.toLocaleString("en-US")} · cloud model ${nextModel}`);
      })
      .catch(() => {
        if (!cancelled) {
          setRemoteLabel("Remote Config didn't load. Using the built-in limit of 1,800 and gemini-3.5-flash-lite.");
        }
      });
    return () => {
      cancelled = true;
    };
  }, [services.remoteConfig]);

  useEffect(() => {
    if (!user) return;
    const notesQuery = query(collection(services.db, "users", user.uid, "notes"), orderBy("updatedAt", "desc"));
    return onSnapshot(
      notesQuery,
      (snapshot) => {
        if (snapshot.empty) {
          void seedIfEmpty(services.db, user.uid).catch((seedError: unknown) => {
            setError(explainFirestore(seedError));
          });
        }
        const list = snapshot.docs.map((item) => noteFromSnapshot(item.id, item.data()));
        const pending = dirty.current;
        setNotes(
          list.map((note) =>
            pending && pending.id === note.id
              ? { ...note, title: pending.title, body: pending.body, updatedAt: pending.updatedAt }
              : note,
          ),
        );
        setActiveId((current) => {
          if (current && (current === pending?.id || list.some((note) => note.id === current))) return current;
          return list[0]?.id ?? null;
        });
      },
      (snapshotError) => setError(explainFirestore(snapshotError)),
    );
  }, [services.db, user]);

  function enqueueSave(uid: string, note: Note) {
    latest.current = note;
    dirty.current = { id: note.id, title: note.title, body: note.body, updatedAt: note.updatedAt };
    if (timer.current) window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => {
      const snapshot = latest.current;
      if (!snapshot) return;
      queue.current = queue.current
        .then(() => persistNote(services.db, uid, snapshot))
        .then(() => {
          if (dirty.current?.updatedAt === snapshot.updatedAt) dirty.current = null;
        })
        .catch((saveError: unknown) => setError(explainFirestore(saveError)));
    }, 450);
  }

  function updateActive(patch: { title?: string; body?: string }) {
    if (!user || !activeId) return;
    setNotes((current) =>
      current.map((note) => {
        if (note.id !== activeId) return note;
        const next = { ...note, ...patch, updatedAt: Date.now() };
        enqueueSave(user.uid, next);
        return next;
      }),
    );
  }

  async function createNote() {
    if (!user) return;
    const note = blankNote();
    setNotes((current) => [note, ...current]);
    setActiveId(note.id);
    setImage(null);
    setError(null);
    try {
      await persistNote(services.db, user.uid, note);
    } catch (createError) {
      setError(explainFirestore(createError));
    }
  }

  async function deleteNote(id: string) {
    if (!user) return;
    const note = notesRef.current.find((item) => item.id === id);
    const label = note?.title.trim() || "Untitled";
    if (!window.confirm(`Delete “${label}”?`)) return;
    if (dirty.current?.id === id) dirty.current = null;
    setImage(null);
    try {
      await removeNote(services.db, user.uid, id);
    } catch (deleteError) {
      setError(explainFirestore(deleteError));
    }
  }

  async function runBrief() {
    if (!user || busy || preparing) return;
    const note = notesRef.current.find((item) => item.id === activeId);
    if (!note || (!note.body.trim() && !image)) return;
    const plan = planRoute({
      deskMode: mode,
      charCount: note.body.trim().length,
      limit,
      online,
      image,
    });
    setBusy(true);
    setError(null);
    try {
      const outcome = await makeBrief({
        app: services.app,
        body: note.body,
        image,
        plan,
        cloudModel,
        onProgress: (fraction) => {
          setProgress(fraction);
          setNano("downloading");
        },
      });
      const title = note.title.trim() ? note.title : outcome.brief.title;
      const updated: Note = {
        ...note,
        title,
        brief: outcome.brief,
        lastRun: {
          ...outcome.stamp,
          charCount: note.body.trim().length,
          at: Date.now(),
        },
        updatedAt: Date.now(),
      };
      setNotes((current) => current.map((item) => (item.id === updated.id ? updated : item)));
      enqueueSave(user.uid, updated);
      setNano(await probeNano());
      setProgress(null);
    } catch (briefError) {
      setError(explainAi(briefError));
      setNano(await probeNano());
    } finally {
      setBusy(false);
    }
  }

  async function prepare() {
    if (preparing || busy) return;
    setPreparing(true);
    setError(null);
    setNano("downloading");
    try {
      await prepareDeviceModel(services.app, cloudModel, (fraction) => setProgress(fraction));
      setNano(await probeNano());
    } catch (prepareError) {
      setError(explainAi(prepareError));
      setNano(await probeNano());
    } finally {
      setProgress(null);
      setPreparing(false);
    }
  }

  async function withAuth(action: () => Promise<unknown>) {
    setAuthBusy(true);
    setAuthError(null);
    try {
      await action();
    } catch (authFailure) {
      setAuthError(explainAuth(authFailure));
    } finally {
      setAuthBusy(false);
    }
  }

  if (user === undefined) return <Splash label="Opening your desk…" />;
  if (!user) {
    return (
      <AuthScreen
        busy={authBusy}
        error={authError}
        onGuest={() => void withAuth(() => signInAnonymously(services.auth))}
        onSignIn={(email, password) =>
          void withAuth(() => signInWithEmailAndPassword(services.auth, email, password))
        }
        onCreate={(email, password) =>
          void withAuth(() => createUserWithEmailAndPassword(services.auth, email, password))
        }
      />
    );
  }

  return (
    <Desk
      notes={notes}
      activeId={activeId}
      accountLabel={user.isAnonymous ? "Guest" : user.email || "Signed in"}
      onSignOut={() => {
        dirty.current = null;
        setNotes([]);
        setActiveId(null);
        void signOut(services.auth);
      }}
      onSelect={(id) => {
        setActiveId(id);
        setImage(null);
        setImageError(null);
        setError(null);
      }}
      onCreate={() => void createNote()}
      onDelete={(id) => void deleteNote(id)}
      onChange={updateActive}
      onBrief={() => void runBrief()}
      onPrepare={() => void prepare()}
      busy={busy}
      preparing={preparing}
      error={error}
      mode={mode}
      onMode={setMode}
      limit={limit}
      cloudModel={cloudModel}
      remoteLabel={remoteLabel}
      online={online}
      nano={nano}
      progress={progress}
      image={image}
      onImage={setImage}
      imageError={imageError}
      onImageError={setImageError}
    />
  );
}
