➜ ocr git:(main) ✗ swift main.swift
用法: MacOCR /path/to/image.png
➜ ocr git:(main) ✗ swift main.swift /Users/lex/Downloads/1.png

# Xcode 里 Product → Run 可以直接跑

# 或者在构建出的可执行文件所在目录

./MacOCR /Users/you/Desktop/test.png



swiftc DropOCR.swift -o DropOCR -framework Cocoa -framework Vision && mkdir -p DropOCR.app/Contents/MacOS && mv DropOCR DropOCR.app/Contents/MacOS/ && echo '<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>图片OCR</string>
  <key>CFBundleDisplayName</key>
  <string>图片OCR</string>
  <key>CFBundleVersion</key>
  <string>1.0</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleSignature</key>
  <string>????</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict>
</plist>' > DropOCR.app/Contents/Info.plist