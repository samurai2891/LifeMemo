import Foundation
import UIKit

/// Generates PDF documents from export models.
///
/// Uses UIKit's PDF rendering context to create formatted PDF documents
/// with proper typography, headers, and page breaks.
enum PDFExporter {

    // MARK: - Public API

    static func make(model: ExportModel, options: ExportOptions) -> Data {
        let pageWidth: CGFloat = 612  // US Letter
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 50
        let contentWidth = pageWidth - margin * 2

        let pdfData = NSMutableData()

        UIGraphicsBeginPDFContextToData(
            pdfData,
            CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight),
            pdfMetadata(title: model.title)
        )

        var renderer = PDFPageRenderer(
            pageWidth: pageWidth,
            pageHeight: pageHeight,
            margin: margin,
            contentWidth: contentWidth
        )

        renderer.beginNewPage()

        renderTitle(model: model, renderer: &renderer)
        renderMetadata(model: model, options: options, renderer: &renderer)
        renderSeparator(renderer: &renderer)
        renderSummary(model: model, options: options, renderer: &renderer)
        renderHighlights(model: model, options: options, renderer: &renderer)
        renderTranscript(model: model, options: options, renderer: &renderer)

        UIGraphicsEndPDFContext()
        return pdfData as Data
    }

    // MARK: - Section Renderers

    private static func renderTitle(model: ExportModel, renderer: inout PDFPageRenderer) {
        renderer.drawText(
            model.title,
            font: UIFont.systemFont(ofSize: 24, weight: .bold),
            color: .black
        )
        renderer.advance(8)
    }

    private static func renderMetadata(
        model: ExportModel,
        options: ExportOptions,
        renderer: inout PDFPageRenderer
    ) {
        guard options.includeMetadata else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        let meta = [
            "Started: \(formatter.string(from: model.startedAt))",
            model.endedAt.map { "Ended: \(formatter.string(from: $0))" },
            "Language: \(model.languageMode)",
            "Audio: \(model.audioKept ? "Kept" : "Deleted")"
        ].compactMap { $0 }

        for line in meta {
            renderer.drawText(line, font: .systemFont(ofSize: 11), color: .darkGray)
        }
        renderer.advance(16)
    }

    private static func renderSeparator(renderer: inout PDFPageRenderer) {
        renderer.drawSeparator()
        renderer.advance(16)
    }

    private static func renderSummary(
        model: ExportModel,
        options: ExportOptions,
        renderer: inout PDFPageRenderer
    ) {
        guard options.includeSummary,
              let summary = model.summaryMarkdown,
              !summary.isEmpty else { return }

        renderer.drawText(
            "Summary",
            font: .systemFont(ofSize: 18, weight: .semibold),
            color: .black
        )
        renderer.advance(8)

        // Strip markdown formatting for PDF
        let plainSummary = stripMarkdown(summary)
        renderer.drawText(plainSummary, font: .systemFont(ofSize: 11), color: .darkGray)
        renderer.advance(16)
    }

    private static func renderHighlights(
        model: ExportModel,
        options: ExportOptions,
        renderer: inout PDFPageRenderer
    ) {
        guard options.includeHighlights, !model.highlights.isEmpty else { return }

        renderer.drawText(
            "Highlights",
            font: .systemFont(ofSize: 18, weight: .semibold),
            color: .black
        )
        renderer.advance(8)

        for highlight in model.highlights {
            let text = formatHighlight(highlight)
            renderer.drawText(text, font: .systemFont(ofSize: 11), color: .darkGray)
        }
        renderer.advance(16)
    }

    private static func renderTranscript(
        model: ExportModel,
        options: ExportOptions,
        renderer: inout PDFPageRenderer
    ) {
        guard options.includeTranscript, !model.fullTranscript.isEmpty else { return }

        renderer.drawText(
            "Transcript",
            font: .systemFont(ofSize: 18, weight: .semibold),
            color: .black
        )
        renderer.advance(8)

        let paragraphs = model.fullTranscript.components(separatedBy: "\n")
        for paragraph in paragraphs {
            guard !paragraph.trimmingCharacters(in: .whitespaces).isEmpty else {
                renderer.advance(6)
                continue
            }
            renderer.drawText(paragraph, font: .systemFont(ofSize: 11), color: .black)
            renderer.advance(2)
        }
    }

    // MARK: - Helpers

    private static func pdfMetadata(title: String) -> [String: Any] {
        [
            kCGPDFContextTitle as String: title,
            kCGPDFContextCreator as String: "LifeMemo",
            kCGPDFContextAuthor as String: "LifeMemo App"
        ]
    }

    private static func stripMarkdown(_ text: String) -> String {
        text
            .replacingOccurrences(of: "# ", with: "")
            .replacingOccurrences(of: "## ", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "- ", with: "  \u{2022} ")
    }

    private static func formatHighlight(_ highlight: HighlightInfo) -> String {
        let sec = highlight.atMs / 1000
        let min = sec / 60
        let remSec = sec % 60
        let label = highlight.label ?? ""
        return "[\(String(format: "%02d:%02d", min, remSec))] \(label)"
    }
}

// MARK: - PDF Page Renderer

/// Tracks vertical position within PDF pages and handles page breaks automatically.
private struct PDFPageRenderer {

    let pageWidth: CGFloat
    let pageHeight: CGFloat
    let margin: CGFloat
    let contentWidth: CGFloat

    private var currentY: CGFloat = 0
    private let bottomMargin: CGFloat = 70

    init(pageWidth: CGFloat, pageHeight: CGFloat, margin: CGFloat, contentWidth: CGFloat) {
        self.pageWidth = pageWidth
        self.pageHeight = pageHeight
        self.margin = margin
        self.contentWidth = contentWidth
    }

    mutating func beginNewPage() {
        UIGraphicsBeginPDFPage()
        currentY = margin
    }

    mutating func drawText(_ text: String, font: UIFont, color: UIColor) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]

        let maxSize = CGSize(width: contentWidth, height: .greatestFiniteMagnitude)
        let boundingRect = (text as NSString).boundingRect(
            with: maxSize,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )

        // Check if we need a new page
        if currentY + boundingRect.height > pageHeight - bottomMargin {
            beginNewPage()
        }

        let drawRect = CGRect(
            x: margin,
            y: currentY,
            width: contentWidth,
            height: boundingRect.height
        )
        (text as NSString).draw(in: drawRect, withAttributes: attributes)
        currentY += boundingRect.height
    }

    mutating func advance(_ points: CGFloat) {
        currentY += points
        if currentY > pageHeight - bottomMargin {
            beginNewPage()
        }
    }

    mutating func drawSeparator() {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setStrokeColor(UIColor.lightGray.cgColor)
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: margin, y: currentY))
        context.addLine(to: CGPoint(x: pageWidth - margin, y: currentY))
        context.strokePath()
        currentY += 1
    }
}
