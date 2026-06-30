<div align="center">

**English** · [简体中文](README.zh-CN.md)

<img src="KitchenInventory/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="120" alt="Stashster app icon" />

# Stashster · 囤囤鼠

> *stash* + ham**ster** — a little hamster that loves to stock up 🐹

**Say one sentence, and your kitchen stock is handled.**

A local-first, voice-driven personal kitchen inventory app for iOS, built with SwiftUI + SwiftData.

</div>

---

## What is this

"What do we still have at home?" "What do I need to buy?" — KitchenInventory exists to answer exactly these two everyday questions.

Its design follows a few principles:

- **Local-first / Privacy-first / Zero-latency**: speech recognition runs entirely on-device — no cloud sync, no accounts.
- **Speak, don't type**: you add items by talking, not typing.
- **Track state, not quantity**: it only cares about "have / running low / out" rather than counting units — closer to how real cooking decisions are made.
- **Everything is undoable, no confirmation dialogs**: every destructive action comes with an undo, so nothing interrupts you with an "Are you sure?".

## Features

### Shipped

| | Feature |
|---|---|
| 🎙️ | **Voice shopping list** — add / remove / assign to a store / mark "out" just by speaking; every action is undoable |
| 🧊 | **Smart three-tier inventory** — Fresh / Dry goods / Staples, auto-grouped; long-press to move an item between tiers |
| 🏪 | **Store management** — swipe to delete / rename / merge; same-name stores merge automatically |
| 🔤 | **Grocery identity dedup** — same name means same item; even saying "peach peach peach" records just one |
| 🔁 | **Status cycle** — have → running low → out; once out, it automatically returns to the shopping list |
| 📦 | **First-launch seed** of 12 staples (salt, sugar, oil, soy sauce, …) |
| 🐹 | **Custom app icon** (a hamster hugging a shopping bag) |

### In progress

| | Feature |
|---|---|
| 🧾 | **Receipt scanning** — Vision OCR (`ReceiptScanner`) + rule-based parsing (`ReceiptParser`) + a review screen (`ReceiptReviewView`). The code is ready and compiles, but it is not yet wired into a main tab. |

## Tech stack

- **SwiftUI** — the entire UI
- **SwiftData** — local persistence (`@Model`; `@Attribute(.unique)` enforces grocery identity)
- **Speech / SFSpeechRecognizer** — on-device speech recognition (locked to `zh_CN`, streaming transcription)
- **AVFoundation** — audio recording
- **Vision** — receipt OCR (in progress)
- Deployment target **iOS 17.0+**, Swift 6 (default MainActor isolation)

## Project structure

| File | Responsibility |
|---|---|
| `ContentView.swift` | `@main` entry + TabView + first-launch seeding |
| `Models.swift` | `Grocery` (three tiers / three states / unique name) and `Supermarket` data models |
| `GroceryActions.swift` | All business logic: voice command execution, CRUD, store management, seeding |
| `TextParser.swift` | Chinese sentence splitting + repeat collapsing + voice command parsing |
| `SpeechManager.swift` | `SFSpeechRecognizer` on-device speech recognition wrapper |
| `ShoppingListView.swift` | Shopping list tab + store picker / management |
| `InventoryView.swift` | Inventory tab, three-tier grouping + long-press to move tier |
| `ReceiptParser.swift` | Receipt text parsing (pure rules, in progress) |
| `ReceiptScanner.swift` | Vision OCR receipt scanning (in progress) |
| `ReceiptReviewView.swift` | Receipt result review screen (in progress) |
| `KitchenInventory/Assets.xcassets/` | AppIcon + AccentColor |

## Data model notes

- `Grocery`: `@Attribute(.unique) name` — **same name means same item**
  - tier `typeValue`: `fresh` / `dry` / `staple`
  - state `statusValue`: `have` / `runningLow` / `none`
  - `isOnShoppingList`, `store` (optional supermarket link, `.nullify`), `isStorePinned`
- `Supermarket`: delete rule `.nullify`, so deleting a store never cascades into deleting groceries

## Build & run

1. Open `KitchenInventory.xcodeproj` in Xcode (developed with Xcode 26 / iOS 17 SDK).
2. Under **Signing & Capabilities**, select your own Apple developer Team.
3. Run on a device or simulator.

> **Permissions**: the app needs microphone, speech recognition, and camera access, all configured via the project's `INFOPLIST_KEY_*` (this project uses `GENERATE_INFOPLIST_FILE`, with no standalone Info.plist). Missing microphone / speech permission will crash the app on launch.

## Known limitations

- The app is built around **Mandarin Chinese voice input** (UI and recognition are in Chinese).
- When "和 / 跟" (Chinese for "and / with") is used as a separator, it may mis-split grocery names that contain those characters (e.g. "和牛" / wagyu) — though this is rare.
- Continuous Chinese without separators is not auto-split (e.g. "青椒土豆" / "bell pepper potato" is treated as a single item) — left to a future model-based approach.
- The speech locale is locked to `zh_CN`, so mixed Chinese-English is limited; English store names are best entered manually.

---

<div align="center">
A personal project · a tool built for myself 🐹
</div>
