import Foundation
import AppKit

func main() {
    let args = CommandLine.arguments
    guard args.count >= 3 else {
        fputs("Usage: doc2pdf-mac <input-file> <output-pdf>\n", stderr)
        exit(1)
    }

    let inputPath = args[1]
    let outputPath = args[2]

    let inputURL = URL(fileURLWithPath: inputPath)
    let outputURL = URL(fileURLWithPath: outputPath)

    guard FileManager.default.fileExists(atPath: inputURL.path) else {
        fputs("Error: Input file does not exist: \(inputPath)\n", stderr)
        exit(2)
    }

    var docAttr: NSDictionary?
    guard let attr = (try? NSAttributedString(url: inputURL, options: [:], documentAttributes: &docAttr)) else {
        fputs("Error: Unable to parse document with AppKit: \(inputPath)\n", stderr)
        exit(3)
    }

    let mut = NSMutableAttributedString(attributedString: attr)

    // Remove duplicate bullets:
    // When Cocoa imports documents with options: [:], the text string often already contains
    // the bullet characters and tab stops (e.g. \t•\t). If ps.textLists is also set,
    // NSTextView renders a second bullet marker in front of the text.
    // If the text already contains a bullet, clear ps.textLists so only ONE bullet is rendered.
    mut.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: mut.length)) { val, rng, _ in
        if let ps = val as? NSParagraphStyle, !ps.textLists.isEmpty {
            let textSub = (mut.string as NSString).substring(with: rng)
            if textSub.contains("•") || textSub.contains("◦") || textSub.contains("▪") ||
               textSub.contains("‣") || textSub.contains("\t•\t") || textSub.contains("\t•") {
                let mps = ps.mutableCopy() as! NSMutableParagraphStyle
                mps.textLists = []
                mut.addAttribute(.paragraphStyle, value: mps, range: rng)
            }
        }
    }

    // Determine Page Size (Default A4: 595.2 x 841.8 pt)
    var pageWidth: CGFloat = 595.2
    var pageHeight: CGFloat = 841.8
    if let paperVal = docAttr?[NSAttributedString.DocumentAttributeKey.paperSize] as? NSValue {
        let sz = paperVal.sizeValue
        if sz.width >= 200 && sz.height >= 200 {
            pageWidth = sz.width
            pageHeight = sz.height
        }
    }

    let margin: CGFloat = 36.0 // 0.5 inch
    let contentWidth = max(pageWidth - (margin * 2), 200)
    let contentHeight = max(pageHeight - (margin * 2), 200)

    let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
    printInfo.paperSize = NSSize(width: pageWidth, height: pageHeight)
    printInfo.topMargin = margin
    printInfo.bottomMargin = margin
    printInfo.leftMargin = margin
    printInfo.rightMargin = margin
    printInfo.isVerticallyCentered = false
    printInfo.isHorizontallyCentered = false
    printInfo.jobDisposition = .save
    printInfo.dictionary().setObject(outputURL, forKey: NSPrintInfo.AttributeKey.jobSavingURL as NSCopying)

    // Text Container & Layout Manager
    let textStorage = NSTextStorage(attributedString: mut)
    let layoutManager = NSLayoutManager()
    textStorage.addLayoutManager(layoutManager)

    let textContainer = NSTextContainer(size: NSSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude))
    textContainer.widthTracksTextView = true
    textContainer.lineFragmentPadding = 0
    layoutManager.addTextContainer(textContainer)

    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight), textContainer: textContainer)
    textView.isHorizontallyResizable = false
    textView.isVerticallyResizable = true
    textView.autoresizingMask = [.width]

    layoutManager.glyphRange(for: textContainer)
    let usedRect = layoutManager.usedRect(for: textContainer)
    textView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: max(usedRect.height, contentHeight))

    let printOp = NSPrintOperation(view: textView, printInfo: printInfo)
    printOp.showsPrintPanel = false
    printOp.showsProgressPanel = false

    guard printOp.run() else {
        fputs("Error: NSPrintOperation failed\n", stderr)
        exit(4)
    }

    let fileSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path))?[.size] as? UInt64 ?? 0
    guard FileManager.default.fileExists(atPath: outputURL.path), fileSize > 0 else {
        fputs("Error: PDF output was not created or is empty\n", stderr)
        exit(5)
    }

    exit(0)
}

main()
