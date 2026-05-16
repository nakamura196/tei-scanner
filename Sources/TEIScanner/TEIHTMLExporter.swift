import Foundation

/// Renders a TEI document to a standalone HTML page by applying a small
/// XSLT 1.0 stylesheet. The bundle export writes the result as `index.html`
/// next to `tei.xml` and `images/`, so a reviewer can eyeball the OCR text
/// against each page image without opening the TEI/IIIF editor.
///
/// The transform runs in-process through `XMLDocument` (libxslt); no IIIF
/// server, network access, or external tool is involved.
enum TEIHTMLExporter {

    enum ExportError: LocalizedError {
        case transformProducedNothing
        var errorDescription: String? {
            switch self {
            case .transformProducedNothing:
                return "The TEI document could not be transformed to HTML."
            }
        }
    }

    /// Apply `stylesheet` to `teiXML` and return a complete HTML5 document.
    static func renderHTML(fromTEI teiXML: String) throws -> String {
        // Preserve whitespace so an empty OCR line keeps the (whitespace-only)
        // text node after its `<lb/>`; otherwise line-to-text alignment shifts.
        let teiDoc = try XMLDocument(xmlString: teiXML, options: [.nodePreserveWhitespace])
        let result = try teiDoc.object(byApplyingXSLTString: stylesheet, arguments: nil)

        let rendered: String
        switch result {
        case let doc as XMLDocument: rendered = doc.xmlString
        case let node as XMLNode: rendered = node.xmlString
        default: throw ExportError.transformProducedNothing
        }
        return standaloneHTML(from: rendered)
    }

    /// Drop any XML declaration / DOCTYPE the serializer prepended and emit a
    /// clean HTML5 document, so browsers render it in standards mode.
    private static func standaloneHTML(from raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("<?xml"), let end = s.range(of: "?>") {
            s = String(s[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if s.lowercased().hasPrefix("<!doctype"), let end = s.range(of: ">") {
            s = String(s[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "<!DOCTYPE html>\n" + s + "\n"
    }

    // MARK: - Stylesheet

    /// A deliberately small XSLT 1.0 stylesheet: for each `<pb>` it lays out the
    /// page image beside the numbered OCR lines that follow it (lines are
    /// grouped to their page by their nearest preceding `<pb>` sibling — the
    /// structure `TEIBuilder` emits). `<graphic url>` is relative (`images/…`),
    /// so the page resolves against the bundle when opened from its folder.
    static let stylesheet: String = #"""
    <?xml version="1.0" encoding="UTF-8"?>
    <xsl:stylesheet version="1.0"
        xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
        xmlns:tei="http://www.tei-c.org/ns/1.0"
        exclude-result-prefixes="tei">

      <xsl:output method="html" encoding="UTF-8" indent="yes"/>

      <!-- `xml:id` is matched by local name: Apple's XMLDocument surfaces it
           as a plain `id` attribute (the `xml` namespace is dropped), while
           xsltproc keeps it namespaced — `local-name()` covers both. -->
      <xsl:key name="surface-by-id" match="tei:surface"
          use="@*[local-name() = 'id']"/>

      <xsl:variable name="title" select="normalize-space(//tei:titleStmt/tei:title)"/>

      <xsl:template match="/">
        <html lang="{//tei:TEI/@*[local-name() = 'lang']}">
          <head>
            <meta charset="UTF-8"/>
            <meta name="viewport" content="width=device-width, initial-scale=1"/>
            <title><xsl:value-of select="$title"/> — TEI preview</title>
            <style>
              body { font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
                     margin: 0; color: #1a1a1a; background: #fafafa; }
              header { padding: 1.5rem 2rem; background: #fff; border-bottom: 1px solid #ddd; }
              header h1 { margin: 0 0 .35rem; font-size: 1.35rem; }
              .meta { margin: 0; color: #666; font-size: .85rem; }
              .meta span { margin-right: 1.25rem; }
              .page { padding: 1.5rem 2rem; border-bottom: 1px solid #ececec; }
              .page h2 { margin: 0 0 .75rem; font-size: .95rem; color: #555;
                         text-transform: uppercase; letter-spacing: .04em; }
              .page-grid { display: flex; gap: 1.5rem; align-items: flex-start; }
              .image-col { flex: 1 1 50%; }
              .image-col img { max-width: 100%; height: auto;
                               border: 1px solid #ccc; background: #fff; }
              .lines { flex: 1 1 50%; margin: 0; padding: 0; list-style: none; }
              .lines li { display: flex; gap: .75rem; padding: .2rem 0;
                          border-bottom: 1px dotted #e3e3e3; font-size: .95rem; }
              .lineno { flex: 0 0 2.25rem; text-align: right;
                        color: #aaa; font-variant-numeric: tabular-nums; }
              .linetext { white-space: pre-wrap; word-break: break-word; }
              .empty { color: #bbb; }
              @media (max-width: 760px) { .page-grid { flex-direction: column; } }
            </style>
          </head>
          <body>
            <header>
              <h1><xsl:value-of select="$title"/></h1>
              <p class="meta">
                <xsl:if test="normalize-space(//tei:respStmt/tei:name) != ''">
                  <span>Resp: <xsl:value-of select="//tei:respStmt/tei:name"/></span>
                </xsl:if>
                <xsl:if test="//tei:publicationStmt/tei:date/@when">
                  <span>Date: <xsl:value-of select="//tei:publicationStmt/tei:date/@when"/></span>
                </xsl:if>
                <span>Pages: <xsl:value-of select="count(//tei:body//tei:pb)"/></span>
              </p>
            </header>
            <xsl:apply-templates select="//tei:body//tei:pb"/>
          </body>
        </html>
      </xsl:template>

      <xsl:template match="tei:pb">
        <xsl:variable name="surface"
            select="key('surface-by-id', substring-after(@facs, '#'))"/>
        <section class="page">
          <h2>Page <xsl:value-of select="@n"/></h2>
          <div class="page-grid">
            <div class="image-col">
              <xsl:if test="$surface/tei:graphic/@url">
                <img src="{$surface/tei:graphic/@url}" alt="Page {@n}"/>
              </xsl:if>
            </div>
            <ol class="lines">
              <xsl:for-each select="following-sibling::tei:lb[
                  generate-id(preceding-sibling::tei:pb[1]) = generate-id(current())]">
                <xsl:variable name="text"
                    select="normalize-space(following-sibling::text()[1])"/>
                <li>
                  <span class="lineno"><xsl:value-of select="@n"/></span>
                  <xsl:choose>
                    <xsl:when test="$text != ''">
                      <span class="linetext"><xsl:value-of select="$text"/></span>
                    </xsl:when>
                    <xsl:otherwise>
                      <span class="linetext empty">(empty)</span>
                    </xsl:otherwise>
                  </xsl:choose>
                </li>
              </xsl:for-each>
            </ol>
          </div>
        </section>
      </xsl:template>

    </xsl:stylesheet>
    """#
}
