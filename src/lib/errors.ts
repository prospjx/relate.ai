import { FirebaseError } from "firebase/app";

function readCode(error: unknown): string {
  if (error instanceof FirebaseError) return error.code;
  if (typeof error === "object" && error && "code" in error) {
    return String((error as { code: unknown }).code);
  }
  return "";
}

function readMessage(error: unknown): string {
  if (error instanceof Error && error.message) return error.message;
  return "";
}

export function explainAuth(error: unknown): string {
  const code = readCode(error);
  if (code.includes("operation-not-allowed")) {
    return "Enable Email/Password and Anonymous sign-in in Firebase Authentication, then try again.";
  }
  if (code.includes("email-already-in-use")) {
    return "That email already has an account. Sign in instead.";
  }
  if (
    code.includes("invalid-credential") ||
    code.includes("wrong-password") ||
    code.includes("user-not-found")
  ) {
    return "That email and password didn't match.";
  }
  if (code.includes("weak-password")) return "Use at least 6 characters.";
  if (code.includes("invalid-email")) return "Enter a valid email address.";
  if (code.includes("too-many-requests")) {
    return "Too many attempts. Wait a minute and try again.";
  }
  return "Sign-in didn't complete. Check Firebase Authentication and try again.";
}

export function explainFirestore(error: unknown): string {
  const code = readCode(error);
  if (code.includes("permission-denied")) {
    return "Firestore refused this save. Deploy firestore.rules so each signed-in person can only read and write their own notes.";
  }
  if (code.includes("unavailable") || code.includes("failed-precondition")) {
    return "Firestore isn't reachable. Create a Firestore database in the Firebase console, then try again.";
  }
  const message = readMessage(error);
  return message || "The note couldn't be saved.";
}

export function explainAi(error: unknown): string {
  const code = readCode(error);
  const message = readMessage(error);
  const haystack = `${code} ${message}`;
  if (/app.?check/i.test(haystack)) {
    return "App Check refused this request. Open the browser console, copy the App Check debug token, and register it under Security, App Check, Apps, Manage debug tokens.";
  }
  if (/api-not-enabled|API_KEY|api key|PERMISSION_DENIED|permission-denied/i.test(haystack)) {
    return "Firebase rejected the model request. Finish the AI Logic setup in the console and confirm the Gemini Developer API is enabled for this project.";
  }
  if (/unregistered|debug token|app-check\/throttled/i.test(haystack)) {
    return "This browser's App Check debug token isn't registered yet. Copy it from the console and add it in the Firebase App Check settings.";
  }
  if (/LanguageModel|NotSupportedError|on-device model|only_on_device/i.test(haystack)) {
    return "Gemini Nano isn't available for this request. Use desktop Chrome 139 or newer, enable the on-device model flag, and download the model. Hybrid mode uses the cloud when Nano isn't ready. Device lock does not.";
  }
  return message || "The brief didn't complete.";
}
