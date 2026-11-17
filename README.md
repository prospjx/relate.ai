# BuildWithAI workspace

This folder has two apps:

- **Hearth** (this README) — Firebase AI Logic hybrid notes for #BuildHybridAI
- **Orbit** (`orbit/`) — simple Flutter messaging app for local chats with your contacts (AI features come next)

---

# Hearth

Hearth is a private notebook for Chrome. Short notes are briefed on this device with Gemini Nano. Long notes go to the cloud. Firebase AI Logic makes that choice one SDK call, and the desk shows where the brief actually ran.

A brief is a title, a two or three sentence summary, a few tags, and the next steps already in the note. Nothing is invented on purpose: the prompt tells the model to stay inside the text you wrote.

## Why it's hybrid

On-device inference is private, works offline, and doesn't spend cloud quota. It also isn't on every computer, and Gemini Nano's context is about 9,216 tokens. Hearth treats that as a product decision, not a hidden fallback.

- A note under the Remote Config character limit uses `InferenceMode.PREFER_ON_DEVICE`. If Gemini Nano is ready, the brief stays on the device. If it isn't, Firebase AI Logic falls back to the cloud and Hearth says so.
- A note over that limit uses `InferenceMode.ONLY_IN_CLOUD`, because a long page is the cloud model's job.
- **On device** locks the brief to `InferenceMode.ONLY_ON_DEVICE`. If Nano isn't available, the request stops instead of quietly leaving the machine.
- **Cloud** uses `InferenceMode.ONLY_IN_CLOUD`.
- Offline, Hearth can only try Gemini Nano.

The limit ships as 1,800 characters. Change `on_device_char_limit` in Remote Config without shipping a new build. The two sample notes are on purpose: Monday standup is under the limit, and the East Branch interview is over it.

## What runs through Firebase

| Product | What Hearth uses it for |
| --- | --- |
| Firebase AI Logic | `getAI`, `GoogleAIBackend`, `getGenerativeModel`, `initializeDeviceModel`, and `generateContent` in `src/lib/ai.ts` |
| Hybrid inference | `InferenceMode` chooses the route. `response.inferenceSource` (`on_device` or `in_cloud`) is saved on the note and shown on the brief |
| Structured output | The same `Schema` is the cloud `responseSchema` and the on-device `responseConstraint`, so both paths return a brief |
| App Check | Initialized before any AI call. Debug tokens are used for local development |
| Authentication | Email/password and anonymous guest sign-in |
| Cloud Firestore | Notes, briefs, and the inference stamp, one user at a time |
| Remote Config | `on_device_char_limit` and `cloud_model` |

This is a new project, built for the web (Chrome) track. On-device inference is Gemini Nano through the Chrome Prompt API, which is the on-device model Firebase AI Logic uses for web. The cloud default is `gemini-3.5-flash-lite`.

## Run it locally

You need desktop Chrome 139 or newer, Node.js 22 or newer, and a Firebase project on the Spark plan or above. Text inference through the Gemini Developer API is free inside the current usage limits.

### 1. Chrome, for Gemini Nano

1. Update Chrome at `chrome://settings/help`.
2. Open `chrome://flags/#prompt-api-for-gemini-nano-multimodal-input` and set it to **Enabled**. Restart Chrome.
3. Optional, so the first brief doesn't wait on a download: open DevTools and run `await LanguageModel.availability()`. If it prints `downloadable`, run `await LanguageModel.create()` and let it finish. `available` means Nano is ready.

### 2. Firebase

1. Create a project in the [Firebase console](https://console.firebase.google.com/). Analytics is optional.
2. Add a **Web** app and copy its config.
3. Open **AI Services → AI Logic**, choose **Get started**, and select the **Gemini Developer API**.
4. App Check is enforced for AI Logic. Register the web app with **reCAPTCHA Enterprise** and copy the site key. For localhost, do not add `localhost` to the reCAPTCHA allowed domains. Use a debug token instead (step 6).
5. In **Authentication → Sign-in method**, enable **Email/Password** and **Anonymous**.
6. Create a **Cloud Firestore** database.
7. Open **Remote Config** and publish two parameters (the app also has these as defaults):
   - `on_device_char_limit` — Number — `1800`
   - `cloud_model` — String — `gemini-3.5-flash-lite`
8. Publish the Firestore rules from `firestore.rules`. In the console, paste them into **Firestore → Rules**. Or, after `npx firebase-tools login` and `npx firebase-tools use --add`:

```bash
npx firebase-tools deploy --only firestore:rules
```

### 3. This app

```bash
npm install
```

Windows:

```bash
copy .env.example .env.local
```

macOS or Linux:

```bash
cp .env.example .env.local
```

Fill in `.env.local` from the web app config and the reCAPTCHA site key. Then:

```bash
npm run dev
```

Open the printed localhost URL in Chrome. The first load prints an App Check debug token in the DevTools console. Register it under **Security → App Check → Apps → Manage debug tokens**. Requests fail until that token is registered.

Sign in as a guest or with email. Hearth seeds two notes. Open **Monday standup**, choose **Hybrid**, and click **Make a brief**. The result should say it ran on this device once Nano is ready. Open **East Branch interview**. The meter moves to the cloud because the note is past the limit. Make a brief and the result should name the cloud model.

**On device** is the privacy lock. **Cloud** forces the server. Ctrl+Enter makes a brief. JPEG and PNG attachments are sent as inline data, which is what on-device inference accepts.

## Host it for judging

Vite bakes `VITE_*` values in at build time. For a public URL, register the hosting domain on the reCAPTCHA Enterprise key, and do not set `VITE_APPCHECK_DEBUG_TOKEN` in that build.

```bash
npm run build
npx firebase-tools deploy --only hosting,firestore:rules
```

`firebase.json` rewrites every path to `index.html`.

## Demo video

Keep it under three minutes.

1. Show the Nano status, and click **Prepare Gemini Nano** if it isn't ready.
2. Brief the short Monday note on Hybrid. Point at the "on this device" result.
3. Open the East Branch interview, show the meter cross the limit, and brief it in the cloud.
4. Optional: lock a short note to **On device**, or switch Chrome offline and brief the short note again.

## Troubleshooting

- **App Check refused this request.** Register the debug token from the browser console. `npm run dev` turns the debug provider on. A production build does not, unless `VITE_APPCHECK_DEBUG_TOKEN` is set to a token you created yourself. Don't commit that token.
- **Sign-in method disabled.** Enable Email/Password and Anonymous.
- **Firestore refused this save.** Publish `firestore.rules`.
- **Nano isn't available.** Confirm desktop Chrome, the flag above, and that `LanguageModel.availability()` is not `unavailable`. Hybrid still briefs the note in the cloud. On device does not.
- **The first on-device brief is slow.** The model download can take several minutes. Prepare Nano before recording.

## License

Apache License 2.0. See `LICENSE`.
