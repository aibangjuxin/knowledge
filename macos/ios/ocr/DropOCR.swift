import Cocoa
import Vision

class DropView: NSView {
    var textView: NSTextView!
    
    init(frame: NSRect, textView: NSTextView) {
        self.textView = textView
        super.init(frame: frame)
        setupDrop()
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    func setupDrop() {
        registerForDraggedTypes([.fileURL])
        layer?.backgroundColor = NSColor.darkGray.cgColor
        layer?.cornerRadius = 8
    }
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = sender.fileURL else { return false }
        recognizeText(url: url)
        return true
    }
    
    func recognizeText(url: URL) {
        let req = VNRecognizeTextRequest { req, err in
            if let err = err {
                self.textView.string = "错误：\(err.localizedDescription)"
                return
            }
            
            var result = ""
            for obs in req.results as! [VNRecognizedTextObservation] {
                guard let candidate = obs.topCandidates(1).first else { continue }
                result += candidate.string + "\n"
            }
            
            DispatchQueue.main.async {
                self.textView.string = result.isEmpty ? "未识别到文字" : result
            }
        }
        
        req.recognitionLanguages = ["zh-Hans", "en-US"]
        req.usesLanguageCorrection = true
        
        try? VNImageRequestHandler(url: url, options: [:]).perform([req])
    }
}

extension NSDraggingInfo {
    var fileURL: URL? {
        let pboard = draggingPasteboard
        return pboard.readObjects(forClasses: [NSURL.self], options: nil)?.first as? URL
    }
}

// MARK: - APP 主入口
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "🖼️ 拖入图片 OCR 工具"
        win.center()
        win.makeKeyAndOrderFront(nil)
        window = win
        
        let textView = NSTextView(frame: .zero)
        textView.font = .systemFont(ofSize: 16)
        textView.isEditable = false
        textView.backgroundColor = NSColor(white: 0.1, alpha: 1)
        textView.textColor = .white
        textView.string = "👉 把图片拖到上方灰色区域即可识别文字"
        
        let scroll = NSScrollView(frame: .zero)
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        
        let dropView = DropView(frame: .zero, textView: textView)
        
        let stack = NSStackView(views: [dropView, scroll])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -20),
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -20),
            dropView.heightAnchor.constraint(equalToConstant: 180)
        ])
    }
}

// 启动APP
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
