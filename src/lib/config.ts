export type FirebaseWebConfig = {
  apiKey: string;
  authDomain: string;
  projectId: string;
  appId: string;
  recaptchaSiteKey: string;
  storageBucket?: string;
  messagingSenderId?: string;
};

export type ConfigField = {
  key: keyof ImportMetaEnv;
  label: string;
  present: boolean;
};

const fields: { key: keyof ImportMetaEnv; label: string }[] = [
  { key: "VITE_FIREBASE_API_KEY", label: "Firebase API key" },
  { key: "VITE_FIREBASE_AUTH_DOMAIN", label: "Auth domain" },
  { key: "VITE_FIREBASE_PROJECT_ID", label: "Project ID" },
  { key: "VITE_FIREBASE_APP_ID", label: "App ID" },
  { key: "VITE_RECAPTCHA_SITE_KEY", label: "App Check reCAPTCHA Enterprise site key" },
];

function readEnv(name: keyof ImportMetaEnv): string {
  const value = import.meta.env[name];
  return typeof value === "string" ? value.trim() : "";
}

export function configChecklist(): ConfigField[] {
  return fields.map((field) => ({
    ...field,
    present: readEnv(field.key).length > 0,
  }));
}

export function readFirebaseConfig(): FirebaseWebConfig | null {
  const apiKey = readEnv("VITE_FIREBASE_API_KEY");
  const authDomain = readEnv("VITE_FIREBASE_AUTH_DOMAIN");
  const projectId = readEnv("VITE_FIREBASE_PROJECT_ID");
  const appId = readEnv("VITE_FIREBASE_APP_ID");
  const recaptchaSiteKey = readEnv("VITE_RECAPTCHA_SITE_KEY");
  if (!apiKey || !authDomain || !projectId || !appId || !recaptchaSiteKey) return null;

  const storageBucket = readEnv("VITE_FIREBASE_STORAGE_BUCKET");
  const messagingSenderId = readEnv("VITE_FIREBASE_MESSAGING_SENDER_ID");
  return {
    apiKey,
    authDomain,
    projectId,
    appId,
    recaptchaSiteKey,
    ...(storageBucket ? { storageBucket } : {}),
    ...(messagingSenderId ? { messagingSenderId } : {}),
  };
}
