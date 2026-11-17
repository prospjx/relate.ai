import { type FirebaseApp, getApp, getApps, initializeApp } from "firebase/app";
import { initializeAppCheck, ReCaptchaEnterpriseProvider } from "firebase/app-check";
import { getAuth } from "firebase/auth";
import {
  getFirestore,
  initializeFirestore,
  persistentLocalCache,
  persistentMultipleTabManager,
  type Firestore,
} from "firebase/firestore";
import { getRemoteConfig, type RemoteConfig } from "firebase/remote-config";
import type { FirebaseWebConfig } from "./config.ts";
import { DEFAULT_CLOUD_MODEL, DEFAULT_ON_DEVICE_CHAR_LIMIT } from "./route.ts";

export type FirebaseServices = {
  app: FirebaseApp;
  auth: ReturnType<typeof getAuth>;
  db: Firestore;
  remoteConfig: RemoteConfig;
};

let appCheckReady = false;
let firestore: Firestore | null = null;
let remoteConfig: RemoteConfig | null = null;

function applyDebugToken(): void {
  const token = import.meta.env.VITE_APPCHECK_DEBUG_TOKEN?.trim();
  if (import.meta.env.DEV) {
    window.FIREBASE_APPCHECK_DEBUG_TOKEN = token || true;
    return;
  }
  if (token) window.FIREBASE_APPCHECK_DEBUG_TOKEN = token;
}

export function initFirebase(config: FirebaseWebConfig): FirebaseServices {
  const app = getApps().length
    ? getApp()
    : initializeApp({
        apiKey: config.apiKey,
        authDomain: config.authDomain,
        projectId: config.projectId,
        appId: config.appId,
        ...(config.storageBucket ? { storageBucket: config.storageBucket } : {}),
        ...(config.messagingSenderId ? { messagingSenderId: config.messagingSenderId } : {}),
      });

  if (!appCheckReady) {
    applyDebugToken();
    initializeAppCheck(app, {
      provider: new ReCaptchaEnterpriseProvider(config.recaptchaSiteKey),
      isTokenAutoRefreshEnabled: true,
    });
    appCheckReady = true;
  }

  return {
    app,
    auth: getAuth(app),
    db: ensureFirestore(app),
    remoteConfig: ensureRemoteConfig(app),
  };
}

function ensureFirestore(app: FirebaseApp): Firestore {
  if (firestore) return firestore;
  try {
    firestore = initializeFirestore(app, {
      localCache: persistentLocalCache({ tabManager: persistentMultipleTabManager() }),
    });
  } catch {
    firestore = getFirestore(app);
  }
  return firestore;
}

function ensureRemoteConfig(app: FirebaseApp): RemoteConfig {
  if (remoteConfig) return remoteConfig;
  remoteConfig = getRemoteConfig(app);
  remoteConfig.settings.minimumFetchIntervalMillis = 60_000;
  remoteConfig.defaultConfig = {
    on_device_char_limit: DEFAULT_ON_DEVICE_CHAR_LIMIT,
    cloud_model: DEFAULT_CLOUD_MODEL,
  };
  return remoteConfig;
}
