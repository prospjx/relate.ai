import { useState } from "react";

type AuthScreenProps = {
  busy: boolean;
  error: string | null;
  onGuest: () => void;
  onSignIn: (email: string, password: string) => void;
  onCreate: (email: string, password: string) => void;
};

export function AuthScreen({ busy, error, onGuest, onSignIn, onCreate }: AuthScreenProps) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");

  return (
    <div className="gate">
      <section className="gate-copy">
        <p className="eyebrow">Firebase AI Logic · Chrome</p>
        <h1>Notes that stay on the device until they don't fit.</h1>
        <p>
          Hearth writes a brief on Gemini Nano when a note is short. When the note passes the limit from Remote
          Config, or Nano isn't on this computer, the same action runs in the cloud. Every brief says which one
          happened.
        </p>
      </section>
      <section className="gate-card">
        <button type="button" className="primary" disabled={busy} onClick={onGuest}>
          {busy ? "Signing in…" : "Continue as guest"}
        </button>
        <p className="or">or use email</p>
        <form
          onSubmit={(event) => {
            event.preventDefault();
            onSignIn(email.trim(), password);
          }}
        >
          <label htmlFor="email">Email</label>
          <input
            id="email"
            type="email"
            autoComplete="email"
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            required
          />
          <label htmlFor="password">Password</label>
          <input
            id="password"
            type="password"
            autoComplete="current-password"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            minLength={6}
            required
          />
          {error && (
            <p className="error" role="alert">
              {error}
            </p>
          )}
          <div className="form-actions">
            <button type="submit" className="secondary" disabled={busy}>
              Sign in
            </button>
            <button
              type="button"
              className="text-button"
              disabled={busy}
              onClick={() => onCreate(email.trim(), password)}
            >
              Create account
            </button>
          </div>
        </form>
      </section>
    </div>
  );
}

export function Splash({ label }: { label: string }) {
  return (
    <div className="splash">
      <p className="wordmark">Hearth</p>
      <p>{label}</p>
    </div>
  );
}
