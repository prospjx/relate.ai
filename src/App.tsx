import { useMemo } from "react";
import { readFirebaseConfig } from "./lib/config.ts";
import { FirebaseDesk } from "./components/FirebaseDesk.tsx";
import { PreviewDesk } from "./components/PreviewDesk.tsx";
import { SetupScreen } from "./components/SetupScreen.tsx";

export default function App() {
  const config = useMemo(() => readFirebaseConfig(), []);
  const preview = new URLSearchParams(window.location.search).get("preview") === "1";
  if (!config && preview) return <PreviewDesk />;
  if (!config) return <SetupScreen />;
  return <FirebaseDesk config={config} />;
}
