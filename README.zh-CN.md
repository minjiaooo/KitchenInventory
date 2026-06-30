<div align="center">

[English](README.md) · **简体中文**

<img src="KitchenInventory/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="120" alt="囤囤鼠 App 图标" />

# 囤囤鼠 · KitchenInventory

**说一句话，就管好家里的厨房库存。**

一个本地优先、语音驱动的个人厨房食材管理 iOS App，用 SwiftUI + SwiftData 构建。

</div>

---

## 这是什么

「家里还有什么？」「该买什么了？」——囤囤鼠就为解决这两个日常问题。

它的设计围绕几条原则：

- **本地优先 / 隐私优先 / 零延迟**：语音识别在设备本地完成，无云同步、无账号体系。
- **说而不打**：录入靠说话，不靠打字。
- **管状态，不管数量**：只关心「有 / 快没了 / 没了」，而不是数有几个——更贴近真实做饭决策。
- **一切可撤销，不弹确认框**：每个破坏性操作都带撤销，不用确认弹窗打断你。

## 功能

### 已上线

| | 功能 |
|---|---|
| 🎙️ | **语音采购清单**——说话即可加入 / 删除 / 归到某超市 / 标记「没了」，每步都可撤销 |
| 🧊 | **智能库存三层视图**——生鲜 / 干货 / 常备 自动分层，长按可在分类间移动 |
| 🏪 | **超市管理**——侧滑删除 / 重命名 / 合并；同名自动合并去重 |
| 🔤 | **食材身份去重**——同名即同物，连说「桃子桃子桃子」也只记一个 |
| 🔁 | **状态轮转**——有 → 快没了 → 没了，用完自动回到待买清单 |
| 📦 | **首次启动预置** 12 种常备品（盐、糖、油、酱油……） |
| 🐹 | **自定义 App 图标**（仓鼠抱购物袋） |

### 开发中

| | 功能 |
|---|---|
| 🧾 | **小票识别**——Vision OCR（`ReceiptScanner`）+ 纯规则解析（`ReceiptParser`）+ 复核界面（`ReceiptReviewView`）。代码已就绪并参与编译，尚未接入主界面 Tab。 |

## 技术栈

- **SwiftUI** —— 全部界面
- **SwiftData** —— 本地持久化（`@Model`、`@Attribute(.unique)` 保证食材身份唯一）
- **Speech / SFSpeechRecognizer** —— 本地语音识别（锁定 `zh_CN`，流式上屏）
- **AVFoundation** —— 录音
- **Vision** —— 小票 OCR（开发中）
- 部署目标 **iOS 17.0+**，Swift 6（默认 MainActor 隔离）

## 工程结构

| 文件 | 职责 |
|---|---|
| `ContentView.swift` | `@main` 入口 + TabView + 首次启动预置 |
| `Models.swift` | `Grocery`（三分类 / 三状态 / 唯一名）与 `Supermarket` 数据模型 |
| `GroceryActions.swift` | 全部业务逻辑：语音指令执行、CRUD、超市管理、预置 |
| `TextParser.swift` | 中文断句 + 重复折叠 + 语音指令解析 |
| `SpeechManager.swift` | `SFSpeechRecognizer` 本地语音识别封装 |
| `ShoppingListView.swift` | 采购清单 Tab + 超市选择/管理 |
| `InventoryView.swift` | 库存 Tab，三层分组 + 长按移动分类 |
| `ReceiptParser.swift` | 小票文本解析（纯规则，开发中） |
| `ReceiptScanner.swift` | Vision OCR 扫描小票（开发中） |
| `ReceiptReviewView.swift` | 小票识别结果复核界面（开发中） |
| `KitchenInventory/Assets.xcassets/` | AppIcon + AccentColor |

## 数据模型要点

- `Grocery`：`@Attribute(.unique) name`——**同名即同物**
  - 分类 `typeValue`：`fresh`（生鲜）/ `dry`（干货）/ `staple`（常备）
  - 状态 `statusValue`：`have` / `runningLow` / `none`
  - `isOnShoppingList`、`store`（可选关联超市，`.nullify`）、`isStorePinned`
- `Supermarket`：删除规则 `.nullify`，食材不会被连带删除

## 构建运行

1. 用 Xcode 打开 `KitchenInventory.xcodeproj`（开发环境为 Xcode 26 / iOS 17 SDK）。
2. 在 **Signing & Capabilities** 选择你自己的 Apple 开发者 Team。
3. 选真机或模拟器运行。

> **权限**：App 需要麦克风、语音识别、相机权限，均配置在工程的 `INFOPLIST_KEY_*`（本工程用 `GENERATE_INFOPLIST_FILE`，无独立 Info.plist）。缺少麦克风 / 语音权限会导致启动崩溃。

## 已知局限

- 「和 / 跟」作为分隔符时，可能误伤含这些字的食材名（如「和牛」），但命中率极低。
- 无分隔符的连写中文不会自动拆分（如「青椒土豆」会被当成一个整体）——留给后续模型方案。
- 语音 locale 锁定 `zh_CN`，中英混说受限，英文店名建议手动输入。

---

<div align="center">
个人项目 · 自用工具 🐹
</div>
