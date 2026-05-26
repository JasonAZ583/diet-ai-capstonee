# DietAI — SwiftUI Demo Client

A minimal SwiftUI app that talks to the FastAPI backend in this repo.

## What's inside

```
ios/DietAI/
├── DietAIApp.swift                # @main entry
├── Models/Models.swift            # Codable types matching FastAPI schemas
├── Networking/APIClient.swift     # Async/await URLSession client
├── ViewModels/                    # ObservableObject view models per tab
└── Views/
    ├── ContentView.swift          # TabView shell
    ├── DashboardView.swift        # Today's macros + meal list
    ├── VaultView.swift            # Food vault list + add sheet
    ├── MealsView.swift            # Today's meals + log sheet
    └── ChatView.swift             # AI coach chat
```

## Running the demo

### 1. Start the FastAPI backend

```bash
cd /Users/anthony/Documents/dev/gh/dietai
uv run uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

CORS is already enabled so the iOS client can call it. `--host 0.0.0.0`
also lets a physical device on the same Wi‑Fi reach your Mac.

### 2. Create the Xcode project

Xcode project files (`.xcodeproj`) are XML and not friendly to generate by
hand. Spin one up in Xcode and drop the source files in:

1. Open Xcode → **File → New → Project…**
2. Pick **iOS → App**, click Next.
3. Settings:
   - Product Name: **DietAI**
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Storage: **None**
4. Save the project anywhere — for example, inside this `ios/` folder.
5. **Delete** the auto‑generated `DietAIApp.swift` and `ContentView.swift`
   from the Xcode project (move to trash).
6. In Finder, open `ios/DietAI/`. Drag the four folders
   (`Models`, `Networking`, `ViewModels`, `Views`) **and** `DietAIApp.swift`
   into the Xcode project navigator. When prompted:
   - ✅ Copy items if needed (or leave unchecked to reference in place)
   - ✅ Create groups
   - ✅ Add to target: DietAI

### 3. Allow plain HTTP in the simulator

The simulator talks to `http://localhost:8000`, but iOS blocks plaintext
HTTP by default (App Transport Security). Add an exception:

1. Select the project in the navigator → target **DietAI** → **Info** tab.
2. Add a new key: **App Transport Security Settings** (Dictionary).
3. Inside it, add **Allow Arbitrary Loads** → set to **YES**.

Or add this directly to `Info.plist` source:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

For production you would scope this per-domain, but for a local demo
arbitrary loads is fine.

### 4. Run

- **Simulator**: just hit ⌘R. The default base URL `http://localhost:8000`
  works as-is.
- **Physical device**: edit `Networking/APIClient.swift` and change
  `baseURL` to your Mac's LAN IP, e.g.
  `http://192.168.1.10:8000`. Find it with `ipconfig getifaddr en0`.

## What the demo does

- **Today** — Pulls `/api/dashboard`, shows calories + macros against goals
  and lists today's meals. Pull-to-refresh.
- **Vault** — `GET/POST/DELETE /api/vault` for stored food items. Add via
  manual entry sheet (no barcode scanning in the demo).
- **Meals** — `GET/POST/DELETE /api/meals`. Log either by picking a vault
  item or entering macros manually.
- **Chat** — `POST /api/chat` for the AI coach, with multi-turn history.
  Requires `DEDALUS_API_KEY` set on the backend; without it the backend
  returns a fallback reply.

## Not in the demo (kept intentionally small)

- Barcode camera scanning (would need `AVFoundation` + permissions).
- Goals editor (`/api/goals/manual`, `/api/goals/calculate`).
- AI meal suggestions (`/api/meals/suggest` + `/api/meals/confirm`).

These all have backend endpoints already, so adding them is just another
ViewModel + View.
