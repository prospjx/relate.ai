import { configChecklist } from "../lib/config.ts";

export function SetupScreen() {
  const fields = configChecklist();
  return (
    <div className="gate">
      <section className="gate-copy">
        <p className="eyebrow">Setup</p>
        <h1>Connect Hearth to your Firebase project.</h1>
        <p>
          The desk uses Firebase AI Logic for hybrid inference, App Check to protect that API, Authentication and
          Firestore for your notes, and Remote Config for the on-device character limit.
        </p>
        <p>
          Copy <code>.env.example</code> to <code>.env.local</code>, fill in the values, and restart{" "}
          <code>npm run dev</code>. The README has the console clicks in order.
        </p>
      </section>
      <section className="gate-card">
        <ul className="checklist">
          {fields.map((field) => (
            <li key={field.key} className={field.present ? "is-done" : ""}>
              <span>{field.present ? "Ready" : "Missing"}</span>
              {field.label}
            </li>
          ))}
        </ul>
        <a className="secondary setup-link" href="?preview=1">
          Preview the desk without Firebase
        </a>
        <p className="quiet">
          The preview shows the routing meter only. Briefs run after Firebase is configured, through{" "}
          <code>makeBrief()</code> in <code>src/lib/ai.ts</code>.
        </p>
      </section>
    </div>
  );
}
