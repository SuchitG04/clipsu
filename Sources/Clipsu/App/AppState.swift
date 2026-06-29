import AppKit
import Combine
import ClipsuCore

/// Vim input contexts. Only meaningful when `settings.vimEnabled` is on.
enum InputMode: Equatable {
    case normal
    case search
}

/// The single source of truth for the UI: holds the visible item list, search/filter
/// state and selection, and exposes every user action (paste, copy, pin, delete, …).
@MainActor
final class AppState: ObservableObject {
    let database: Database
    let imageStore: ImageStore
    let settings: AppSettings
    private let ocr: OCRService
    private let paste = PasteService()

    @Published var items: [ClipboardItem] = []
    @Published var query: String = ""
    @Published var filter: ClipFilter = .all
    @Published var selectedID: Int64?
    @Published var editingItem: ClipboardItem?
    @Published var editingText: String = ""
    @Published var quickLookItem: ClipboardItem?
    @Published var toast: String?

    // ⌘K actions menu.
    @Published var showingActions = false
    @Published var actionIndex = 0

    // Vim mode.
    @Published var inputMode: InputMode = .normal
    @Published var pendingOperator: Character?   // first key of gg / dd / yy
    private var pendingWorkItem: DispatchWorkItem?

    var vimEnabled: Bool { settings.vimEnabled }
    /// Whether the search field should hold focus: always (non-vim) or only in Search mode (vim).
    var shouldFocusSearch: Bool { !settings.vimEnabled || inputMode == .search }

    /// Bumped to ask the view layer to refocus the search field (panel re-shown).
    @Published var focusNonce = 0
    func requestSearchFocus() { focusNonce += 1 }

    /// Wired by AppDelegate so actions can drive the window + monitor.
    var hidePanel: (() -> Void)?
    var acknowledgePasteboardWrite: (() -> Void)?
    var onNeedsAccessibility: (() -> Void)?

    private var cancellables = Set<AnyCancellable>()
    private var toastWorkItem: DispatchWorkItem?

    init(database: Database, imageStore: ImageStore, ocr: OCRService, settings: AppSettings) {
        self.database = database
        self.imageStore = imageStore
        self.ocr = ocr
        self.settings = settings

        // Reload on filter change; receive on the main runloop so the @Published value is
        // actually updated before reload() reads it (Published emits in willSet).
        $filter
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)

        $query
            .removeDuplicates()
            .debounce(for: .milliseconds(80), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)

        reload()
    }

    // MARK: - Loading

    func reload() {
        let filter = self.filter
        let query = self.query
        let db = self.database
        DispatchQueue.global(qos: .userInitiated).async {
            let fetched = (try? db.fetch(filter: filter, search: query, limit: 500)) ?? []
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.items = fetched
                // Keep selection valid; default to the first row.
                if self.selectedID == nil || !fetched.contains(where: { $0.id == self.selectedID }) {
                    self.selectedID = fetched.first?.id
                }
            }
        }
    }

    var selectedItem: ClipboardItem? {
        guard let id = selectedID else { return nil }
        return items.first { $0.id == id }
    }

    /// Called when the panel is shown: reset to a clean state.
    func prepareForPresentation() {
        query = ""
        filter = .all
        showingActions = false
        clearPending()
        inputMode = settings.vimEnabled ? .normal : .search
        selectedID = nil   // always start on the first row when the panel opens
        reload()
    }

    // MARK: - Vim mode

    func enterSearch() { inputMode = .search }
    func enterNormal() { clearPending(); inputMode = .normal }

    /// Buffers the first key of a two-stroke command (g/d/y), auto-cancelling after a short delay.
    func setPending(_ key: Character) {
        pendingOperator = key
        pendingWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.pendingOperator = nil }
        pendingWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    func clearPending() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        pendingOperator = nil
    }

    func selectFirst() { selectedID = items.first?.id }
    func selectLast() { selectedID = items.last?.id }

    func nextFilter() {
        let all = ClipFilter.allCases
        if let i = all.firstIndex(of: filter) { filter = all[(i + 1) % all.count] }
    }

    func previousFilter() {
        let all = ClipFilter.allCases
        if let i = all.firstIndex(of: filter) { filter = all[(i - 1 + all.count) % all.count] }
    }

    func actionsFirst() { actionIndex = 0 }
    func actionsLast() { actionIndex = max(0, currentActions.count - 1) }

    // MARK: - Selection helpers (keyboard nav)

    func selectNext() {
        guard let id = selectedID, let idx = items.firstIndex(where: { $0.id == id }) else {
            selectedID = items.first?.id; return
        }
        if idx + 1 < items.count { selectedID = items[idx + 1].id }
    }

    func selectPrevious() {
        guard let id = selectedID, let idx = items.firstIndex(where: { $0.id == id }) else {
            selectedID = items.first?.id; return
        }
        if idx > 0 { selectedID = items[idx - 1].id }
    }

    // MARK: - Actions menu (⌘K)

    var currentActions: [ClipAction] {
        guard let item = selectedItem else { return [] }
        return ClipAction.actions(for: item)
    }

    func toggleActions() {
        if showingActions { showingActions = false }
        else if selectedItem != nil { actionIndex = 0; showingActions = true }
    }

    func closeActions() { showingActions = false }

    func actionsNext() {
        let count = currentActions.count
        guard count > 0 else { return }
        actionIndex = min(actionIndex + 1, count - 1)
    }

    func actionsPrevious() {
        guard !currentActions.isEmpty else { return }
        actionIndex = max(actionIndex - 1, 0)
    }

    func performSelectedAction() {
        let actions = currentActions
        guard actions.indices.contains(actionIndex), let item = selectedItem else { return }
        showingActions = false
        actions[actionIndex].perform(on: item, appState: self)
    }

    /// Run a specific action against the current selection (used by global key shortcuts).
    func perform(_ action: ClipAction) {
        guard let item = selectedItem, action.applies(to: item) else { return }
        showingActions = false
        action.perform(on: item, appState: self)
    }

    // MARK: - Primary actions

    /// Paste-back: place on pasteboard, close panel, synthesise ⌘V.
    func paste(_ item: ClipboardItem, plainOnly: Bool = false) {
        paste.place(item, plainOnly: plainOnly)
        acknowledgePasteboardWrite?()
        try? database.bumpUsage(id: item.id)

        // Without Accessibility we can't synthesise ⌘V. Still copy (so manual ⌘V works),
        // hide the panel, and guide the user to grant permission.
        guard paste.hasAccessibility else {
            hidePanel?()
            onNeedsAccessibility?()
            reload()
            return
        }

        hidePanel?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.paste.synthesizePaste()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.reload() }
    }

    /// The default action for ↵, honouring the user's Enter-behaviour setting.
    func activate(_ item: ClipboardItem) {
        switch settings.enterBehavior {
        case .alwaysPaste:
            paste(item)
        case .smart:
            if item.kind == .image { openImage(item) } else { paste(item) }
        }
    }

    func copyToClipboard(_ item: ClipboardItem) {
        paste.place(item)
        acknowledgePasteboardWrite?()
        try? database.bumpUsage(id: item.id)
        showToast("Copied")
        reload()
    }

    func copyPlainText(_ item: ClipboardItem) {
        paste.place(item, plainOnly: true)
        acknowledgePasteboardWrite?()
        showToast("Copied as plain text")
    }

    func togglePin(_ item: ClipboardItem) {
        try? database.setPinned(id: item.id, !item.pinned)
        reload()
    }

    func delete(_ item: ClipboardItem) {
        // If we're deleting the selected row, move selection to its neighbour
        // (next, else previous) so it doesn't jump back to the top on reload.
        if item.id == selectedID, let idx = items.firstIndex(where: { $0.id == item.id }) {
            let neighbour = idx + 1 < items.count ? items[idx + 1] : (idx > 0 ? items[idx - 1] : nil)
            selectedID = neighbour?.id
        }
        try? database.delete(id: item.id)
        imageStore.deleteFiles([item.imagePath, item.thumbPath].compactMap { $0 })
        reload()
    }

    func clearAll() {
        let paths = (try? database.allReferencedPaths()) ?? []
        try? database.deleteAll()
        imageStore.deleteFiles(Array(paths))
        reload()
    }

    // MARK: - Edit (creates a new entry)

    func beginEdit(_ item: ClipboardItem) {
        editingText = item.plainText ?? ""
        editingItem = item
    }

    func cancelEdit() { editingItem = nil }

    func commitEdit() {
        guard let original = editingItem else { return }
        let newText = editingText
        guard !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let kind = ContentClassifier.kind(forPlainText: newText)
        let item = ClipboardItem(
            kind: kind,
            plainText: newText,
            sourceBundleID: original.sourceBundleID,
            sourceAppName: original.sourceAppName,
            contentHash: Hashing.sha256(newText),
            byteSize: newText.utf8.count
        )
        if let inserted = try? database.insert(item) {
            selectedID = inserted.id
        }
        editingItem = nil
        reload()
    }

    // MARK: - Quick Look (in-app image lightbox)

    func quickLook(_ item: ClipboardItem) {
        guard item.kind == .image else { return }
        quickLookItem = item
    }

    func closeQuickLook() { quickLookItem = nil }

    // MARK: - Open / reveal

    func openInBrowser(_ item: ClipboardItem) {
        guard let text = item.plainText, let url = ContentClassifier.openableURL(from: text) else { return }
        NSWorkspace.shared.open(url)
        hidePanel?()
    }

    func openImage(_ item: ClipboardItem) {
        guard let path = item.imagePath else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
        hidePanel?()
    }

    func saveImage(_ item: ClipboardItem) {
        guard let path = item.imagePath else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Image.png"
        panel.allowedContentTypes = [.png]
        if panel.runModal() == .OK, let dest = panel.url {
            try? FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: dest)
        }
    }

    func copyOCRText(_ item: ClipboardItem) {
        guard let text = item.ocrText, !text.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        acknowledgePasteboardWrite?()
        showToast("Copied recognized text")
    }

    func revealSourceApp(_ item: ClipboardItem) {
        guard let bid = item.sourceBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Toast

    func showToast(_ message: String) {
        toast = message
        toastWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }
}
