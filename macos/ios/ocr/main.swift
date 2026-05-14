import Foundation
import Vision
import AppKit   // 用于加载 NSImage

func recognizeText(from imageURL: URL) {
    guard let nsImage = NSImage(contentsOf: imageURL) else {
        print("无法加载图片: \(imageURL.path)")
        return
    }
    guard let tiffData = nsImage.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let cgImage = bitmap.cgImage else {
        print("无法转换为 CGImage")
        return
    }

    // 1. 创建识别请求
    let request = VNRecognizeTextRequest { request, error in
        if let error = error {
            print("识别出错: \(error)")
            return
        }
        guard let observations = request.results as? [VNRecognizedTextObservation] else {
            print("无结果")
            return
        }
        let lines = observations.compactMap { obs in
            obs.topCandidates(1).first?.string
        }
        print(lines.joined(separator: "\n"))
    }

    // 2. 配置识别参数
    request.recognitionLevel = .accurate          // .fast 或 .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = ["zh-Hans", "en"] // 简体中文 + 英文[web:204]

    // 3. 运行请求
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do {
        try handler.perform([request])
    } catch {
        print("执行识别失败: \(error)")
    }
}

// 从命令行获取图片路径
let args = CommandLine.arguments
guard args.count > 1 else {
    print("用法: MacOCR /path/to/image.png")
    exit(1)
}
let path = args[1]
let url = URL(fileURLWithPath: path)
recognizeText(from: url)
RunLoop.current.run(until: Date(timeIntervalSinceNow: 3))

