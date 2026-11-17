import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Combine

enum Stage: String, Codable, CaseIterable, Identifiable {
    case todo = "To do", doing = "In progress", done = "Done"
    var id: String { rawValue }
    var icon: String { switch self { case .todo: return "circle"; case .doing: return "circle.lefthalf.filled"; case .done: return "checkmark.circle.fill" } }
    var color: Color { switch self { case .todo: return .secondary; case .doing: return .mint; case .done: return .mint } }
}
struct Task: Codable, Identifiable {
    var id = UUID()
    var title: String
    var stage: Stage = .todo
    var created = Date()
    var important: Bool? = false
}
@MainActor final class Store: ObservableObject {
    @Published var tasks: [Task] = [] { didSet { save() } }
    private let key = "notch.tasks.v1"
    @Published var previous: [Task]?
    @Published var undoLabel = ""
    func checkpoint(_ label: String) { previous = tasks; undoLabel = label }
    func undo() { guard let snapshot = previous else { return }; tasks = snapshot; previous = nil }
    func clear(completedOnly: Bool) { checkpoint(completedOnly ? "Completed tasks cleared" : "Board cleared"); tasks.removeAll { !completedOnly || $0.stage == .done } }
    func edit(_ task: Task, title: String, important: Bool) {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let i = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        checkpoint("Task updated"); tasks[i].title = value; tasks[i].important = important
    }
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults; if let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode([Task].self, from: data) { tasks = saved } }
    func save() { if let data = try? JSONEncoder().encode(tasks) { defaults.set(data, forKey: key) } }
    func add(_ title: String) { let value = title.trimmingCharacters(in: .whitespacesAndNewlines); guard !value.isEmpty else { return }; checkpoint("Task added"); tasks.insert(Task(title: value), at: 0) }
    func move(_ task: Task, to stage: Stage) { if let i = tasks.firstIndex(where: { $0.id == task.id }) { checkpoint("Task moved"); tasks[i].stage = stage } }
    func delete(_ task: Task) { checkpoint("Task deleted"); tasks.removeAll { $0.id == task.id } }
}
@main struct DaymarkApp: App {
    @NSApplicationDelegateAdaptor(StatusController.self) private var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor final class StatusController: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let store = Store()
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private var subscription: AnyCancellable?
    private var timer: Timer?
    private var title = ""
    private var started = Date()
    private var statusWidth: CGFloat = 20

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(toggleBoard)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 820, height: 600)
        popover.contentViewController = NSHostingController(rootView: Board().environmentObject(store))
        subscription = store.$tasks.sink { [weak self] tasks in
            guard let self else { return }
            let next = tasks.first(where: { $0.stage == .doing })?.title ?? ""
            if next != self.title { self.title = next; self.started = Date() }
            self.drawTitle()
        }
        timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.drawTitle() }
        }
        RunLoop.main.add(timer!, forMode: .common)
        drawTitle()
    }

    @objc private func toggleBoard() {
        guard let button = item.button else { return }
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            popover.performClose(nil)
            let menu = NSMenu(title: "Daymark")
            menu.autoenablesItems = false
            func entry(_ title: String, _ action: Selector, enabled: Bool = true) {
                let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
                entry.target = self
                entry.isEnabled = enabled
                menu.addItem(entry)
            }
            entry("Open board", #selector(openBoard))
            menu.addItem(.separator())
            entry("Undo last change", #selector(undoChange), enabled: store.previous != nil)
            entry("Clear completed", #selector(clearCompleted), enabled: store.tasks.contains { $0.stage == .done })
            menu.addItem(.separator())
            entry("Quit Daymark", #selector(quitApp))
            NSMenu.popUpContextMenu(menu, with: event, for: button)
            return
        }
        if popover.isShown { popover.performClose(nil) }
        else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc private func openBoard() {
        guard let button = item.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    @objc private func undoChange() { store.undo() }
    @objc private func clearCompleted() { store.clear(completedOnly: true) }
    @objc private func quitApp() { NSApp.terminate(nil) }

    func popoverDidClose(_ notification: Notification) { drawTitle() }

    private func drawTitle() {
        guard let button = item?.button else { return }
        let font = NSFont.menuBarFont(ofSize: 13)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let textWidth = ceil((title as NSString).size(withAttributes: attributes).width)
        // Keep the popover anchor fixed throughout a drag and while editing.
        if !popover.isShown { statusWidth = title.isEmpty ? 20 : min(textWidth, 140) + 34 }
        let visibleWidth = max(0, statusWidth - 34)
        let image = NSImage(size: NSSize(width: statusWidth, height: 22))
        image.lockFocus()
        if let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(1.7)
            context.setLineCap(.round)
            context.addPath(DaymarkSymbol.path(in: CGRect(x: 2, y: 3, width: 16, height: 16)))
            context.strokePath()
            context.restoreGState()
        }
        if !title.isEmpty {
            NSGraphicsContext.saveGraphicsState()
            let textRect = NSRect(x: 26, y: 0, width: visibleWidth, height: 22)
            NSBezierPath(rect: textRect).addClip()
            // Pan only overflowing text, pausing at each end so the title stays readable.
            let overflow = max(0, textWidth - visibleWidth)
            let duration = overflow / 24
            let phase = Date().timeIntervalSince(started).truncatingRemainder(dividingBy: 2 * duration + 3)
            var travel: CGFloat = 0
            if overflow > 0 && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                if phase < 1.5 { travel = 0 }
                else if phase < 1.5 + duration { travel = (phase - 1.5) * 24 }
                else if phase < 3 + duration { travel = overflow }
                else { travel = max(0, overflow - (phase - 3 - duration) * 24) }
            }
            let textHeight = (title as NSString).size(withAttributes: attributes).height
            let y = floor((22 - textHeight) / 2)
            (title as NSString).draw(at: NSPoint(x: textRect.minX - travel, y: y), withAttributes: attributes)
            NSGraphicsContext.restoreGraphicsState()
        }
        image.unlockFocus()
        image.isTemplate = true
        button.image = image
        button.toolTip = title.isEmpty ? "Daymark · Open task board" : title
        button.setAccessibilityLabel(title.isEmpty ? "Daymark task board" : "Daymark: " + title)
    }
}
// A rising arc and a horizon: the same two strokes at every size.
enum DaymarkSymbol {
    static func path(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        path.move(to: point(0.20, 0.43))
        path.addCurve(to: point(0.80, 0.43), control1: point(0.20, 0.91), control2: point(0.80, 0.91))
        path.move(to: point(0.12, 0.23))
        path.addLine(to: point(0.88, 0.23))
        return path
    }
}
struct BrandMark: View {
    var body: some View {
        Canvas { context, size in
            // AppKit and SwiftUI use opposite vertical coordinate directions.
            var flip = CGAffineTransform(translationX: 0, y: size.height).scaledBy(x: 1, y: -1)
            let path = DaymarkSymbol.path(in: CGRect(origin: .zero, size: size)).copy(using: &flip)!
            context.stroke(Path(path), with: .color(.mint), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }.frame(width: 22, height: 22).accessibilityLabel("Daymark").help("Daymark")
    }
}

struct Board: View {
    @EnvironmentObject var store: Store
    @State private var title = ""
    @State private var search = ""
    @State private var editing: Task?
    @State private var confirmClear = false
    @State private var celebration: Date?
    @FocusState private var focused: Bool
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dropTarget: Stage?
    private var completed: Int { store.tasks.filter { $0.stage == .done }.count }
    private var openCount: Int { store.tasks.count - completed }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            composer
            toolbar
            HStack(alignment: .top, spacing: 12) {
                ForEach(Stage.allCases) { stage in column(stage) }
            }.padding(.horizontal, 22).padding(.bottom, 18)
            footer
        }
        .frame(width: 820, height: 600)
        .background(.regularMaterial)
        .tint(.mint)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: dropTarget)
        .sheet(item: $editing) { task in TaskEditor(task: task).environmentObject(store) }
        .alert("Clear every task?", isPresented: $confirmClear) {
            Button("Cancel", role: .cancel) { }
            Button("Clear all tasks", role: .destructive) { store.clear(completedOnly: false) }
        } message: { Text("This removes all \(store.tasks.count) tasks from your board. You can undo this immediately afterward.") }
        .background {
            Group {
                Button("") { focused = true }.keyboardShortcut("n")
                Button("") { searchFocused = true }.keyboardShortcut("f")
                Button("") { store.undo() }.keyboardShortcut("z").disabled(store.previous == nil)
            }.hidden()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            BrandMark()
            Spacer()
            if !store.tasks.isEmpty {
                Text("\(completed) of \(store.tasks.count) complete")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
            Menu {
                Button("Export tasks…", action: exportTasks).disabled(store.tasks.isEmpty)
                Divider()
                Button("Quit Daymark") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
            } label: { Image(systemName: "ellipsis.circle").font(.title3) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Daymark options")
        }.padding(.horizontal, 22).padding(.vertical, 12)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus").font(.system(size: 16, weight: .medium)).foregroundStyle(Color.mint)
            TextField("What would you like to get done?", text: $title)
                .textFieldStyle(.plain).font(.system(size: 14)).focused($focused).onSubmit(add)
                .accessibilityLabel("New task")
            Button(action: add) { Text("Add task  ↩").font(.system(size: 12, weight: .semibold)) }
                .buttonStyle(.borderedProminent).controlSize(.regular)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.padding(12)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(focused ? Color.mint.opacity(0.7) : Color.primary.opacity(0.10)))
            .overlay(alignment: .trailing) {
                if let celebration {
                    if reduceMotion {
                        Label("Added", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Color.mint)
                            .padding(7).background(.regularMaterial, in: Capsule())
                            .offset(y: -30)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    } else {
                        AddConfetti(started: celebration)
                            .frame(width: 220, height: 140).offset(x: 22, y: -12)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
            }
            .padding(.horizontal, 22)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find a task", text: $search).textFieldStyle(.plain).focused($searchFocused).accessibilityLabel("Search tasks")
                .frame(width: 145)
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).help("Clear search")
            }
            Spacer()
            Button("Clear completed") { store.clear(completedOnly: true) }.disabled(completed == 0)
            Divider().frame(height: 12)
            Button(role: .destructive) { confirmClear = true } label: { Label("Clear all", systemImage: "trash") }.disabled(store.tasks.isEmpty)
        }.font(.system(size: 11)).buttonStyle(.plain).padding(.horizontal, 24).padding(.vertical, 16)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.5)
            HStack(spacing: 7) {
                Circle().fill(Color.mint).frame(width: 5, height: 5)
                Text("\(openCount) open")
                if store.previous != nil {
                    Text("·").foregroundStyle(.tertiary)
                    Text(store.undoLabel).lineLimit(1)
                    Button("Undo") { store.undo() }.buttonStyle(.plain).foregroundStyle(Color.mint).help("Undo last change (⌘Z)")
                }
                Spacer(minLength: 8)
                Image(systemName: "lock").font(.system(size: 9))
                Text("Saved on this Mac")
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 13)
        }
    }

    private func add() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        store.add(title)
        title = ""
        focused = true
        let started = Date()
        celebration = started
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
            if celebration == started { celebration = nil }
        }
    }

    private func column(_ stage: Stage) -> some View {
        let all = store.tasks.filter { $0.stage == stage }
        let items = all.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
            .sorted { ($0.important == true ? 1 : 0) > ($1.important == true ? 1 : 0) }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: stage.icon).foregroundStyle(stage.color)
                Text(stage.rawValue).fontWeight(.semibold)
                Text("\(all.count)").font(.system(size: 10, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 6).padding(.vertical, 3).background(Color.primary.opacity(0.06), in: Capsule())
                Spacer(minLength: 0)
            }.font(.system(size: 12)).padding(.horizontal, 3).padding(.top, 3)
            ScrollView {
                LazyVStack(spacing: 8) {
                    if items.isEmpty { emptyState(stage, searching: !search.isEmpty) }
                    ForEach(items) { task in taskCard(task) }
                }.padding(.bottom, 4)
            }.frame(maxHeight: .infinity)
        }
        .padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(dropTarget == stage ? Color.mint.opacity(0.10) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(dropTarget == stage ? Color.mint.opacity(0.6) : Color.primary.opacity(0.04)))
        .contentShape(Rectangle())
        .onDrop(of: [UTType.plainText], isTargeted: Binding(get: { dropTarget == stage }, set: { active in
            if active { dropTarget = stage } else if dropTarget == stage { dropTarget = nil }
        })) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: String.self) { value, _ in
                guard let value, let id = UUID(uuidString: value) else { return }
                DispatchQueue.main.async {
                    if let task = store.tasks.first(where: { $0.id == id }) { dropTarget = nil; store.move(task, to: stage) }
                }
            }
            return true
        }
    }

    private func emptyState(_ stage: Stage, searching: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: searching ? "magnifyingglass" : stage == .todo ? "text.badge.plus" : stage == .doing ? "play.circle" : "checkmark.seal")
                .font(.system(size: 21, weight: .light)).foregroundStyle(.tertiary)
            Text(searching ? "No matching tasks" : stage == .todo ? "Make a little room" : stage == .doing ? "One thing at a time" : "Progress lives here")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Text(searching ? "Try a different search." : stage == .todo ? "Capture your next task above." : stage == .doing ? "Drag a task here to focus on it." : "Check off a task to see it here.")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6).padding(.top, 22)
    }

    private func taskCard(_ task: Task) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Button { store.move(task, to: task.stage == .done ? .todo : .done) } label: {
                Image(systemName: task.stage == .done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16)).foregroundStyle(task.stage == .done ? Color.mint : Color.secondary)
            }.buttonStyle(.plain).help(task.stage == .done ? "Reopen task" : "Complete task")
            VStack(alignment: .leading, spacing: 8) {
                Text(task.title).font(.system(size: 13, weight: .medium)).lineSpacing(3)
                    .foregroundStyle(task.stage == .done ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                if task.important == true {
                    Label("Priority", systemImage: "flag.fill").font(.system(size: 9, weight: .medium)).foregroundStyle(Color.mint)
                }
            }.onTapGesture(count: 2) { editing = task }
            Menu {
                Button("Edit task…") { editing = task }
                Button(task.important == true ? "Remove priority" : "Mark as priority") {
                    store.edit(task, title: task.title, important: task.important != true)
                }
                Divider()
                ForEach(Stage.allCases) { destination in
                    Button("Move to \(destination.rawValue)") { store.move(task, to: destination) }.disabled(task.stage == destination)
                }
                Divider()
                Button("Delete task", role: .destructive) { store.delete(task) }
            } label: { Image(systemName: "ellipsis").foregroundStyle(.secondary) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Task options")
        }.padding(12).background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.05)))
            .contentShape(Rectangle()).onDrag { NSItemProvider(object: task.id.uuidString as NSString) }
    }

    private func exportTasks() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Daymark tasks.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(store.tasks).write(to: url, options: .atomic)
        } catch { NSAlert(error: error).runModal() }
    }
}

struct AddConfetti: View {
    let started: Date
    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = max(0, min(1, timeline.date.timeIntervalSince(started) / 0.9))
            Canvas { context, size in
                let colors: [Color] = [.mint, Color(red: 0.72, green: 0.92, blue: 0.86), Color(red: 0.92, green: 0.83, blue: 0.56)]
                for index in 0..<20 {
                    let seed = Double(index)
                    let angle = -Double.pi + 0.22 + seed / 19 * (Double.pi - 0.44)
                    let speed = 65 + Double((index * 37) % 65)
                    let x = size.width * 0.68 + cos(angle) * speed * elapsed
                    let y = size.height * 0.63 + sin(angle) * speed * elapsed + 88 * elapsed * elapsed
                    var particle = context
                    particle.opacity = min(1, (1 - elapsed) * 2.5)
                    particle.translateBy(x: x, y: y)
                    particle.rotate(by: .radians(seed + elapsed * (index.isMultiple(of: 2) ? 8 : -8)))
                    let rect = CGRect(x: -2, y: -3, width: 4, height: index.isMultiple(of: 3) ? 4 : 7)
                    particle.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(colors[index % colors.count]))
                }
            }
        }
    }
}

struct TaskEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let task: Task
    @State private var title: String
    @State private var important: Bool
    @FocusState private var focused: Bool
    init(task: Task) {
        self.task = task
        _title = State(initialValue: task.title)
        _important = State(initialValue: task.important == true)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Edit task").font(.system(size: 20, weight: .semibold, design: .rounded))
            TextField("Task title", text: $title, axis: .vertical).lineLimit(3...6).textFieldStyle(.roundedBorder).focused($focused)
            Toggle("Mark as priority", isOn: $important).toggleStyle(.checkbox)
            HStack {
                Text("Added \(task.created.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save changes") { store.edit(task, title: title, important: important); dismiss() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 440).tint(.mint).onAppear { focused = true }
    }
}
