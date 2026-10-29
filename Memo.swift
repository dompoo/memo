import Carbon
import SwiftUI

@main
struct MemoApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    init() {
        HotKey.shared.register(Action.open.shortcut.code, Action.open.shortcut.mods)
    }

    // 메모창은 직접 띄우는 패널이라 씬은 비워둔다. 편집 메뉴(복사·붙여넣기·실행 취소)는 SwiftUI가 만들어준다.
    // 설정 열기는 메모창 단축키로 처리해서 기본 설정 메뉴(빈 창)는 뺀다
    var body: some Scene {
        Settings { EmptyView() }
            .commands { CommandGroup(replacing: .appSettings) {} }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    // 실행하면 바로 띄우고, 실행 중에 다시 실행(Raycast·Spotlight)하면 여닫는다
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Memo")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(click)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        toggleMemoWindow()
    }

    // 메뉴바 아이콘을 누르면 메모를 여닫고, 오른쪽 클릭하면 단축키를 모르는 사람도 쓸 수 있게 설정·도움말·종료 메뉴를 띄운다
    @objc func click() {
        guard NSApp.currentEvent?.type == .rightMouseUp, let b = statusItem.button else { return toggleMemoWindow() }
        let menu = NSMenu()
        menu.addItem(withTitle: "설정…", action: #selector(settings), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Markdown 도움말", action: #selector(help), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Memo 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: b.bounds.height + 4), in: b)
    }

    @objc func settings() { showSettings() }
    @objc func help() { showHelp() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        toggleMemoWindow()
        return false
    }
}

let notesDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "Memo")
func noteFile(_ i: Int) -> URL { notesDir.appending(path: "\(i + 1).md") }

struct ContentView: View {
    @State private var notes = (0..<5).map { (try? String(contentsOf: noteFile($0), encoding: .utf8)) ?? "" }
    @AppStorage("selected") private var sel = 0  // 메모 전환 단축키는 이 값을 바꾼다
    @AppStorage("fontFamily") private var fontFamily = ""
    @State private var saveFailed = false

    var body: some View {
        VStack(spacing: 0) {
            // 타이틀바 자리에 메모 표시. 내용 있으면 채운 점, 빈 메모는 빈 고리, 지금 메모는 크고 진하게
            HStack(spacing: 10) {
                ForEach(notes.indices, id: \.self) { i in
                    Button { sel = i } label: {
                        let color = sel == i ? Color.primary.opacity(0.7) : Color.gray.opacity(0.5)
                        Circle()
                            .fill(notes[i].isEmpty ? Color.clear : color)
                            .overlay(Circle().strokeBorder(color, lineWidth: 1.5))
                            .frame(width: sel == i ? 12 : 9, height: sel == i ? 12 : 9)
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            LiveEditor(text: $notes[sel], fontFamily: fontFamily)
        }
        .overlay(alignment: .topTrailing) {
            if saveFailed {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .help("~/Documents/Memo 저장 실패")
                    .padding(8)
            }
        }
        .ignoresSafeArea()
        .background(Color.white)
        .environment(\.colorScheme, .light)
        .onChange(of: notes, initial: true) { save() }
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)
            // 한 번도 안 쓴 메모는 빈 파일을 만들지 않는다
            for i in notes.indices where notes[i] != ((try? String(contentsOf: noteFile(i), encoding: .utf8)) ?? "") {
                try notes[i].write(to: noteFile(i), atomically: true, encoding: .utf8)
            }
            saveFailed = false
        } catch {
            saveFailed = true
        }
    }
}

// MenuBarExtra 창은 다른 앱을 누르면 닫혀서, 핫키로만 여닫는 패널을 직접 띄운다
var memoPanel: NSPanel?

@MainActor func toggleMemoWindow() {
    let onTop = UserDefaults.standard.object(forKey: "alwaysOnTop") as? Bool ?? true
    // 위에 띄우지 않으면 다른 창 뒤에 깔려 있을 수 있어서, 그땐 닫지 않고 앞으로 꺼낸다
    if let memoPanel, memoPanel.isVisible, onTop || memoPanel.isKeyWindow { return memoPanel.orderOut(nil) }
    if memoPanel == nil {
        // 빈 타이틀바를 끌어서 옮기고 가장자리로 크기를 바꾼다. 메모 표시를 타이틀바 자리에 그리려고 내용을 그 밑까지 깐다
        let p = NSPanel(contentRect: .zero, styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        let host = NSHostingController(rootView: ContentView())
        host.sizingOptions = []  // SwiftUI가 창 크기를 되돌리지 않게
        p.contentViewController = host
        p.titlebarAppearsTransparent = true
        p.backgroundColor = .white
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { p.standardWindowButton(b)?.isHidden = true }
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isReleasedWhenClosed = false
        // 옮기거나 바꾼 위치·크기를 기억한다. 처음엔 화면 가로 1/3 × 세로 절반으로 가운데
        if !p.setFrameUsingName("memo") {
            let screen = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1512, height: 944)
            p.setContentSize(NSSize(width: screen.width / 3, height: screen.height / 2))
            p.center()
        }
        p.setFrameAutosaveName("memo")
        memoPanel = p
    }
    memoPanel!.level = onTop ? .floating : .normal  // 설정창을 열면 메모가 닫히니 다시 열 때 반영하면 된다
    memoPanel!.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
}

// Carbon 전역 단축키. 손쉬운 사용 권한 없이 동작한다
final class HotKey {
    static let shared = HotKey()
    private var ref: EventHotKeyRef?

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            MainActor.assumeIsolated { toggleMemoWindow() }
            return noErr
        }, 1, &spec, nil, nil)
    }

    // code가 -1이면 해제만 한다. 다른 앱이 이미 쓰는 조합이면 false
    @discardableResult
    func register(_ code: Int, _ mods: Int) -> Bool {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        guard code >= 0 else { return true }
        return RegisterEventHotKey(UInt32(code), UInt32(mods), EventHotKeyID(signature: 0x4D454D4F, id: 1), GetApplicationEventTarget(), 0, &ref) == noErr
    }
}

func carbonMods(_ f: NSEvent.ModifierFlags) -> Int {
    (f.contains(.control) ? controlKey : 0) | (f.contains(.option) ? optionKey : 0) | (f.contains(.shift) ? shiftKey : 0) | (f.contains(.command) ? cmdKey : 0)
}

// ponytail: 키 이름은 ANSI 배열 keyCode 0~50과 방향키만 표시하고 F키 등은 #코드로 보인다
func hotKeyLabel(_ code: Int, _ mods: Int) -> String {
    guard code >= 0 else { return "클릭해서 설정" }
    let keys = Array("ASDFHGZXCV§BQWERYT123465=97-80]OU[IP↩LJ'K;\\,/NM.⇥␣`")
    return (mods & controlKey != 0 ? "⌃" : "") + (mods & optionKey != 0 ? "⌥" : "") + (mods & shiftKey != 0 ? "⇧" : "")
        + (mods & cmdKey != 0 ? "⌘" : "") + (code < keys.count ? String(keys[code]) : [123: "←", 124: "→", 125: "↓", 126: "↑"][code] ?? "#\(code)")
}

// 단축키는 keyCode + Carbon 수정키로 저장한다. code -1은 없음
struct Shortcut: Equatable {
    var code = -1, mods = 0
}

// rawValue는 UserDefaults 키 앞부분 (메모 열기는 예전 키 이름 그대로)
enum Action: String, CaseIterable {
    case open = "hotKey", settings, help, find, bold, italic, strike, highlight, checkbox, bigger, smaller, indent, outdent, lineUp, lineDown,
         copyLine, cutLine, note1, note2, note3, note4, note5

    // 메모 전환이면 몇 번째 메모인지
    var note: Int? { [Action.note1, .note2, .note3, .note4, .note5].firstIndex(of: self) }

    var title: String {
        switch self {
        case .open: "메모 열기 (전역)"
        case .settings: "설정 열기"
        case .help: "Markdown 도움말"
        case .find: "찾기"
        case .bold: "굵게"
        case .italic: "기울임"
        case .strike: "취소선"
        case .highlight: "하이라이트"
        case .checkbox: "체크박스 만들기·체크"
        case .bigger: "글자 크게"
        case .smaller: "글자 작게"
        case .indent: "목록 들여쓰기"
        case .outdent: "목록 내어쓰기"
        case .lineUp: "줄 위로 옮기기"
        case .lineDown: "줄 아래로 옮기기"
        case .copyLine: "복사 (선택 없으면 줄)"
        case .cutLine: "잘라내기 (선택 없으면 줄)"
        case .note1, .note2, .note3, .note4, .note5: "메모 \(note! + 1)"
        }
    }

    var standard: Shortcut {
        switch self {
        case .open: Shortcut()
        case .settings: Shortcut(code: 43, mods: cmdKey)
        case .help: Shortcut(code: 44, mods: cmdKey | shiftKey)  // ⌘? (macOS 도움말 기본 키)
        case .find: Shortcut(code: 3, mods: cmdKey)
        case .bold: Shortcut(code: 11, mods: cmdKey)
        case .italic: Shortcut(code: 34, mods: cmdKey)
        case .strike: Shortcut(code: 7, mods: cmdKey | shiftKey)
        case .highlight: Shortcut(code: 4, mods: cmdKey | shiftKey)
        case .checkbox: Shortcut(code: 37, mods: cmdKey)
        case .bigger: Shortcut(code: 24, mods: cmdKey)
        case .smaller: Shortcut(code: 27, mods: cmdKey)
        case .indent: Shortcut(code: 48, mods: 0)
        case .outdent: Shortcut(code: 48, mods: shiftKey)
        case .lineUp: Shortcut(code: 126, mods: optionKey)
        case .lineDown: Shortcut(code: 125, mods: optionKey)
        case .copyLine: Shortcut(code: 8, mods: cmdKey)
        case .cutLine: Shortcut(code: 7, mods: cmdKey)
        case .note1, .note2, .note3, .note4, .note5: Shortcut(code: [18, 19, 20, 21, 23][note!], mods: cmdKey)  // ⌘1~⌘5
        }
    }

    var shortcut: Shortcut {
        get {
            let d = UserDefaults.standard
            return Shortcut(code: d.object(forKey: rawValue + "Code") as? Int ?? standard.code, mods: d.object(forKey: rawValue + "Mods") as? Int ?? standard.mods)
        }
        nonmutating set {
            UserDefaults.standard.set(newValue.code, forKey: rawValue + "Code")
            UserDefaults.standard.set(newValue.mods, forKey: rawValue + "Mods")
        }
    }
}

// SwiftUI Settings scene은 메뉴바 앱에서 앞으로 뜨지 않아서 창을 직접 띄운다
var settingsWindow: NSWindow?

@MainActor func showSettings() {
    memoPanel?.orderOut(nil)  // 메모창이 floating이라 설정창을 가리지 않게 닫는다
    if settingsWindow == nil {
        settingsWindow = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
        settingsWindow!.title = "Memo 설정"
        settingsWindow!.isReleasedWhenClosed = false
    }
    settingsWindow!.center()
    settingsWindow!.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
}

var helpWindow: NSWindow?

// 도움말은 메모와 같은 편집기로 띄운 연습장이다. 저장하지 않고, 닫았다 열면 처음 글로 돌아간다
@MainActor func showHelp() {
    if helpWindow?.isVisible != true {
        let host = NSHostingController(rootView: HelpView())
        host.sizingOptions = []
        helpWindow = NSWindow(contentViewController: host)
        helpWindow!.title = "Markdown 도움말"
        helpWindow!.isReleasedWhenClosed = false
        helpWindow!.setContentSize(NSSize(width: 480, height: 640))
        helpWindow!.center()
    }
    helpWindow!.level = memoPanel?.level ?? .normal  // 메모창이 위에 떠 있어도 가리지 않게
    helpWindow!.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
}

struct HelpView: View {
    @State private var text = helpText()
    @AppStorage("fontFamily") private var fontFamily = ""

    var body: some View {
        LiveEditor(text: $text, fontFamily: fontFamily)
            .background(Color.white)
            .environment(\.colorScheme, .light)
    }
}

// 회색 코드 블록 안은 서식이 안 걸려서 친 글자 그대로 보인다. 그 밑에 같은 글을 둬서 어떻게 보이는지 나란히 보여준다
func helpText() -> String {
    func k(_ a: Action) -> String { hotKeyLabel(a.shortcut.code, a.shortcut.mods) }
    return """
    # Markdown 도움말
    Markdown은 기호 몇 개로 글에 서식을 다는 방법이에요. 회색 칸이 직접 치는 글자, 그 밑이 Memo에 보이는 모습이에요.
    여기는 연습장이에요. 마음대로 고쳐 보세요. 기호를 숨긴 줄도 커서를 올리면 기호가 나타나요. 창을 닫으면 처음으로 돌아가요.

    ## 제목
    줄 맨 앞에 #과 띄어쓰기를 붙여요. #이 많을수록 작아져요.
    ```
    # 큰 제목
    ## 중간 제목
    ### 작은 제목
    ```

    # 큰 제목
    ## 중간 제목
    ### 작은 제목

    ## 글자 꾸미기
    꾸밀 글자를 선택하고 단축키를 눌러도 돼요. 굵게 \(k(.bold)), 기울임 \(k(.italic)), 취소선 \(k(.strike)), 하이라이트 \(k(.highlight))
    ```
    **굵게**  *기울임*  ~~취소선~~  ==하이라이트==  `코드`
    ```

    **굵게**  *기울임*  ~~취소선~~  ==하이라이트==  `코드`

    ## 목록
    줄 맨 앞에 -와 띄어쓰기를 붙여요. 숫자와 점으로 시작하면 번호 목록이에요.
    엔터를 치면 다음 줄에도 이어지고, 빈 항목에서 한 번 더 치면 끝나요. \(k(.indent))로 한 칸 들이고 \(k(.outdent))로 내요.
    ```
    - 과일
    \t- 사과
    1. 첫째
    2. 둘째
    ```

    - 과일
    \t- 사과
    1. 첫째
    2. 둘째

    ## 할 일
    줄 맨 앞에 - [ ] 를 붙여요. 네모를 누르거나 \(k(.checkbox))를 누르면 체크돼요.
    ```
    - [ ] 장보기
    - [x] 메일 답장
    ```

    - [ ] 장보기
    - [x] 메일 답장

    ## 인용
    줄 맨 앞에 >와 띄어쓰기를 붙여요.
    ```
    > 짧은 글이 잘 읽힌다
    ```

    > 짧은 글이 잘 읽힌다

    ## 링크
    대괄호에 보일 글자를, 바로 뒤 괄호에 주소를 써요. 주소만 써도 링크가 돼요. ⌘를 누른 채 클릭하면 열려요.
    ```
    [예시 사이트](https://example.com)
    https://example.com
    ```

    [예시 사이트](https://example.com)
    https://example.com

    ## 구분선
    빈 줄에 -를 세 개 써요.
    ```
    ---
    ```

    ---

    ## 코드 블록
    줄에 ``` 만 쓴 두 줄 사이는 코드 블록이에요. 서식이 걸리지 않아서, 지금까지 회색 칸의 글자가 친 그대로 보였어요.

    ## 알아두면 편한 키
    - 줄 옮기기: \(k(.lineUp)) / \(k(.lineDown))
    - 선택 없이 복사·잘라내기하면 줄 전체: \(k(.copyLine)) / \(k(.cutLine))
    - 글자 크게·작게: \(k(.bigger)) / \(k(.smaller))
    - 찾기: \(k(.find))
    - 메모 1~5 바꾸기: \(k(.note1)) ~ \(k(.note5))
    - 단축키는 설정(\(k(.settings)))에서 바꿀 수 있어요. 이 도움말은 \(k(.help))로 다시 열어요.

    """
}

struct SettingsView: View {
    @State private var keys = Dictionary(uniqueKeysWithValues: Action.allCases.map { ($0, $0.shortcut) })
    @State private var recording: Action?
    @State private var monitor: Any?
    @State private var failed = false
    @AppStorage("fontFamily") private var fontFamily = ""  // 빈 값은 시스템 글꼴
    @AppStorage("alwaysOnTop") private var onTop = true

    // 일반 섹션에 없는 단축키는 여기 넣어야 설정에 보인다
    private let groups: [(String, [Action])] = [
        ("서식", [.bold, .italic, .strike, .highlight, .checkbox]),
        ("편집", [.indent, .outdent, .lineUp, .lineDown, .copyLine, .cutLine, .find]),
        ("보기", [.bigger, .smaller]),
        ("메모 전환", [.note1, .note2, .note3, .note4, .note5]),
    ]

    var changed: Bool { fontFamily != "" || !onTop || Action.allCases.contains { keys[$0] != $0.standard } }

    var body: some View {
        Form {
            Section("일반") {
                Picker(selection: $fontFamily) {
                    Text("시스템 기본").tag("")
                    ForEach(NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") }, id: \.self) { Text($0).tag($0) }
                } label: {
                    label("글꼴", changed: fontFamily != "")
                }
                Toggle(isOn: $onTop) { label("다른 앱 위에 항상 표시", changed: !onTop) }.toggleStyle(.switch)
                row(.open)
                if failed { Text("다른 앱이 이미 쓰고 있는 메모 열기 단축키예요.").foregroundStyle(.red) }
                row(.settings)
                row(.help)
            }
            ForEach(groups, id: \.0) { title, actions in
                Section(title) { ForEach(actions, id: \.self, content: row) }
            }
            Section {
                HStack {
                    if changed {
                        Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                        Text("기본값에서 바꾼 설정").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("기본값으로 초기화") {
                        stop()
                        keys = Dictionary(uniqueKeysWithValues: Action.allCases.map { ($0, $0.standard) })
                        fontFamily = ""
                        onTop = true
                    }
                    .disabled(!changed)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 600)
        .onChange(of: keys) {
            for (a, s) in keys { a.shortcut = s }
            failed = !HotKey.shared.register(keys[.open]!.code, keys[.open]!.mods)
        }
        .onDisappear(perform: stop)
    }

    func row(_ a: Action) -> some View {
        LabeledContent {
            Button(recording == a ? "키를 누르세요 (Esc 취소, ⌫ 없음)" : hotKeyLabel(keys[a]!.code, keys[a]!.mods)) {
                if recording == a { stop() } else { record(a) }
            }
        } label: {
            label(a.title, changed: keys[a] != a.standard)
        }
    }

    // 기본값과 다른 설정은 이름 뒤에 점을 찍는다
    func label(_ title: String, changed: Bool) -> some View {
        HStack(spacing: 5) {
            Text(title)
            if changed { Circle().fill(Color.accentColor).frame(width: 6, height: 6) }
        }
    }

    // 기록하는 동안은 메모 열기 단축키를 풀어둬야 같은 조합도 입력으로 들어온다
    func record(_ a: Action) {
        stop()
        HotKey.shared.register(-1, 0)
        recording = a
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            guard e.window === settingsWindow else { return e }
            let m = carbonMods(e.modifierFlags)
            switch e.keyCode {
            case 53:  // Esc
                stop()
            case 51:  // ⌫ → 없음
                keys[a] = Shortcut()
                stop()
            // 메모 열기는 전역이라 ⌘⌥⌃ 중 하나가 있어야 하고, 메모창 단축키는 Tab만 수정키 없이 허용
            case _ where m & (cmdKey | optionKey | controlKey) != 0 || (a != .open && e.keyCode == 48):
                keys[a] = Shortcut(code: Int(e.keyCode), mods: m)
                stop()
            default:
                break
            }
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
        failed = !HotKey.shared.register(keys[.open]!.code, keys[.open]!.mods)
    }
}

struct LiveEditor: NSViewRepresentable {
    @Binding var text: String
    var fontFamily: String

    func makeNSView(context: Context) -> NSScrollView {
        // TextKit 1 스택을 직접 만든다 (layoutManager로 글자 위치를 구해야 해서)
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)

        let tv = LiveTextView(frame: .zero, textContainer: container)
        tv.autoresizingMask = .width
        tv.isVerticallyResizable = true
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 8, height: 10)
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.usesFindBar = true  // ⌘F는 메모 위쪽에 찾기 막대를 띄운다
        tv.isIncrementalSearchingEnabled = true
        tv.delegate = context.coordinator

        let sv = NSScrollView()
        sv.appearance = NSAppearance(named: .aqua)  // 흰 배경이라 다크 모드에서도 밝은 글자색을 쓰지 않게
        sv.hasVerticalScroller = true
        sv.drawsBackground = false
        sv.documentView = tv
        DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {
        context.coordinator.text = $text
        let tv = sv.documentView as! LiveTextView
        if tv.fontFamily != fontFamily { tv.fontFamily = fontFamily }
        if tv.string != text {  // 다른 메모로 바뀌었을 때
            tv.string = text
            tv.undoManager?.removeAllActions()  // 이전 메모의 실행 취소 기록이 새 메모에 적용되지 않게
            tv.restyle()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ n: Notification) {
            let tv = n.object as! LiveTextView
            text.wrappedValue = tv.string
            tv.restyle()
        }

        func textViewDidChangeSelection(_ n: Notification) {
            (n.object as! LiveTextView).restyle()
        }
    }
}

private func rx(_ pattern: String) -> NSRegularExpression { try! NSRegularExpression(pattern: pattern) }

// 줄 머리 기호(들여쓰기 뒤): 체크박스·글머리표·인용·번호(1. ). 없으면 nil
func lineMarker(_ body: Substring) -> String? {
    if let m = ["- [ ] ", "- [x] ", "- ", "* ", "> "].first(where: { body.hasPrefix($0) }) { return m }
    let digits = body.prefix(while: { $0.isASCII && $0.isNumber })
    return !digits.isEmpty && body.dropFirst(digits.count).hasPrefix(". ") ? digits + ". " : nil
}

// 커서가 닿은 Markdown 기호는 흐리게 보여주고, 나머지는 기호를 숨겨서 렌더링된 것처럼 보이게 한다
final class LiveTextView: NSTextView {
    enum Mark { case box(Bool), bullet, rule, quote(NSRange) }  // quote는 막대를 그을 문단
    private var marks: [(NSRange, Mark)] = []
    private var codeBlocks: [NSRange] = []  // ``` 부터 ``` 까지
    private var fontSize = CGFloat(UserDefaults.standard.object(forKey: "fontSize") as? Double ?? 14) {
        didSet {
            UserDefaults.standard.set(Double(fontSize), forKey: "fontSize")
            restyle()
        }
    }

    var fontFamily = "" { didSet { restyle() } }

    // 설정에서 고른 글꼴. 비어 있거나 없는 글꼴이면 시스템 글꼴 (한글이 없는 글꼴은 한글만 시스템 글꼴로 나온다)
    private func font(_ size: CGFloat) -> NSFont {
        NSFontManager.shared.font(withFamily: fontFamily, traits: [], weight: 5, size: size) ?? .systemFont(ofSize: size)
    }

    private static let hidden: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 0.1), .foregroundColor: NSColor.clear]
    private static let inlineRules: [(NSRegularExpression, Int, (NSTextStorage, NSRange) -> Void)] = [
        (rx(#"\*\*(.+?)\*\*"#), 2, { $0.applyFontTraits(.boldFontMask, range: $1) }),
        // 한글 글꼴엔 기울임체가 없어서 글꼴 대신 글자를 기울인다
        (rx(#"(?<!\*)\*(?![\s*])(.+?)(?<![\s*])\*(?!\*)"#), 1, { $0.addAttribute(.obliqueness, value: 0.2, range: $1) }),
        (rx("~~(.+?)~~"), 2, { $0.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: $1) }),
        (rx("==(.+?)=="), 2, { $0.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.35), range: $1) }),
        (rx("`([^`]+)`"), 1, { st, r in
            let size = (st.attribute(.font, at: r.location, effectiveRange: nil) as! NSFont).pointSize - 1
            st.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: size, weight: .regular), .backgroundColor: NSColor.quaternaryLabelColor], range: r)
        }),
    ]
    private static let mdLink = rx(#"\[([^\]\n]+)\]\(([^)\s]+)\)"#)
    private static let urls = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    private static let linkKey = NSAttributedString.Key("memoLink")  // .link를 쓰면 그냥 클릭해도 열려서 따로 둔다

    // ponytail: 키 입력·커서 이동마다 문서 전체를 다시 칠한다. 메모가 수천 줄이 되면 바뀐 줄만 칠하도록
    func restyle() {
        guard !hasMarkedText(), let st = textStorage, let lm = layoutManager else { return }  // 한글 조합 중에는 건드리지 않는다
        let s = string as NSString
        let all = NSRange(location: 0, length: s.length)
        let sel = selectedRange()
        let active = s.paragraphRange(for: sel)
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3
        var hanging: [(NSRange, Int)] = []  // 목록·인용 줄과 그 내용 시작 위치
        var codeStart: Int?  // 코드 블록 안이면 여는 ``` 줄의 시작

        st.beginEditing()
        st.setAttributes([.font: font(fontSize), .foregroundColor: NSColor.labelColor, .paragraphStyle: para], range: all)
        marks = []
        codeBlocks = []
        s.enumerateSubstrings(in: all, options: .byParagraphs) { line, r, _, _ in
            guard let line else { return }
            let show = NSLocationInRange(r.location, active) || r.location == active.location
            let lead = line.prefix(while: { $0 == " " || $0 == "\t" }).count
            let body = line.dropFirst(lead)
            let at = r.location + lead

            // 코드 블록은 고정폭 글자만 쓰고 다른 서식은 적용하지 않는다. 배경은 draw()에서 칠한다
            if body.hasPrefix("```") || codeStart != nil {
                st.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: self.fontSize - 1, weight: .regular), range: r)
                guard body.hasPrefix("```") else { return }
                st.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: r)
                if let start = codeStart {
                    self.codeBlocks.append(NSRange(location: start, length: NSMaxRange(r) - start))
                    codeStart = nil
                } else {
                    codeStart = r.location
                }
                return
            }

            func markup(_ loc: Int, _ len: Int, raw: Bool) {
                st.addAttributes(raw ? [.foregroundColor: NSColor.tertiaryLabelColor] : Self.hidden, range: NSRange(location: loc, length: len))
            }
            // 글자 꾸밈·링크 기호는 커서·선택이 그 구간에 닿을 때(끝 바로 뒤 포함)만 원문을 보인다
            func touches(_ range: NSRange) -> Bool {
                NSLocationInRange(sel.location, range) || sel.location == NSMaxRange(range) || NSIntersectionRange(sel, range).length > 0
            }
            // 체크박스·글머리표·구분선은 글자 폭을 남겨두고 draw()에서 그 자리에 그린다. raw면 원문을 흐리게 보인다
            func mark(_ len: Int, _ m: Mark, raw: Bool) {
                let range = NSRange(location: at, length: len)
                st.addAttribute(.foregroundColor, value: raw ? NSColor.tertiaryLabelColor : NSColor.clear, range: range)
                if !raw { self.marks.append((range, m)) }
            }
            // 목록 기호는 줄에 들어가도 프리뷰로 두고, 커서·선택이 기호 위에 올 때만 원문을 보인다
            func onMarker(_ len: Int) -> Bool {
                let range = NSRange(location: at, length: len)
                return NSLocationInRange(sel.location, range) || NSIntersectionRange(sel, range).length > 0
            }

            let hashes = body.prefix(while: { $0 == "#" }).count
            if (1...3).contains(hashes), body.dropFirst(hashes).hasPrefix(" ") {
                st.addAttribute(.font, value: NSFontManager.shared.convert(self.font([22, 18, 15][hashes - 1] / 14 * self.fontSize), toHaveTrait: .boldFontMask), range: r)
                markup(at, hashes + 1, raw: show)
            } else if body.hasPrefix("- [ ] ") || body.hasPrefix("- [x] ") {
                hanging.append((r, at + 6))
                let done = body.hasPrefix("- [x] ")
                let raw = onMarker(6)
                mark(5, .box(done), raw: raw)
                // "- [ ]" 글자 폭이 상자보다 넓어서 글자는 접고 상자 폭만큼만 비워둔다
                if !raw {
                    st.addAttributes(Self.hidden, range: NSRange(location: at, length: 5))
                    st.addAttribute(.kern, value: self.fontSize + 1, range: NSRange(location: at + 4, length: 1))
                }
                if done {
                    st.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: NSColor.secondaryLabelColor],
                                     range: NSRange(location: at + 6, length: NSMaxRange(r) - at - 6))
                }
            } else if body.hasPrefix("- ") || body.hasPrefix("* ") {
                mark(1, .bullet, raw: onMarker(2))
                hanging.append((r, at + 2))
            } else if body.hasPrefix("> ") {  // 인용은 > 자리에 세로 막대를 긋는다
                mark(1, .quote(r), raw: onMarker(2))
                hanging.append((r, at + 2))
            } else if let n = lineMarker(body) {  // 남은 건 번호 목록. 번호는 늘 보이고 흐리게
                st.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: NSRange(location: at, length: n.count - 1))
                hanging.append((r, at + n.count))
            } else if body == "---" {
                mark(3, .rule, raw: show)
            }

            // 링크: 맨 URL은 그대로, [글자](주소)는 글자만 보인다. ⌘+클릭으로 연다 (mouseDown)
            func link(_ range: NSRange, _ url: URL) {
                st.addAttributes([.foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue, Self.linkKey: url], range: range)
            }
            for m in Self.urls.matches(in: s as String, range: r) { if let url = m.url { link(m.range, url) } }
            for m in Self.mdLink.matches(in: s as String, range: r) {
                let text = m.range(at: 1)
                if let url = URL(string: s.substring(with: m.range(at: 2))) { link(text, url) }
                let raw = touches(m.range)
                markup(m.range.location, 1, raw: raw)
                markup(NSMaxRange(text), NSMaxRange(m.range) - NSMaxRange(text), raw: raw)
            }

            for (regex, d, style) in Self.inlineRules {
                for m in regex.matches(in: s as String, range: r) {
                    style(st, m.range(at: 1))
                    let raw = touches(m.range)
                    markup(m.range.location, d, raw: raw)
                    markup(NSMaxRange(m.range) - d, d, raw: raw)
                }
            }
        }
        if let start = codeStart { codeBlocks.append(NSRange(location: start, length: s.length - start)) }  // 닫지 않은 코드 블록은 끝까지
        st.endEditing()

        // 목록·인용 줄이 화면에서 접히면 둘째 줄부터 내용 시작 위치에 맞춘다. 그 위치는 글자 배치가 끝나야 알 수 있어서 따로 칠한다
        let indents = hanging.filter { $0.1 < NSMaxRange($0.0) }.map { r, content in
            (r, lm.location(forGlyphAt: lm.glyphIndexForCharacter(at: content)).x - textContainer!.lineFragmentPadding)
        }
        st.beginEditing()
        for (r, indent) in indents {
            let p = para.mutableCopy() as! NSMutableParagraphStyle
            p.headIndent = indent
            st.addAttribute(.paragraphStyle, value: p, range: r)
        }
        st.endEditing()
        needsDisplay = true
    }

    private func rect(_ range: NSRange) -> NSRect {
        let glyphs = layoutManager!.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        return layoutManager!.boundingRect(forGlyphRange: glyphs, in: textContainer!)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }

    // 줄 글자의 세로 가운데. 줄 사각형은 아래에 lineSpacing이 붙어 있어서 그 가운데보다 위다
    private func textMidY(_ range: NSRange) -> CGFloat {
        let g = layoutManager!.glyphIndexForCharacter(at: range.location)
        return layoutManager!.lineFragmentRect(forGlyphAt: g, effectiveRange: nil).minY + layoutManager!.location(forGlyphAt: g).y
            + textContainerOrigin.y - font(fontSize).capHeight / 2
    }

    override func draw(_ dirtyRect: NSRect) {
        // 코드 블록 배경은 글자 밑에 깔리게 먼저 칠한다 (drawsBackground가 꺼져 있어서 super가 덮지 않는다)
        NSColor.quaternaryLabelColor.setFill()
        let left = textContainerOrigin.x + textContainer!.lineFragmentPadding - 4
        for block in codeBlocks {
            let b = rect(block)
            NSBezierPath(roundedRect: NSRect(x: left, y: b.minY, width: bounds.width - left * 2, height: b.height), xRadius: 4, yRadius: 4).fill()
        }
        super.draw(dirtyRect)
        for (range, mark) in marks {
            let r = rect(range)
            switch mark {
            case .box(let done):
                let side = fontSize + 1
                let img = NSImage(systemSymbolName: done ? "checkmark.square.fill" : "square", accessibilityDescription: nil)!
                    .withSymbolConfiguration(.init(paletteColors: done ? [.white, .controlAccentColor] : [.secondaryLabelColor]))!
                img.draw(in: NSRect(x: r.minX, y: textMidY(range) - side / 2, width: side, height: side),
                         from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            case .bullet:
                NSColor.secondaryLabelColor.setFill()
                let d = fontSize / 3
                NSBezierPath(ovalIn: NSRect(x: r.midX - d / 2, y: textMidY(range) - d / 2, width: d, height: d)).fill()
            case .rule:
                NSColor.separatorColor.setFill()
                NSRect(x: r.minX, y: r.midY, width: bounds.width - r.minX - textContainerInset.width, height: 1).fill()
            case .quote(let para):
                NSColor.tertiaryLabelColor.setFill()
                let p = rect(para)
                NSRect(x: r.minX + 1, y: p.minY, width: 3, height: p.height).fill()
            }
        }
    }

    // 렌더링된 체크박스를 클릭하면 커서를 옮기지 않고 [ ] ↔ [x]만 바꾼다. ⌘+클릭한 곳이 링크면 연다
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.command), let url = link(at: p) {
            NSWorkspace.shared.open(url)
            return
        }
        for case let (range, .box(done)) in marks where rect(range).contains(p) {
            let r = NSRange(location: range.location + 3, length: 1)
            let s = done ? " " : "x"
            if shouldChangeText(in: r, replacementString: s) {
                textStorage!.replaceCharacters(in: r, with: s)
                didChangeText()
            }
            return
        }
        super.mouseDown(with: event)
    }

    func link(at p: NSPoint) -> URL? {
        let i = layoutManager!.characterIndex(for: NSPoint(x: p.x - textContainerOrigin.x, y: p.y - textContainerOrigin.y),
                                              in: textContainer!, fractionOfDistanceBetweenInsertionPoints: nil)
        return i < textStorage!.length ? textStorage!.attribute(Self.linkKey, at: i, effectiveRange: nil) as? URL : nil
    }

    // 설정의 단축키를 keyCode로 비교해서 한글 입력 상태에서도 먹는다. ⌘ 조합은 performKeyEquivalent, Tab 등은 keyDown으로 들어온다
    private func perform(_ event: NSEvent) -> Bool {
        let pressed = Shortcut(code: Int(event.keyCode), mods: carbonMods(event.modifierFlags))
        guard let action = Action.allCases.first(where: { $0 != .open && $0.shortcut == pressed }) else { return false }
        if hasMarkedText() {  // 조합 중인 한글은 확정하고 시작
            inputContext?.discardMarkedText()
            unmarkText()
        }
        switch action {
        case .open: break
        case .settings: showSettings()
        case .help: showHelp()
        case .find:
            let item = NSMenuItem()
            item.tag = NSTextFinder.Action.showFindInterface.rawValue
            performTextFinderAction(item)
        case .bold: toggleWrap("**")
        case .italic: toggleWrap("*")
        case .strike: toggleWrap("~~")
        case .highlight: toggleWrap("==")
        case .checkbox: toggleCheckbox()
        case .lineUp: moveLines(by: -1)
        case .lineDown: moveLines(by: 1)
        case .bigger: fontSize = min(fontSize + 1, 30)
        case .smaller: fontSize = max(fontSize - 1, 10)
        case .indent: if !shiftListLines(by: 1) { insertTab(nil) }
        case .outdent: if !shiftListLines(by: -1) { insertBacktab(nil) }
        case .copyLine: copyLine(cut: false)
        case .cutLine: copyLine(cut: true)
        case .note1, .note2, .note3, .note4, .note5: UserDefaults.standard.set(action.note!, forKey: "selected")
        }
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        perform(event) || super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if !perform(event) { super.keyDown(with: event) }
    }

    // 목록·인용 줄에서 엔터를 치면 다음 줄에 같은 기호(체크박스는 빈 칸, 번호는 다음 번호)를 잇고, 내용 없는 줄에서 치면 기호를 지워 끝낸다
    // ponytail: 코드 블록 안의 "- " 줄도 목록처럼 이어진다. 거슬리면 코드 블록 안인지 확인하기
    override func insertNewline(_ sender: Any?) {
        let s = string as NSString
        let sel = selectedRange()
        var start = 0, end = 0
        s.getParagraphStart(&start, end: nil, contentsEnd: &end, for: sel)
        let line = s.substring(with: NSRange(location: start, length: end - start))
        let lead = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
        let body = line.dropFirst(lead.count)
        guard sel.length == 0, !hasMarkedText(), let marker = lineMarker(body),
              sel.location >= start + lead.count + marker.count  // 기호 앞에서 치면 그냥 줄바꿈
        else { return super.insertNewline(sender) }
        if body == marker {
            insertText("", replacementRange: NSRange(location: start, length: end - start))
        } else if let n = Int(marker.dropLast(2)) {
            // 아래에 이어지는 같은 단계 번호도 하나씩 밀어서 다시 매긴다. 실행 취소는 한 번에
            undoManager?.beginUndoGrouping()
            insertText("\n" + lead + "\(n + 1). ", replacementRange: sel)
            renumber(after: selectedRange().location, lead: lead, from: n + 2)
            undoManager?.endUndoGrouping()
        } else {
            insertText("\n" + lead + (marker == "- [x] " ? "- [ ] " : marker), replacementRange: sel)
        }
    }

    // loc이 있는 줄 다음부터 들여쓰기가 lead인 번호 줄의 번호를 n, n+1, …로 맞춘다. 더 깊이 들여쓴 하위 줄은 건너뛴다
    private func renumber(after loc: Int, lead: String, from n: Int) {
        var n = n
        var i = NSMaxRange((string as NSString).paragraphRange(for: NSRange(location: loc, length: 0)))
        while i < (string as NSString).length {
            let s = string as NSString
            let r = s.paragraphRange(for: NSRange(location: i, length: 0))
            let line = s.substring(with: r)
            let l = line.prefix(while: { $0 == " " || $0 == "\t" })
            i = NSMaxRange(r)
            if l.count > lead.count, l.hasPrefix(lead) { continue }
            guard l == lead, let m = lineMarker(line.dropFirst(l.count)), let old = Int(m.dropLast(2)) else { return }
            let digits = NSRange(location: r.location + l.count, length: m.count - 2)
            if old != n, shouldChangeText(in: digits, replacementString: "\(n)") {
                textStorage!.replaceCharacters(in: digits, with: "\(n)")
                didChangeText()
                i += "\(n)".count - digits.length
            }
            n += 1
        }
    }

    // 괄호·백틱은 짝을 같이 넣고, 글자를 선택한 채 치면 감싼다(* ~ =도). 닫는 기호 바로 앞에서 같은 기호를 치면 넘어가기만 한다
    private static let pairs = ["(": ")", "[": "]", "{": "}", "`": "`"]
    override func insertText(_ string: Any, replacementRange: NSRange) {
        let typed = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        let s = self.string as NSString
        let sel = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
        func char(_ i: Int) -> String { i >= 0 && i < s.length ? s.substring(with: NSRange(location: i, length: 1)) : "" }
        let next = char(NSMaxRange(sel)), prev = char(sel.location - 1)
        guard !hasMarkedText(), typed.count == 1 else { return super.insertText(string, replacementRange: replacementRange) }
        if sel.length == 0, Self.pairs.values.contains(typed), next == typed {
            return setSelectedRange(NSRange(location: sel.location + 1, length: 0))
        }
        if let close = Self.pairs[typed] ?? (sel.length > 0 && "*~=".contains(typed) ? typed : nil) {
            if sel.length > 0 {
                super.insertText(typed + s.substring(with: sel) + close, replacementRange: sel)
                return setSelectedRange(NSRange(location: sel.location + 1, length: sel.length))
            }
            // 바로 뒤에 글자가 붙어 있으면 짝을 넣지 않는다. ```를 칠 수 있게 백틱 뒤 백틱도 넣지 않는다
            if next.isEmpty || next == " " || next == "\n" || Self.pairs.values.contains(next), !(typed == "`" && prev == "`") {
                super.insertText(typed + close, replacementRange: sel)
                return setSelectedRange(NSRange(location: sel.location + 1, length: 0))
            }
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    // 빈 괄호 짝 사이에서 지우면 닫는 쪽도 같이 지운다
    override func deleteBackward(_ sender: Any?) {
        let s = string as NSString, sel = selectedRange()
        if sel.length == 0, sel.location > 0, sel.location < s.length,
           Self.pairs[s.substring(with: NSRange(location: sel.location - 1, length: 1))] == s.substring(with: NSRange(location: sel.location, length: 1)) {
            return insertText("", replacementRange: NSRange(location: sel.location - 1, length: 2))
        }
        super.deleteBackward(sender)
    }

    // 줄을 체크박스로 만들고, 이미 빈 체크박스면 체크한다(체크된 건 다시 빈 칸). 여러 줄을 선택하면 빈 줄만 빼고 한꺼번에
    private func toggleCheckbox() {
        let s = string as NSString
        let sel = selectedRange()
        let block = s.paragraphRange(for: sel)
        var text = s.substring(with: block)
        let newline = text.hasSuffix("\n")
        if newline { text.removeLast() }
        var lines = text.components(separatedBy: "\n")
        var caret = sel.location
        for i in lines.indices where !lines[i].isEmpty || lines.count == 1 {
            let lead = lines[i].prefix(while: { $0 == " " || $0 == "\t" })
            let body = lines[i].dropFirst(lead.count)
            let old = lineMarker(body) ?? ""
            let new = old == "- [ ] " ? "- [x] " : "- [ ] "
            lines[i] = lead + new + body.dropFirst(old.count)
            if i == 0 {  // 커서는 내용 안에서 같은 글자 앞에 둔다
                let content = block.location + lead.count
                caret = max(sel.location - old.count, content) + new.count
            }
        }
        let new = lines.joined(separator: "\n") + (newline ? "\n" : "")
        guard shouldChangeText(in: block, replacementString: new) else { return }
        textStorage!.replaceCharacters(in: block, with: new)
        didChangeText()
        setSelectedRange(sel.length == 0 ? NSRange(location: caret, length: 0) : NSRange(location: block.location, length: (new as NSString).length - (newline ? 1 : 0)))
    }

    // 커서가 있는 줄(선택한 줄들)을 위·아래 줄과 맞바꾼다
    private func moveLines(by step: Int) {
        let s = string as NSString
        let sel = selectedRange()
        let block = s.paragraphRange(for: sel)
        guard block.length > 0, step < 0 ? block.location > 0 : NSMaxRange(block) < s.length else { return }
        let neighbor = s.paragraphRange(for: NSRange(location: step < 0 ? block.location - 1 : NSMaxRange(block), length: 0))
        let both = NSUnionRange(block, neighbor)
        var text = s.substring(with: both)
        let newline = text.hasSuffix("\n")  // 마지막 줄에 줄바꿈이 없어도 맞바꾼 뒤 그대로 없게
        if newline { text.removeLast() }
        var lines = text.components(separatedBy: "\n")
        let other = step < 0 ? lines.removeFirst() : lines.removeLast()
        lines = step < 0 ? lines + [other] : [other] + lines
        let new = lines.joined(separator: "\n") + (newline ? "\n" : "")
        guard shouldChangeText(in: both, replacementString: new) else { return }
        textStorage!.replaceCharacters(in: both, with: new)
        didChangeText()
        let shift = (other as NSString).length + 1
        setSelectedRange(NSRange(location: sel.location + (step < 0 ? -shift : shift), length: sel.length))
    }

    // 목록 줄에서 ⌘←는 먼저 기호 바로 뒤(내용 맨 앞)로 가고, 이미 거기거나 기호 안이면 줄 맨 앞으로 간다
    override func moveToLeftEndOfLine(_ sender: Any?) {
        let before = selectedRange().location
        super.moveToLeftEndOfLine(sender)
        if let content = listContent(before), before > content, selectedRange().location < content {
            setSelectedRange(NSRange(location: content, length: 0))
        }
    }

    // ⇧⌘←도 같은 규칙으로 선택의 왼쪽 끝을 내용 맨 앞에서 멈춘다
    override func moveToLeftEndOfLineAndModifySelection(_ sender: Any?) {
        let before = selectedRange().location
        super.moveToLeftEndOfLineAndModifySelection(sender)
        let after = selectedRange()
        // 선택을 직접 지정하면 기준점(이후 ⇧←·⇧→가 움직이지 않는 쪽)을 잃어서, 되도록 한 글자씩 당겨 기준점을 남긴다
        if let content = listContent(before), before > content, after.location < content {
            moveRightAndModifySelection(nil)
            if selectedRange().location > after.location {  // 기준점이 오른쪽 끝 (보통의 경우)
                for _ in selectedRange().location..<content { moveRightAndModifySelection(nil) }
            } else {  // 오른쪽으로 늘려 가던 선택이면 기준점은 못 지키고 범위만 맞춘다
                setSelectedRange(NSRange(location: content, length: NSMaxRange(after) - content))
            }
        }
    }

    // loc이 있는 목록 줄의 내용 시작 위치(기호 바로 뒤). 목록 줄이 아니면 nil
    private func listContent(_ loc: Int) -> Int? {
        let s = string as NSString
        var start = 0, end = 0
        s.getParagraphStart(&start, end: nil, contentsEnd: &end, for: NSRange(location: loc, length: 0))
        let line = s.substring(with: NSRange(location: start, length: end - start))
        let lead = line.prefix(while: { $0 == " " || $0 == "\t" }).count
        // 줄이 화면에서 접혀 둘째 줄 이후에 있으면 호출한 쪽에서 기본 동작(그 화면 줄의 맨 앞)대로 둔다
        return lineMarker(line.dropFirst(lead)).map { start + lead + $0.count }
    }

    // 선택이 없으면 커서가 있는 줄 전체(줄바꿈 포함)를 선택해서 복사·잘라낸다. 복사는 선택이 남아서 무엇을 복사했는지 보인다
    private func copyLine(cut: Bool) {
        if selectedRange().length == 0 {
            let line = (string as NSString).paragraphRange(for: selectedRange())
            guard line.length > 0 else { return }
            setSelectedRange(line)
        }
        if cut { self.cut(nil) } else { copy(nil) }
    }

    // 선택한 부분(선택이 없으면 현재 줄에서 #·- [ ] 같은 머리 기호를 뺀 내용)을 m(** · * · ~~ · ==)으로 감싸거나 푼다
    // ponytail: 굵게+기울임 겹침(***글자***)은 렌더링이 깨진다. 필요하면 굵게·기울임 정규식을 *** 기준으로 손보기
    private func toggleWrap(_ m: String) {
        if hasMarkedText() {  // 조합 중인 한글은 확정하고 시작
            inputContext?.discardMarkedText()
            unmarkText()
        }
        let s = string as NSString
        let sel = selectedRange()
        var target = sel
        if sel.length == 0 {
            var start = 0, end = 0
            s.getParagraphStart(&start, end: nil, contentsEnd: &end, for: sel)
            let line = s.substring(with: NSRange(location: start, length: end - start))
            let lead = line.prefix(while: { $0 == " " || $0 == "\t" }).count
            let body = line.dropFirst(lead)
            let hashes = body.prefix(while: { $0 == "#" }).count
            let marker = lineMarker(body)?.count
                ?? ((1...3).contains(hashes) && body.dropFirst(hashes).hasPrefix(" ") ? hashes + 1 : 0)
            target = NSRange(location: start + lead + marker, length: end - start - lead - marker)
        }

        // 이미 감싸져 있으면 m은 대상 안쪽 끝(**글자**를 선택한 경우)이거나 바로 바깥(글자만 선택한 경우)에 있다.
        // 같은 기호 글자가 정확히 m 길이만큼 이어질 때만 m으로 본다 (기울임 *를 굵게 **의 일부로 보지 않게)
        let d = m.utf16.count, c = m.utf16.first!
        func run(_ i: Int, _ step: Int) -> Int {
            var j = i
            while j >= 0, j < s.length, s.character(at: j) == c { j += step }
            return abs(j - i)
        }
        let text = s.substring(with: target)
        let unwrap: NSRange? = target.length >= 2 * d && run(target.location, 1) == d && run(NSMaxRange(target) - 1, -1) == d ? target
            : run(target.location - 1, -1) == d && run(NSMaxRange(target), 1) == d ? NSRange(location: target.location - d, length: target.length + 2 * d)
            : nil

        let edit = unwrap ?? target
        let inner = unwrap.map { NSRange(location: $0.location + d, length: $0.length - 2 * d) } ?? target
        let new = unwrap == nil ? m + text + m : s.substring(with: inner)
        guard shouldChangeText(in: edit, replacementString: new) else { return }
        textStorage!.replaceCharacters(in: edit, with: new)
        didChangeText()

        let innerStart = edit.location + (unwrap == nil ? d : 0)
        let caret = min(max(sel.location - inner.location, 0), inner.length)
        setSelectedRange(sel.length > 0
            ? NSRange(location: innerStart, length: inner.length)
            : NSRange(location: innerStart + caret, length: 0))
    }

    // 목록 줄에서는 커서 위치와 상관없이 줄 전체를 들여쓰기·내어쓰기한다
    private func shiftListLines(by step: Int) -> Bool {
        let s = string as NSString
        let sel = selectedRange()
        let block = s.paragraphRange(for: sel)
        var lines = s.substring(with: block).components(separatedBy: "\n")
        var hasList = false
        var firstDelta = 0
        for i in lines.indices {
            let body = lines[i].drop(while: { $0 == " " || $0 == "\t" })
            guard let m = lineMarker(body), m != "> " else { continue }
            hasList = true
            if step > 0 {
                lines[i] = "\t" + lines[i]
            } else if lines[i].hasPrefix("\t") {
                lines[i].removeFirst()
            } else {
                continue
            }
            if i == 0 { firstDelta = step }
        }
        guard hasList else { return false }

        let new = lines.joined(separator: "\n")
        if new != s.substring(with: block), shouldChangeText(in: block, replacementString: new) {
            textStorage!.replaceCharacters(in: block, with: new)
            didChangeText()
            setSelectedRange(sel.length == 0
                ? NSRange(location: max(block.location, sel.location + firstDelta), length: 0)
                : NSRange(location: block.location, length: (new as NSString).length))
        }
        return true
    }

    // 글이 짧아도 빈 영역 클릭이 텍스트 뷰에 닿도록 보이는 높이만큼은 차지한다
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(NSSize(width: newSize.width, height: max(newSize.height, enclosingScrollView?.contentSize.height ?? 0)))
    }
}
