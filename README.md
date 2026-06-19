# ModeloDos

Native **SwiftUI** implementation of the "Native Refined" design for **Modelo** — a
macOS client for running inference against local and cloud LLMs (LM Studio /
OpenRouter). Translated from a Claude Design handoff (`Modelo/INTEGRATION.md`) into
real SwiftUI, matching the `Modelo.xcodeproj` group layout.

> Modelo is a play on words: the app runs inference against large language **models**,
> and Modelo is a favorite beer. The brand mark is a 🍋‍🟩 lime.

## Screens

- **Chat** — context bar (model chip → picker, live context-window meter), message
  list with a web-search tool chip, per-message metrics, a streaming caret, and a
  composer with model chip + amber send.
- **Model Picker** — popover grouped by server with per-model load state
  (selected / loaded / idle+Load / cloud).
- **Server Status** — live server cards (latency / models / requests / throughput +
  sparklines) over a color-coded streaming console.
- **Reports** — stat tiles, throughput + TTFT charts (Swift Charts), and a per-model
  usage table with share bars.
- **Settings** — sub-nav, endpoint list with toggles, default-model / API-key fields,
  behavior switches.
- **Menu-bar mini chat** — a `MenuBarExtra(.window)` popover.
- **Model Browser** — the "01 Native Refined" model grid (bonus; not routed by default).

## Layout

```
Modelo/
├── Theme.swift            # design tokens, Color(hex:), Font.mono, ModeloMark, shared controls
├── AppStore.swift         # @Observable single source of truth + seed sample data
├── ModeloApp.swift        # @main: WindowGroup + MenuBarExtra(.window)
├── ContentView.swift      # NavigationSplitView shell + Section routing + toolbar
├── Models/                # Server, LMStudioModel (ModelInfo/ModelState), Message, Conversation, Persona
├── Settings/              # SettingsView
└── Views/                 # Sidebar, Chat (+ContextBar/MessageRow), ModelPicker (+LoadedModelRow),
                           # Status (+ServerRow/ConsoleInspector/MetricStat),
                           # Reports (+Throughput/TTFT charts), MenuBarChat, ModelBrowser
```

## Integrate into the Modelo app

1. Drop `Modelo/*` into your project's `Modelo` group (paths already match).
2. **Add `AppStore.swift` to the Modelo target** — the one file with no existing
   `project.pbxproj` slot.
3. If your real `Models/*.swift` already declare `Server` / `ModelInfo` / `ChatMessage` /
   `Conversation` / `Persona`, reconcile so there aren't duplicate definitions.
4. Replace the `AppStore.init()` seed data (mock sample frames) with live sources —
   `ServerMonitor`, `ChatSession`, `ReportCalculator` / `MetricsRollup`.
5. Swap the 🍋‍🟩 `ModeloMark` emoji for a real asset, plus a **template** (monochrome)
   menu-bar icon (`isTemplate = true`).

The `Services/` networking layer (LM Studio / OpenRouter / MCP clients, monitors,
keychain) is **out of scope** here — this repo is the UI/design layer only.

See `Modelo/INTEGRATION.md` for the full mapping.

## Target

macOS 14+, SwiftUI + Swift Charts + Observation. No third-party dependencies.
Fonts: SF Pro / SF Mono (Geist in the mock was a stand-in — not bundled).
