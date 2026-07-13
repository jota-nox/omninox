// OmniNox Capture v2 — app nativo Swift/AppKit
// Reescrita do app Electron (2026-07-13). Menubar quick-capture pro vault OmniNox.
// Alinhado ao contrato OmniNox v2: valida marker .omninox-vault, git commit+push
// após cada save, escrita verificada. OCR via Vision in-process.

import AppKit
import Vision
import Carbon.HIToolbox
import ServiceManagement
import UniformTypeIdentifiers

// MARK: - Theme

enum Theme {
    static let bgTint = NSColor(srgbRed: 0x18/255.0, green: 0x18/255.0, blue: 0x1B/255.0, alpha: 0.88)
    static let bgSolid = NSColor(srgbRed: 0x18/255.0, green: 0x18/255.0, blue: 0x1B/255.0, alpha: 0.97)
    static let border = NSColor(white: 1.0, alpha: 0.10)
    static let text = NSColor(srgbRed: 0xFA/255.0, green: 0xFA/255.0, blue: 0xFA/255.0, alpha: 1)
    static let muted = NSColor(srgbRed: 0xA1/255.0, green: 0xA1/255.0, blue: 0xAA/255.0, alpha: 1)
    // hints: o ajuste fino pedido — chips e labels com contraste real
    static let hintLabel = NSColor(srgbRed: 0xB4/255.0, green: 0xB4/255.0, blue: 0xBC/255.0, alpha: 1)
    static let kbdBg = NSColor(srgbRed: 0x3F/255.0, green: 0x3F/255.0, blue: 0x46/255.0, alpha: 1)
    static let kbdText = NSColor(srgbRed: 0xE8/255.0, green: 0xE8/255.0, blue: 0xEA/255.0, alpha: 1)
    static let kbdBorder = NSColor(white: 1.0, alpha: 0.12)
    static let accent = NSColor(srgbRed: 0xE2/255.0, green: 0xE0/255.0, blue: 0x33/255.0, alpha: 1)
    static let accentDim = NSColor(srgbRed: 0xE2/255.0, green: 0xE0/255.0, blue: 0x33/255.0, alpha: 0.15)
    static let success = NSColor(srgbRed: 0x34/255.0, green: 0xD3/255.0, blue: 0x99/255.0, alpha: 1)
    static let danger = NSColor(srgbRed: 0xF8/255.0, green: 0x71/255.0, blue: 0x71/255.0, alpha: 1)

    static func mono(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let candidates: [NSFont.Weight: [String]] = [
            .regular: ["JetBrainsMono-Regular", "JetBrainsMonoRoman-Regular", "JetBrains Mono"],
            .medium: ["JetBrainsMono-Medium", "JetBrainsMonoRoman-Medium"],
            .bold: ["JetBrainsMono-Bold", "JetBrainsMonoRoman-Bold", "JetBrainsMono-ExtraBold"],
        ]
        for name in candidates[weight] ?? [] {
            if let f = NSFont(name: name, size: size) { return f }
        }
        return .monospacedSystemFont(ofSize: size, weight: weight)
    }
}

// MARK: - Config

struct Config {
    static let defaultVaultPath = NSString(string: "~/Documents/omninox").expandingTildeInPath
    static let dir = NSString(string: "~/.config/omninox").expandingTildeInPath
    static let file = dir + "/config.json"
    static let logFile = dir + "/capture.log"
    static let legacyFile = NSString(string: "~/.config/omninox-capture/config.json").expandingTildeInPath

    static func load() -> [String: Any] {
        if let data = FileManager.default.contents(atPath: file),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json
        }
        // migração da config antiga (app Electron / v2.0)
        if let data = FileManager.default.contents(atPath: legacyFile),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            save(json)
            return json
        }
        return [:]
    }

    static func save(_ config: [String: Any]) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: file))
        }
    }

    static var vaultPath: String {
        get { (load()["vaultPath"] as? String) ?? defaultVaultPath }
        set { var c = load(); c["vaultPath"] = newValue; save(c) }
    }

    static func log(_ message: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let line = "[\(df.string(from: Date()))] \(message)\n"
        if let handle = FileHandle(forWritingAtPath: logFile) {
            // rotação simples: acima de 256 KB recomeça
            if let size = try? FileManager.default.attributesOfItem(atPath: logFile)[.size] as? Int, size > 262_144 {
                try? line.write(toFile: logFile, atomically: true, encoding: .utf8)
            } else {
                handle.seekToEndOfFile()
                handle.write(line.data(using: .utf8)!)
            }
            try? handle.close()
        } else {
            try? line.write(toFile: logFile, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Core (lógica de save, testável sem UI)

struct AttachmentInput {
    let originalName: String
    let data: Data
}

enum SaveError: Error, CustomStringConvertible {
    case missingMarker(String)
    case writeFailed(String)

    var description: String {
        switch self {
        case .missingMarker(let path):
            return "Vault sem marker .omninox-vault em \(path) — árvore errada, nada foi salvo."
        case .writeFailed(let path):
            return "Escrita não verificada em \(path)."
        }
    }
}

enum Core {
    static let imageExts = ["png", "jpg", "jpeg", "gif", "webp", "svg"]

    static func slugify(_ text: String, maxLen: Int = 30) -> String {
        let folded = text.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "pt_BR"))
        var slug = ""
        var lastWasDash = false
        for ch in folded.unicodeScalars {
            if (ch >= "a" && ch <= "z") || (ch >= "0" && ch <= "9") {
                slug.unicodeScalars.append(ch)
                lastWasDash = false
            } else if !lastWasDash && !slug.isEmpty {
                slug.append("-")
                lastWasDash = true
            }
        }
        if slug.hasSuffix("-") { slug.removeLast() }
        if slug.count <= maxLen { return slug }
        let truncated = String(slug.prefix(maxLen))
        if let lastDash = truncated.lastIndex(of: "-"),
           truncated.distance(from: truncated.startIndex, to: lastDash) > 10 {
            return String(truncated[..<lastDash])
        }
        return truncated
    }

    static func timestampParts(_ date: Date = Date()) -> (date: String, time: String) {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        let tf = DateFormatter()
        tf.locale = Locale(identifier: "en_US_POSIX")
        tf.dateFormat = "HHmm"
        return (df.string(from: date), tf.string(from: date))
    }

    static func filenamePreview(for text: String, at date: Date = Date()) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let firstLine = trimmed.components(separatedBy: "\n")[0]
            .replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let slug = slugify(firstLine)
        guard !slug.isEmpty else { return "" }
        let (d, t) = timestampParts(date)
        return "\(d)_\(t)_\(slug).md"
    }

    /// Salva a nota no 00 Inbox do vault. Valida o marker antes (contrato v2),
    /// verifica a escrita depois. Retorna o filename gravado.
    @discardableResult
    static func saveNote(text: String, attachments: [AttachmentInput], vault: String, date: Date = Date()) throws -> String {
        let fm = FileManager.default

        // Regra v2: marker ausente = árvore errada, PARE.
        guard fm.fileExists(atPath: vault + "/.omninox-vault") else {
            throw SaveError.missingMarker(vault)
        }

        let inbox = vault + "/00 Inbox"
        let attachmentsDir = inbox + "/attachments"
        try fm.createDirectory(atPath: inbox, withIntermediateDirectories: true)
        if !attachments.isEmpty {
            try fm.createDirectory(atPath: attachmentsDir, withIntermediateDirectories: true)
        }

        let (dateStr, timeStr) = timestampParts(date)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = trimmed.components(separatedBy: "\n")[0]
            .replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        var slug = slugify(firstLine)
        if slug.isEmpty { slug = "nota" }

        var attachmentRefs: [String] = []
        for att in attachments {
            let ext = (att.originalName as NSString).pathExtension.lowercased()
            let extWithDot = ext.isEmpty ? ".bin" : "." + ext
            let base = (att.originalName as NSString).deletingPathExtension
            var attName = "\(dateStr)_\(timeStr)_\(slugify(base))\(extWithDot)"
            var counter = 2
            while fm.fileExists(atPath: attachmentsDir + "/" + attName) {
                attName = "\(dateStr)_\(timeStr)_\(slugify(base))-\(counter)\(extWithDot)"
                counter += 1
            }
            let destPath = attachmentsDir + "/" + attName
            try att.data.write(to: URL(fileURLWithPath: destPath))
            guard fm.fileExists(atPath: destPath) else { throw SaveError.writeFailed(destPath) }
            let isImage = imageExts.contains(ext)
            attachmentRefs.append(isImage ? "![[attachments/\(attName)]]" : "[[attachments/\(attName)]]")
        }

        var body = trimmed.isEmpty ? "Nota sem texto" : trimmed
        if !attachmentRefs.isEmpty {
            body += "\n\n" + attachmentRefs.joined(separator: "\n")
        }
        let content = "---\ntags:\n  - status/inbox\ndate: \(dateStr)\n---\n\n\(body)\n"

        var filename = "\(dateStr)_\(timeStr)_\(slug).md"
        var counter = 2
        while fm.fileExists(atPath: inbox + "/" + filename) {
            filename = "\(dateStr)_\(timeStr)_\(slug)-\(counter).md"
            counter += 1
        }
        let filePath = inbox + "/" + filename
        try content.write(toFile: filePath, atomically: true, encoding: .utf8)

        // Regra v2: escrita não verificada não aconteceu.
        guard let size = try? fm.attributesOfItem(atPath: filePath)[.size] as? Int, size > 0 else {
            throw SaveError.writeFailed(filePath)
        }
        return filename
    }

    // MARK: git (contrato v2: toda escrita termina em commit; push best-effort)

    @discardableResult
    static func run(_ launchPath: String, _ args: [String], timeout: TimeInterval = 30) -> (status: Int32, stdout: String, stderr: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = args
        let outPipe = Pipe(), errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        do { try proc.run() } catch {
            return (-1, "", "\(error)")
        }
        let deadline = DispatchTime.now() + timeout
        let sema = DispatchSemaphore(value: 0)
        proc.terminationHandler = { _ in sema.signal() }
        if sema.wait(timeout: deadline) == .timedOut {
            proc.terminate()
            return (-1, "", "timeout after \(timeout)s")
        }
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (proc.terminationStatus, out, err)
    }

    static let gitQueue = DispatchQueue(label: "com.omninox.capture.git", qos: .utility)

    /// git add -A && commit && pull --rebase && push, em fila serial de background.
    /// Espelha o omni-capture.py: commit sempre; sync/push só se houver remote
    /// (sem origin = usuário escolheu ficar local); conflito aborta e loga.
    static func gitCommitAndPush(vault: String, message: String, synchronous: Bool = false) {
        let work = {
            _ = run("/usr/bin/git", ["-C", vault, "add", "-A"])
            let staged = run("/usr/bin/git", ["-C", vault, "diff", "--cached", "--quiet"])
            if staged.status != 0 {
                let commit = run("/usr/bin/git", ["-C", vault, "commit", "-q", "-m", message])
                if commit.status != 0 {
                    Config.log("commit fail: \(commit.stderr.prefix(200))")
                }
            }
            let remotes = run("/usr/bin/git", ["-C", vault, "remote"])
            guard remotes.stdout.contains("origin") else { return }
            let pull = run("/usr/bin/git", ["-C", vault, "pull", "--rebase", "--autostash", "-q", "origin", "master"], timeout: 90)
            if pull.status != 0 {
                _ = run("/usr/bin/git", ["-C", vault, "rebase", "--abort"])
                Config.log("pull-rebase conflito/falha: \(pull.stderr.prefix(300))")
            }
            let push = run("/usr/bin/git", ["-C", vault, "push", "-q", "origin", "master"], timeout: 60)
            if push.status != 0 {
                Config.log("push fail: \(push.stderr.prefix(200))")
            }
        }
        if synchronous { work() } else { gitQueue.async(execute: work) }
    }

    // MARK: OCR (Vision, in-process — substitui o binário `ocr` do app Electron)

    static func recognizeText(in imageData: Data, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let image = NSImage(data: imageData),
                  let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                completion(nil); return
            }
            let request = VNRecognizeTextRequest { req, _ in
                let lines = (req.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string } ?? []
                completion(lines.isEmpty ? nil : lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["pt-BR", "en-US"]
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cg)
            do { try handler.perform([request]) } catch { completion(nil) }
        }
    }

    /// Heurística do app antigo: mergeia line-wraps visuais do Vision em frases.
    static func mergeOcrLines(_ raw: String) -> [String] {
        var merged: [String] = []
        for line in raw.components(separatedBy: "\n") {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            let startsNewBlock = trimmedLine.range(of: #"^\d+[\.\)]"#, options: .regularExpression) != nil
            let prevEnded = merged.last.map {
                $0.trimmingCharacters(in: .whitespaces).range(of: #"[.!?:;]$"#, options: .regularExpression) != nil
            } ?? true
            if prevEnded || startsNewBlock {
                merged.append(line)
            } else {
                merged[merged.count - 1] += " " + trimmedLine
            }
        }
        return merged
    }

    static func ocrBlock(existingText: String, ocrText: String) -> String {
        let merged = mergeOcrLines(ocrText)
        let formatted = merged.map { "> " + $0 }.joined(separator: "\n")
        let hasText = !existingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let separator = hasText ? "\n\n---\n> **Texto extraído:**\n" : ""
        let trimmedEnd = existingText.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        return trimmedEnd + separator + formatted
    }
}

// MARK: - UI: painel de captura

final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class CaptureTextView: NSTextView {
    var onSave: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onImagePasted: ((Data) -> Void)?
    var onFilesDropped: (([URL]) -> Void)?
    var onDragState: ((Bool) -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 && event.modifierFlags.contains(.command) { onSave?(); return }
        if event.keyCode == 53 { onDismiss?(); return }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) { onDismiss?() }

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        var pastedImages: [Data] = []
        for item in pb.pasteboardItems ?? [] {
            if let png = item.data(forType: .png) {
                pastedImages.append(png)
            } else if let tiff = item.data(forType: .tiff),
                      let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) {
                pastedImages.append(png)
            }
        }
        if !pastedImages.isEmpty {
            pastedImages.forEach { onImagePasted?($0) }
            return
        }
        super.paste(sender)
    }

    private func fileURLs(from info: NSDraggingInfo) -> [URL] {
        (info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if !fileURLs(from: sender).isEmpty { onDragState?(true); return .copy }
        return super.draggingEntered(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragState?(false)
        super.draggingExited(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender)
        onDragState?(false)
        if !urls.isEmpty { onFilesDropped?(urls); return true }
        return super.performDragOperation(sender)
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class DashedOverlayView: NSView {
    private let shape = CAShapeLayer()
    private let label = NSTextField(labelWithString: "Soltar aqui")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Theme.accentDim.withAlphaComponent(0.08).cgColor
        layer?.cornerRadius = 12
        shape.fillColor = nil
        shape.strokeColor = Theme.accent.cgColor
        shape.lineWidth = 2
        shape.lineDashPattern = [6, 4]
        layer?.addSublayer(shape)
        label.font = Theme.mono(13, weight: .medium)
        label.textColor = Theme.accent
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        shape.frame = bounds
        shape.path = CGPath(roundedRect: bounds.insetBy(dx: 4, dy: 4), cornerWidth: 9, cornerHeight: 9, transform: nil)
        label.sizeToFit()
        label.frame.origin = NSPoint(x: (bounds.width - label.frame.width) / 2,
                                     y: (bounds.height - label.frame.height) / 2)
    }
}

/// Chip de tecla (⌘↩ / esc) — redesenho pro problema de legibilidade.
/// Símbolos de tecla via SF Symbols (JetBrains Mono não tem esses glifos;
/// o fallback de fonte renderizava ⌘⏎ minúsculo e ilegível).
final class KbdChip: NSView {
    private static let chipHeight: CGFloat = 20

    convenience init(symbols: [String]) {
        self.init()
        var x: CGFloat = 7
        for name in symbols {
            guard let base = NSImage(systemSymbolName: name, accessibilityDescription: name)?
                .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold)) else { continue }
            let tintedImg = NSImage(size: base.size, flipped: false) { rect in
                base.draw(in: rect)
                Theme.kbdText.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            let iv = NSImageView(image: tintedImg)
            iv.frame = NSRect(x: x, y: (Self.chipHeight - base.size.height) / 2,
                              width: base.size.width, height: base.size.height)
            addSubview(iv)
            x += base.size.width + 4
        }
        setFrameSize(NSSize(width: x - 4 + 7, height: Self.chipHeight))
    }

    convenience init(text: String) {
        self.init()
        let label = NSTextField(labelWithString: text)
        label.font = Theme.mono(11, weight: .medium)
        label.textColor = Theme.kbdText
        label.sizeToFit()
        addSubview(label)
        setFrameSize(NSSize(width: label.frame.width + 14, height: Self.chipHeight))
        label.frame.origin = NSPoint(x: 7, y: (Self.chipHeight - label.frame.height) / 2)
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Theme.kbdBg.cgColor
        layer?.cornerRadius = 5
        layer?.borderWidth = 1
        layer?.borderColor = Theme.kbdBorder.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate, NSTextViewDelegate {
    static var shared: AppDelegate?

    private var panel: CapturePanel!
    private var container: FlippedView!
    private var effectView: NSVisualEffectView!
    private var tintView: NSView!
    private var brandLabel: NSTextField!
    private var scrollView: NSScrollView!
    private var textView: CaptureTextView!
    private var placeholderLabel: NSTextField!
    private var slugLabel: NSTextField!
    private var attachmentsRow: NSView!
    private var footerView: NSView!
    private var attachButton: NSButton!
    private var ocrIndicator: NSTextField!
    private var hintsView: NSView!
    private var dropOverlay: DashedOverlayView!
    private var feedbackView: NSView!
    private var feedbackLabel: NSTextField!

    private var statusItem: NSStatusItem!
    private var trayMenu: NSMenu!
    private var hotKeyRef: EventHotKeyRef?

    private var attachments: [(input: AttachmentInput, isImage: Bool)] = []
    private var ocrPending = 0
    private var isSaving = false
    private var suppressAutoHide = false

    private let panelWidth: CGFloat = 480
    private let padding: CGFloat = 16

    // MARK: lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        buildPanel()
        buildTray()
        registerHotKey()
        firstRunLoginItem()

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            guard let self, !self.suppressAutoHide else { return }
            if self.panel.isVisible { self.hidePanel() }
        }

        let args = CommandLine.arguments
        if args.contains("--show") {
            showPanel()
        }
        if let idx = args.firstIndex(of: "--snapshot"), args.count > idx + 1 {
            renderSnapshot(to: args[idx + 1])
        }
    }

    // MARK: painel

    private func buildPanel() {
        panel = CapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 180),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .darkAqua)

        container = FlippedView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: 180))
        container.wantsLayer = true
        container.layer?.cornerRadius = 13
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = 1
        container.layer?.borderColor = Theme.border.cgColor
        panel.contentView = container

        effectView = NSVisualEffectView()
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.autoresizingMask = [.width, .height]
        container.addSubview(effectView)

        tintView = NSView()
        tintView.wantsLayer = true
        tintView.layer?.backgroundColor = Theme.bgTint.cgColor
        tintView.autoresizingMask = [.width, .height]
        container.addSubview(tintView)

        brandLabel = NSTextField(labelWithString: "OmniNox")
        brandLabel.font = Theme.mono(12, weight: .bold)
        brandLabel.textColor = Theme.accent
        if let font = brandLabel.font {
            brandLabel.attributedStringValue = NSAttributedString(
                string: "OmniNox",
                attributes: [.font: font, .foregroundColor: Theme.accent, .kern: 0.25])
        }
        brandLabel.sizeToFit()
        container.addSubview(brandLabel)

        textView = CaptureTextView()
        textView.isRichText = false
        textView.font = Theme.mono(13)
        textView.textColor = Theme.text
        textView.insertionPointColor = Theme.accent
        textView.drawsBackground = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.defaultParagraphStyle = {
            let p = NSMutableParagraphStyle()
            p.lineHeightMultiple = 1.35
            return p
        }()
        textView.typingAttributes = [
            .font: Theme.mono(13),
            .foregroundColor: Theme.text,
            .paragraphStyle: textView.defaultParagraphStyle!,
        ]
        textView.delegate = self
        textView.onSave = { [weak self] in self?.save() }
        textView.onDismiss = { [weak self] in self?.hidePanel() }
        textView.onImagePasted = { [weak self] data in
            let name = "clipboard-\(Int(Date().timeIntervalSince1970 * 1000)).png"
            self?.addAttachment(name: name, data: data)
        }
        textView.onFilesDropped = { [weak self] urls in self?.addFiles(urls) }
        textView.onDragState = { [weak self] active in self?.setDropOverlay(visible: active) }
        // primeira linha desvia do brand (equivalente ao padding-right: 80px do CSS)
        textView.textContainer?.exclusionPaths = [
            NSBezierPath(rect: NSRect(x: panelWidth - 2 * padding - 80, y: 0, width: 80, height: 18))
        ]

        scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .none
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        container.addSubview(scrollView)

        placeholderLabel = NSTextField(labelWithString: "Tá pensando em que xuxu?")
        placeholderLabel.font = Theme.mono(13)
        placeholderLabel.textColor = Theme.muted.withAlphaComponent(0.8)
        placeholderLabel.sizeToFit()
        container.addSubview(placeholderLabel)

        slugLabel = NSTextField(labelWithString: "")
        slugLabel.font = Theme.mono(10)
        slugLabel.textColor = Theme.muted.withAlphaComponent(0.45)
        slugLabel.lineBreakMode = .byTruncatingTail
        container.addSubview(slugLabel)

        attachmentsRow = FlippedView()
        attachmentsRow.wantsLayer = true
        attachmentsRow.isHidden = true
        container.addSubview(attachmentsRow)

        footerView = FlippedView()
        container.addSubview(footerView)

        attachButton = NSButton()
        attachButton.bezelStyle = .regularSquare
        attachButton.isBordered = false
        attachButton.wantsLayer = true
        attachButton.layer?.cornerRadius = 6
        attachButton.layer?.borderWidth = 1
        attachButton.layer?.borderColor = Theme.border.cgColor
        let clip = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "Anexar")!
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))!
        attachButton.image = tinted(clip, color: Theme.muted)
        attachButton.target = self
        attachButton.action = #selector(pickFiles)
        attachButton.toolTip = "Anexar arquivo"
        attachButton.frame = NSRect(x: 0, y: 0, width: 30, height: 24)
        footerView.addSubview(attachButton)

        ocrIndicator = NSTextField(labelWithString: "")
        ocrIndicator.font = Theme.mono(11)
        ocrIndicator.textColor = Theme.accent
        ocrIndicator.isHidden = true
        footerView.addSubview(ocrIndicator)

        hintsView = buildHints()
        footerView.addSubview(hintsView)

        dropOverlay = DashedOverlayView(frame: container.bounds)
        dropOverlay.autoresizingMask = [.width, .height]
        dropOverlay.isHidden = true
        container.addSubview(dropOverlay)

        feedbackView = NSView()
        feedbackView.wantsLayer = true
        feedbackView.layer?.backgroundColor = Theme.bgSolid.cgColor
        feedbackView.autoresizingMask = [.width, .height]
        feedbackView.isHidden = true
        let check = NSImageView()
        check.image = tinted(
            NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Salvo")!
                .withSymbolConfiguration(.init(pointSize: 20, weight: .semibold))!,
            color: Theme.success)
        check.frame = NSRect(x: 0, y: 0, width: 28, height: 28)
        feedbackView.addSubview(check)
        feedbackLabel = NSTextField(labelWithString: "")
        feedbackLabel.font = Theme.mono(11)
        feedbackLabel.textColor = Theme.muted
        feedbackView.addSubview(feedbackLabel)
        feedbackView.identifier = NSUserInterfaceItemIdentifier("feedback")
        container.addSubview(feedbackView)

        relayout()
    }

    private func buildHints() -> NSView {
        let view = FlippedView()
        let cmdChip = KbdChip(symbols: ["command", "return"])
        let saveLabel = NSTextField(labelWithString: "salvar")
        let escChip = KbdChip(text: "esc")
        let closeLabel = NSTextField(labelWithString: "fechar")
        for label in [saveLabel, closeLabel] {
            label.font = Theme.mono(11.5)
            label.textColor = Theme.hintLabel
            label.sizeToFit()
        }
        var x: CGFloat = 0
        let centerY: CGFloat = 12
        for item: NSView in [cmdChip, saveLabel, escChip, closeLabel] {
            view.addSubview(item)
            item.frame.origin = NSPoint(x: x, y: centerY - item.frame.height / 2)
            x += item.frame.width + (item is KbdChip ? 6 : 14)
        }
        view.setFrameSize(NSSize(width: x - 14, height: 24))
        return view
    }

    private func tinted(_ image: NSImage, color: NSColor) -> NSImage {
        let img = image.copy() as! NSImage
        img.lockFocus()
        color.set()
        NSRect(origin: .zero, size: img.size).fill(using: .sourceAtop)
        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    // MARK: layout manual (top-down, container flipped)

    private func textHeight() -> CGFloat {
        guard let lm = textView.layoutManager, let tc = textView.textContainer else { return 60 }
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc).height
        return max(60, min(used + 4, 260))
    }

    private func relayout() {
        let contentWidth = panelWidth - 2 * padding
        var y: CGFloat = 14

        brandLabel.frame.origin = NSPoint(x: panelWidth - padding - brandLabel.frame.width, y: y)

        let tH = textHeight()
        scrollView.frame = NSRect(x: padding, y: y, width: contentWidth, height: tH)
        placeholderLabel.frame.origin = NSPoint(x: padding + 5, y: y + 1)
        y += tH + 4

        slugLabel.frame = NSRect(x: padding, y: y, width: contentWidth - 90, height: 14)
        y += 14 + 4

        if !attachments.isEmpty {
            attachmentsRow.isHidden = false
            attachmentsRow.frame = NSRect(x: padding, y: y, width: contentWidth, height: 38)
            y += 38 + 4
        } else {
            attachmentsRow.isHidden = true
        }

        footerView.frame = NSRect(x: padding, y: y, width: contentWidth, height: 24)
        attachButton.frame = NSRect(x: 0, y: 0, width: 30, height: 24)
        ocrIndicator.sizeToFit()
        ocrIndicator.frame.origin = NSPoint(x: 38, y: 12 - ocrIndicator.frame.height / 2)
        hintsView.frame.origin = NSPoint(x: contentWidth - hintsView.frame.width, y: 0)
        y += 24 + 14

        let newHeight = max(140, min(y, 500))
        var frame = panel.frame
        let topY = frame.maxY
        frame.size.height = newHeight
        frame.origin.y = topY - newHeight
        panel.setFrame(frame, display: true, animate: panel.isVisible)
        container.frame = NSRect(x: 0, y: 0, width: panelWidth, height: newHeight)
        // autoresizingMask não corrige frame inicial zero — cravar sempre
        effectView.frame = container.bounds
        tintView.frame = container.bounds
        dropOverlay.frame = container.bounds
        feedbackView.frame = container.bounds
    }

    // MARK: show/hide

    func showPanel() {
        if !panel.isVisible, let screen = NSScreen.main {
            let v = screen.visibleFrame
            let f = panel.frame
            panel.setFrameOrigin(NSPoint(
                x: v.midX - f.width / 2,
                y: v.midY - f.height / 2 + v.height * 0.08))
        }
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(textView)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.13
            panel.animator().alphaValue = 1
        }
        relayout()
    }

    func hidePanel() {
        panel.orderOut(nil)
    }

    @objc func togglePanel() {
        if panel.isVisible { hidePanel() } else { showPanel() }
    }

    // MARK: NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        placeholderLabel.isHidden = !textView.string.isEmpty
        slugLabel.stringValue = Core.filenamePreview(for: textView.string)
        relayout()
    }

    // MARK: attachments

    private func addAttachment(name: String, data: Data) {
        let ext = (name as NSString).pathExtension.lowercased()
        let isImage = Core.imageExts.contains(ext)
        attachments.append((AttachmentInput(originalName: name, data: data), isImage))
        renderAttachments()
        if isImage { runOcr(on: data) }
    }

    private func addFiles(_ urls: [URL]) {
        for url in urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            addAttachment(name: url.lastPathComponent, data: data)
        }
    }

    @objc private func pickFiles() {
        suppressAutoHide = true
        let dialog = NSOpenPanel()
        dialog.canChooseFiles = true
        dialog.canChooseDirectories = false
        dialog.allowsMultipleSelection = true
        NSApp.activate(ignoringOtherApps: true)
        dialog.begin { [weak self] response in
            self?.suppressAutoHide = false
            self?.panel.makeKeyAndOrderFront(nil)
            self?.panel.makeFirstResponder(self?.textView)
            if response == .OK { self?.addFiles(dialog.urls) }
        }
    }

    @objc private func removeAttachment(_ sender: NSButton) {
        let index = sender.tag
        guard attachments.indices.contains(index) else { return }
        attachments.remove(at: index)
        renderAttachments()
    }

    private func renderAttachments() {
        attachmentsRow.subviews.forEach { $0.removeFromSuperview() }
        var x: CGFloat = 0
        for (i, att) in attachments.enumerated() {
            let chip = FlippedView()
            chip.wantsLayer = true
            chip.layer?.backgroundColor = NSColor(srgbRed: 0x27/255.0, green: 0x27/255.0, blue: 0x2A/255.0, alpha: 0.9).cgColor
            chip.layer?.cornerRadius = 6
            chip.layer?.borderWidth = 1
            chip.layer?.borderColor = Theme.border.cgColor

            var cx: CGFloat = 5
            if att.isImage, let img = NSImage(data: att.input.data) {
                let thumb = NSImageView()
                thumb.image = img
                thumb.imageScaling = .scaleProportionallyUpOrDown
                thumb.wantsLayer = true
                thumb.layer?.cornerRadius = 3
                thumb.layer?.masksToBounds = true
                thumb.frame = NSRect(x: cx, y: 5, width: 22, height: 22)
                chip.addSubview(thumb)
                cx += 27
            } else {
                let icon = NSImageView()
                icon.image = tinted(
                    NSImage(systemSymbolName: "doc", accessibilityDescription: nil)!
                        .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))!,
                    color: Theme.muted)
                icon.frame = NSRect(x: cx, y: 8, width: 14, height: 16)
                chip.addSubview(icon)
                cx += 19
            }

            let name = NSTextField(labelWithString: att.input.originalName)
            name.font = Theme.mono(10.5)
            name.textColor = Theme.muted
            name.lineBreakMode = .byTruncatingMiddle
            name.sizeToFit()
            let nameWidth = min(name.frame.width, 120)
            name.frame = NSRect(x: cx, y: 16 - name.frame.height / 2, width: nameWidth, height: name.frame.height)
            chip.addSubview(name)
            cx += nameWidth + 6

            let remove = NSButton()
            remove.bezelStyle = .regularSquare
            remove.isBordered = false
            remove.title = "×"
            remove.font = Theme.mono(12)
            remove.contentTintColor = Theme.muted.withAlphaComponent(0.6)
            remove.target = self
            remove.action = #selector(removeAttachment(_:))
            remove.tag = i
            remove.frame = NSRect(x: cx, y: 8, width: 16, height: 16)
            chip.addSubview(remove)
            cx += 18

            chip.frame = NSRect(x: x, y: 3, width: cx, height: 32)
            attachmentsRow.addSubview(chip)
            x += cx + 6
        }
        relayout()
    }

    // MARK: OCR

    private func runOcr(on data: Data) {
        ocrPending += 1
        ocrIndicator.stringValue = "Extraindo texto..."
        ocrIndicator.textColor = Theme.accent
        ocrIndicator.isHidden = false
        relayout()
        Core.recognizeText(in: data) { [weak self] text in
            DispatchQueue.main.async {
                guard let self else { return }
                self.ocrPending -= 1
                if let text, !text.isEmpty {
                    if self.ocrPending == 0 { self.ocrIndicator.isHidden = true }
                    self.textView.string = Core.ocrBlock(existingText: self.textView.string, ocrText: text)
                    self.textDidChange(Notification(name: NSText.didChangeNotification))
                } else if self.ocrPending == 0 {
                    self.ocrIndicator.stringValue = "OCR falhou"
                    self.ocrIndicator.textColor = Theme.danger
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        self.ocrIndicator.isHidden = true
                        self.relayout()
                    }
                }
                self.relayout()
            }
        }
    }

    // MARK: drop overlay

    private func setDropOverlay(visible: Bool) {
        dropOverlay.isHidden = !visible
    }

    // MARK: save

    private func save() {
        guard !isSaving else { return }
        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }

        let vault = Config.vaultPath
        do {
            let filename = try Core.saveNote(
                text: text.isEmpty ? "Nota sem texto" : text,
                attachments: attachments.map(\.input),
                vault: vault)
            Core.gitCommitAndPush(vault: vault, message: "capture-app: \(filename)")
            textView.string = ""
            attachments = []
            renderAttachments()
            placeholderLabel.isHidden = false
            slugLabel.stringValue = ""
            showFeedback(filename: filename)
        } catch let error as SaveError {
            if case .missingMarker = error {
                showMarkerAlert(vault: vault)
            } else {
                showErrorAlert("\(error)")
            }
            Config.log("save fail: \(error)")
        } catch {
            showErrorAlert(error.localizedDescription)
            Config.log("save fail: \(error)")
        }
    }

    private func showFeedback(filename: String) {
        feedbackLabel.stringValue = filename
        feedbackLabel.sizeToFit()
        let check = feedbackView.subviews.first { $0 is NSImageView }
        let totalW = 28 + 8 + feedbackLabel.frame.width
        let bounds = container.bounds
        check?.frame.origin = NSPoint(x: (bounds.width - totalW) / 2, y: bounds.height / 2 - 14)
        feedbackLabel.frame.origin = NSPoint(
            x: (bounds.width - totalW) / 2 + 36,
            y: bounds.height / 2 - feedbackLabel.frame.height / 2)
        feedbackView.isHidden = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in
            self?.feedbackView.isHidden = true
            self?.hidePanel()
            self?.relayout()
        }
    }

    private func showMarkerAlert(vault: String) {
        suppressAutoHide = true
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Vault errado — nada foi salvo"
        alert.informativeText = "O marker .omninox-vault não existe em:\n\(vault)\n\nEssa não é a árvore canônica do OmniNox. Salvar aqui criaria um split-brain."
        alert.addButton(withTitle: "Mudar vault…")
        alert.addButton(withTitle: "Cancelar")
        let response = alert.runModal()
        suppressAutoHide = false
        if response == .alertFirstButtonReturn { changeVault() }
    }

    private func showErrorAlert(_ message: String) {
        suppressAutoHide = true
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Falha ao salvar"
        alert.informativeText = message
        alert.runModal()
        suppressAutoHide = false
    }

    // MARK: tray

    private func buildTray() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let iconPath = Bundle.main.path(forResource: "iconTemplate", ofType: "png")
            if let iconPath, let icon = NSImage(contentsOfFile: iconPath) {
                icon.isTemplate = true
                icon.size = NSSize(width: 18, height: 18)
                button.image = icon
            } else {
                button.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "OmniNox")
            }
            button.toolTip = "OmniNox Capture — arraste arquivos aqui"
            let catcher = TrayDragView(frame: button.bounds)
            catcher.autoresizingMask = [.width, .height]
            catcher.onClick = { [weak self] in self?.togglePanel() }
            catcher.onRightClick = { [weak self] in self?.showTrayMenu() }
            catcher.onFilesDropped = { [weak self] urls in
                self?.showPanel()
                self?.addFiles(urls)
            }
            button.addSubview(catcher)
        }
        rebuildTrayMenu()
    }

    private func rebuildTrayMenu() {
        trayMenu = NSMenu()
        let capture = NSMenuItem(title: "Capture (⌘⇧N)", action: #selector(menuShowPanel), keyEquivalent: "")
        capture.target = self
        trayMenu.addItem(capture)
        trayMenu.addItem(.separator())

        let vault = Config.vaultPath
        let markerOk = FileManager.default.fileExists(atPath: vault + "/.omninox-vault")
        let vaultLabel = markerOk
            ? "Vault: \((vault as NSString).lastPathComponent)"
            : "⚠️ Vault sem marker: \((vault as NSString).lastPathComponent)"
        let vaultItem = NSMenuItem(title: vaultLabel, action: nil, keyEquivalent: "")
        vaultItem.isEnabled = false
        trayMenu.addItem(vaultItem)

        let change = NSMenuItem(title: "Mudar vault…", action: #selector(menuChangeVault), keyEquivalent: "")
        change.target = self
        trayMenu.addItem(change)
        trayMenu.addItem(.separator())

        let login = NSMenuItem(title: "Abrir no login", action: #selector(menuToggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        trayMenu.addItem(login)
        trayMenu.addItem(.separator())

        let quit = NSMenuItem(title: "Sair", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        trayMenu.addItem(quit)
    }

    private func showTrayMenu() {
        rebuildTrayMenu()
        statusItem.menu = trayMenu
        statusItem.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in self?.statusItem.menu = nil }
    }

    @objc private func menuShowPanel() { showPanel() }

    @objc private func menuChangeVault() { changeVault() }

    private func changeVault() {
        suppressAutoHide = true
        NSApp.activate(ignoringOtherApps: true)
        let dialog = NSOpenPanel()
        dialog.title = "Selecionar pasta do vault Obsidian"
        dialog.canChooseFiles = false
        dialog.canChooseDirectories = true
        dialog.allowsMultipleSelection = false
        dialog.directoryURL = URL(fileURLWithPath: Config.vaultPath)
        dialog.prompt = "Selecionar vault"
        let response = dialog.runModal()
        suppressAutoHide = false
        if response == .OK, let url = dialog.urls.first {
            let path = url.path
            if !FileManager.default.fileExists(atPath: path + "/.omninox-vault") {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Pasta sem marker .omninox-vault"
                alert.informativeText = "Essa pasta não é o vault canônico do OmniNox. Selecionar mesmo assim?"
                alert.addButton(withTitle: "Cancelar")
                alert.addButton(withTitle: "Usar mesmo assim")
                if alert.runModal() == .alertFirstButtonReturn { return }
            }
            Config.vaultPath = path
            rebuildTrayMenu()
        }
    }

    @objc private func menuToggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            Config.log("login item toggle fail: \(error)")
        }
        rebuildTrayMenu()
    }

    private func firstRunLoginItem() {
        var config = Config.load()
        guard config["firstRunDone"] as? Bool != true else { return }
        config["firstRunDone"] = true
        Config.save(config)
        try? SMAppService.mainApp.register()
    }

    // MARK: hotkey global (Carbon — não exige permissão de acessibilidade)

    private func registerHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async { AppDelegate.shared?.togglePanel() }
            return noErr
        }, 1, &eventType, nil, nil)
        let hotKeyID = EventHotKeyID(signature: 0x4F4D4E58, id: 1) // 'OMNX'
        RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(cmdKey | shiftKey), hotKeyID,
                            GetEventDispatcherTarget(), 0, &hotKeyRef)
    }

    // MARK: snapshot (verificação visual headless via cacheDisplay)

    private func renderSnapshot(to path: String) {
        if !CommandLine.arguments.contains("--empty") {
            textView.string = "Ideia pro hub de keynotes: cards com preview\ne um gate de senha único"
            textDidChange(Notification(name: NSText.didChangeNotification))
        }
        showPanel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, let view = self.panel.contentView else { NSApp.terminate(nil); return }
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { NSApp.terminate(nil); return }
            view.cacheDisplay(in: view.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path))
            }
            NSApp.terminate(nil)
        }
    }
}

// MARK: - Tray drag catcher

final class TrayDragView: NSView {
    var onClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    var onFilesDropped: (([URL]) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseUp(with event: NSEvent) { onClick?() }
    override func rightMouseUp(with event: NSEvent) { onRightClick?() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard !urls.isEmpty else { return false }
        onFilesDropped?(urls)
        return true
    }
}

// MARK: - Self-test headless

enum SelfTest {
    static func run(vault: String) -> Bool {
        var passed = 0, failed = 0
        func check(_ name: String, _ condition: Bool, _ detail: String = "") {
            if condition { passed += 1; print("PASS \(name)") }
            else { failed += 1; print("FAIL \(name) \(detail)") }
        }

        // slugify (paridade com o JS)
        check("slugify básico", Core.slugify("Olá Mundo! Teste") == "ola-mundo-teste")
        check("slugify acentos", Core.slugify("Acentuação çãé àê") == "acentuacao-cae-ae")
        check("slugify trunca em palavra",
              Core.slugify("uma frase bem longa que passa de trinta caracteres") == "uma-frase-bem-longa-que-passa",
              Core.slugify("uma frase bem longa que passa de trinta caracteres"))
        check("slugify vazio", Core.slugify("!!!") == "")

        // merge OCR
        let merged = Core.mergeOcrLines("Primeira frase que\nquebrou no wrap.\nSegunda frase.")
        check("ocr merge junta wrap", merged == ["Primeira frase que quebrou no wrap.", "Segunda frase."], "\(merged)")
        let block = Core.ocrBlock(existingText: "nota", ocrText: "linha um.")
        check("ocr block separador", block == "nota\n\n---\n> **Texto extraído:**\n> linha um.", block)
        let blockEmpty = Core.ocrBlock(existingText: "", ocrText: "linha um.")
        check("ocr block sem texto", blockEmpty == "> linha um.", blockEmpty)

        // marker ausente → recusa
        let noMarker = NSTemporaryDirectory() + "omninox-test-nomarker-\(ProcessInfo.processInfo.processIdentifier)"
        try? FileManager.default.createDirectory(atPath: noMarker, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: noMarker) }
        do {
            try Core.saveNote(text: "x", attachments: [], vault: noMarker)
            check("marker ausente recusa", false)
        } catch let e as SaveError {
            if case .missingMarker = e { check("marker ausente recusa", true) }
            else { check("marker ausente recusa", false, "\(e)") }
        } catch { check("marker ausente recusa", false, "\(error)") }

        // save real no vault de teste
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        do {
            let f1 = try Core.saveNote(
                text: "# Nota de Teste do Selftest\ncorpo da nota",
                attachments: [AttachmentInput(originalName: "print da tela.png", data: png)],
                vault: vault)
            check("save cria arquivo", FileManager.default.fileExists(atPath: vault + "/00 Inbox/" + f1))
            let content = (try? String(contentsOfFile: vault + "/00 Inbox/" + f1, encoding: .utf8)) ?? ""
            check("frontmatter", content.hasPrefix("---\ntags:\n  - status/inbox\ndate: "))
            check("embed do attachment", content.contains("![[attachments/") && content.contains("print-da-tela.png]]"))
            check("titulo sem hashes", f1.contains("nota-de-teste-do-selftest"))

            // colisão de filename no mesmo minuto
            let f2 = try Core.saveNote(text: "# Nota de Teste do Selftest\noutra", attachments: [], vault: vault)
            check("colisão -2", f2 != f1 && f2.contains("-2.md"), f2)

            // git commit síncrono
            Core.gitCommitAndPush(vault: vault, message: "capture-app: selftest", synchronous: true)
            let log = Core.run("/usr/bin/git", ["-C", vault, "log", "--oneline", "-1"])
            check("git commit", log.stdout.contains("capture-app: selftest"), log.stdout)
        } catch {
            check("save no vault de teste", false, "\(error)")
        }

        // OCR de verdade (Vision) numa imagem renderizada
        let ocrImage = renderTextImage("OmniNox teste 123")
        let sema = DispatchSemaphore(value: 0)
        var ocrResult: String?
        Core.recognizeText(in: ocrImage) { text in ocrResult = text; sema.signal() }
        _ = sema.wait(timeout: .now() + 15)
        check("vision OCR", ocrResult?.contains("OmniNox") == true, ocrResult ?? "nil")

        print("\n\(passed) passed, \(failed) failed")
        return failed == 0
    }

    static func renderTextImage(_ text: String) -> Data {
        let size = NSSize(width: 400, height: 80)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        (text as NSString).draw(
            at: NSPoint(x: 20, y: 25),
            withAttributes: [.font: NSFont.systemFont(ofSize: 28, weight: .semibold), .foregroundColor: NSColor.black])
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return rep.representation(using: .png, properties: [:])!
    }
}

// MARK: - Main

@main
enum Main {
    static func main() {
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--selftest") {
            guard args.count > idx + 1 else {
                print("uso: --selftest <vault-de-teste>")
                exit(1)
            }
            exit(SelfTest.run(vault: args[idx + 1]) ? 0 : 1)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
