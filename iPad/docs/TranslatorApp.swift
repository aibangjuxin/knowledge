import SwiftUI
import Foundation
import CommonCrypto

// 加密函数
import CommonCrypto

func sha256(_ string: String) -> String {
    let data = Data(string.utf8)
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes { buffer in
        _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
    }
    return hash.map { String(format: "%02x", $0) }.joined()
}

// 翻译工具类
class Translator: ObservableObject {
    let appid = "20"
    let secretKey = "yd"
    @Published var translatedText = ""
    @Published var isLoading = false
    
    func translate(text: String, from sourceLanguage: String, to targetLanguage: String) {
        guard !text.isEmpty else { return }
        
        isLoading = true
        let apiURL = URL(string: "https://fanyi-api.baidu.com/api/trans/vip/translate")!
        let salt = String(Int.random(in: 10000...99999))
        let sign = sha256(appid + text + salt + secretKey)
        
        var components = URLComponents(url: apiURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "from", value: sourceLanguage),
            URLQueryItem(name: "to", value: targetLanguage),
            URLQueryItem(name: "appid", value: appid),
            URLQueryItem(name: "salt", value: salt),
            URLQueryItem(name: "sign", value: sign)
        ]
        
        guard let url = components.url else { return }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.translatedText = "翻译错误: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    self?.translatedText = "无数据返回"
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let results = json["trans_result"] as? [[String: Any]],
                       let firstResult = results.first,
                       let translatedText = firstResult["dst"] as? String {
                        self?.translatedText = translatedText
                    }
                } catch {
                    self?.translatedText = "解析错误: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
}

// 主视图
struct ContentView: View {
    @StateObject private var translator = Translator()
    @State private var inputText = ""
    @State private var sourceLanguage = "auto"
    @State private var targetLanguage = "zh"
    
    let languages = [
        ("auto", "自动检测"),
        ("zh", "中文"),
        ("en", "英文"),
        ("jp", "日语"),
        ("kor", "韩语"),
        ("fra", "法语"),
        ("spa", "西班牙语")
    ]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                HStack {
                    Picker("源语言", selection: $sourceLanguage) {
                        ForEach(languages, id: \.0) { lang in
                            Text(lang.1).tag(lang.0)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    
                    Image(systemName: "arrow.right")
                    
                    Picker("目标语言", selection: $targetLanguage) {
                        ForEach(languages, id: \.0) { lang in
                            Text(lang.1).tag(lang.0)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                .padding()
                
                TextEditor(text: $inputText)
                    .frame(height: 100)
                    .padding()
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))
                
                Button(action: {
                    translator.translate(text: inputText, from: sourceLanguage, to: targetLanguage)
                }) {
                    Text("翻译")
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(8)
                }
                .disabled(inputText.isEmpty || translator.isLoading)
                
                if translator.isLoading {
                    ProgressView()
                }
                
                Text(translator.translatedText)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))
                
                Spacer()
            }
            .padding()
            .navigationTitle("翻译工具")
        }
    }
}

// 应用入口
@main
struct TranslatorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}