import SwiftUI
import SwiftData
import UIKit

struct ShoppingListView: View {
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<Grocery> { $0.isOnShoppingList },
           sort: \Grocery.addedToListAt, order: .reverse)
    private var items: [Grocery]

    @StateObject private var speech = SpeechManager()

    // 通用提示 + 撤销
    @State private var toastMessage: String?
    @State private var undoAction: (() -> Void)?
    @State private var toastID = 0

    // 手动加一项
    @State private var showingAdd = false
    @State private var addText = ""

    // 重命名（修正识别）
    @State private var renamingGrocery: Grocery?
    @State private var renameText = ""

    // 归店
    @State private var pickingStoreFor: Grocery?

    // 拍小票（C1）
    @State private var showingCamera = false
    @State private var parsedReceipt: ParsedReceipt?
    @State private var isRecognizing = false

    // 分组：不限超市(nil) 置顶，其余按店名
    private var grouped: [(title: String, items: [Grocery])] {
        let dict = Dictionary(grouping: items) { $0.store }
        var sections: [(String, [Grocery])] = []
        if let noStore = dict[nil], !noStore.isEmpty {
            sections.append(("不限超市", noStore))
        }
        for store in dict.keys.compactMap({ $0 }).sorted(by: { $0.name < $1.name }) {
            sections.append((store.name, dict[store] ?? []))
        }
        return sections.map { (title: $0.0, items: $0.1) }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                listOrEmpty
                    .sheet(item: $pickingStoreFor) { StorePickerSheet(grocery: $0) }
                    .alert("改个名字", isPresented: Binding(
                        get: { renamingGrocery != nil },
                        set: { if !$0 { renamingGrocery = nil } })) {
                        TextField("名称", text: $renameText)
                        Button("保存") {
                            if let g = renamingGrocery {
                                GroceryActions.rename(g, to: renameText, in: context)
                            }
                            renamingGrocery = nil
                        }
                        Button("取消", role: .cancel) { renamingGrocery = nil }
                    }

                if speech.isRecording { listeningBubble }
                if isRecognizing { recognizingOverlay }
                if let toastMessage { toastView(toastMessage) }
                micButton.padding(.bottom, 24)
                    .alert("加一项", isPresented: $showingAdd) {
                        TextField("食材名", text: $addText)
                        Button("添加") { addManually() }
                        Button("取消", role: .cancel) {}
                    }
            }
            .navigationTitle("本周采购")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingCamera = true } label: {
                        Image(systemName: "doc.text.viewfinder")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { addText = ""; showingAdd = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { image in recognizeReceipt(image) }
                    .ignoresSafeArea()
            }
            .sheet(item: $parsedReceipt) { receipt in
                ReceiptReviewView(parsed: receipt) { result in
                    presentToast(result)
                }
            }
            .onAppear { speech.requestAuthorization() }
        }
    }

    @ViewBuilder
    private var listOrEmpty: some View {
        if items.isEmpty {
            ContentUnavailableView("清单是空的", systemImage: "cart",
                                   description: Text("长按下方麦克风，说一句要买什么"))
        } else {
            List {
                ForEach(grouped, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.items) { item in
                            HStack {
                                Text(item.name)
                                Spacer()
                                Button {
                                    withAnimation { GroceryActions.markBought(item) }
                                } label: {
                                    Image(systemName: "circle")
                                        .font(.title3).foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .swipeActions(edge: .leading) {
                                Button { pickingStoreFor = item } label: {
                                    Label("归店", systemImage: "mappin.and.ellipse")
                                }.tint(.blue)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    GroceryActions.removeFromList(item, in: context)
                                } label: { Label("删除", systemImage: "trash") }
                                Button {
                                    renameText = item.name
                                    renamingGrocery = item
                                } label: { Label("编辑", systemImage: "pencil") }.tint(.orange)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var listeningBubble: some View {
        Text(speech.transcript.isEmpty ? "正在倾听…" : speech.transcript)
            .padding(12)
            .background(.thinMaterial, in: Capsule())
            .padding(.bottom, 100)
            .transition(.opacity)
    }

    private var recognizingOverlay: some View {
        ProgressView("识别小票中…")
            .padding(20)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.bottom, 100)
            .transition(.opacity)
    }

    private func toastView(_ msg: String) -> some View {
        HStack {
            Text(msg).font(.subheadline)
            if undoAction != nil {
                Spacer()
                Button("撤销") {
                    undoAction?()
                    withAnimation { toastMessage = nil; undoAction = nil }
                }.font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.bottom, 100)
        .transition(.opacity)
    }

    private var micButton: some View {
        Image(systemName: "mic.fill")
            .font(.title)
            .foregroundStyle(.white)
            .frame(width: 64, height: 64)
            .background(speech.isRecording ? Color.red : Color.accentColor, in: Circle())
            .shadow(radius: 6)
            .scaleEffect(speech.isRecording ? 1.1 : 1.0)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !speech.isRecording else { return }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation { speech.startRecording() }
                    }
                    .onEnded { _ in
                        let text = speech.stopRecording()
                        let command = VoiceCommandParser.parse(text)
                        let result = GroceryActions.perform(command, in: context)
                        presentToast(result)
                    }
            )
    }

    private func addManually() {
        let name = addText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let result = GroceryActions.perform(.add([name]), in: context)
        presentToast(result)
        addText = ""
    }

    // 拍小票：取图后本地 OCR + 规则解析，再弹「预览校对页」让用户确认
    private func recognizeReceipt(_ image: UIImage) {
        isRecognizing = true
        Task {
            let lines = await ReceiptOCR.recognize(image)
            let parsed = ReceiptParser.parse(lines: lines)
            isRecognizing = false
            parsedReceipt = parsed
        }
    }

    private func presentToast(_ result: ActionResult) {
        guard !result.message.isEmpty else { return }
        toastID += 1
        let myID = toastID
        withAnimation { toastMessage = result.message; undoAction = result.undo }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if toastID == myID {
                withAnimation { toastMessage = nil; undoAction = nil }
            }
        }
    }
}

// MARK: - 归店选择

struct StorePickerSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Supermarket.name) private var stores: [Supermarket]
    let grocery: Grocery
    @State private var newName = ""
    @State private var renamingStore: Supermarket?
    @State private var renameStoreText = ""

    var body: some View {
        NavigationStack {
            List {
                Button {
                    grocery.store = nil; grocery.isStorePinned = true; dismiss()
                } label: {
                    Label("不限超市", systemImage: grocery.store == nil ? "checkmark.circle.fill" : "circle")
                }

                Section("超市") {
                    ForEach(stores) { s in
                        Button {
                            grocery.store = s; grocery.isStorePinned = true; dismiss()
                        } label: {
                            HStack {
                                Text(s.name)
                                Spacer()
                                if grocery.store == s { Image(systemName: "checkmark") }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                if grocery.store === s { grocery.store = nil }
                                GroceryActions.deleteSupermarket(s, in: context)
                            } label: { Label("删除", systemImage: "trash") }
                            Button {
                                renameStoreText = s.name
                                renamingStore = s
                            } label: { Label("重命名", systemImage: "pencil") }.tint(.orange)
                        }
                    }
                }

                Section("新建超市") {
                    HStack {
                        TextField("如 Whole Foods / 中超", text: $newName)
                        Button("添加") {
                            let t = newName.trimmingCharacters(in: .whitespaces)
                            guard !t.isEmpty else { return }
                            let s = Supermarket(name: t)
                            context.insert(s)
                            grocery.store = s; grocery.isStorePinned = true
                            newName = ""; dismiss()
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle("归到哪家店")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
            .alert("重命名超市", isPresented: Binding(
                get: { renamingStore != nil },
                set: { if !$0 { renamingStore = nil } })) {
                TextField("超市名", text: $renameStoreText)
                Button("保存") {
                    if let s = renamingStore {
                        GroceryActions.renameSupermarket(s, to: renameStoreText, in: context)
                    }
                    renamingStore = nil
                }
                Button("取消", role: .cancel) { renamingStore = nil }
            }
        }
    }
}
