import Foundation

/// Static `index.html` written into every exported bundle.
///
/// `index.html` renders `tei.xml` **live** in the browser: it embeds an
/// XSLT 1.0 stylesheet and runs it with the browser's built-in
/// `XSLTProcessor` against the current `tei.xml`. Editing `tei.xml` and
/// reloading updates the view — no re-export needed.
///
/// - Served over HTTP (e.g. `python3 -m http.server`) it loads `tei.xml`
///   automatically on every reload.
/// - Double-clicked (`file://`) the browser blocks the automatic load, so it
///   falls back to a manual "choose tei.xml" file picker.
///
/// The stylesheet (`stylesheet`) is the customization point: it is embedded,
/// clearly marked, inside `index.html`, so anyone who knows XSLT can adapt
/// how the document is shown.
enum BundleViewer {

    /// The complete `index.html` document for a bundle.
    static let indexHTML: String = #"""
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>TEI preview</title>
    <style>
      body { font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
             margin: 0; color: #1a1a1a; background: #fafafa; }
      .notice { padding: 2rem; color: #555; line-height: 1.7; max-width: 44rem; }
      .notice.error { color: #b00; }
      .pick { display: inline-block; margin: .25rem 2rem; padding: .45rem 1rem;
              border: 1px solid #bbb; border-radius: 6px; background: #fff; cursor: pointer; }
    </style>
    </head>
    <body>
    <div id="app"><p class="notice">Loading…</p></div>

    <!-- ====================================================================
         Verification-view stylesheet. This XSLT 1.0 stylesheet IS the
         renderer: edit it to customize how tei.xml is shown, then reload.
         ===================================================================== -->
    <script type="application/xslt+xml" id="tei-stylesheet">
    \#(stylesheet)
    </script>

    <script>
    "use strict";
    (function () {
      var app = document.getElementById("app");

      function showError(msg) {
        app.innerHTML = "";
        var p = document.createElement("p");
        p.className = "notice error";
        p.textContent = msg;
        app.appendChild(p);
      }

      var proc = new XSLTProcessor();
      try {
        var xsltText = document.getElementById("tei-stylesheet").textContent.trim();
        var xsltDoc = new DOMParser().parseFromString(xsltText, "application/xml");
        proc.importStylesheet(xsltDoc);
      } catch (e) {
        showError("Could not load the stylesheet: " + e);
        return;
      }

      function render(xmlText) {
        var xml = new DOMParser().parseFromString(xmlText, "application/xml");
        if (xml.getElementsByTagName("parsererror").length) {
          showError("Could not parse tei.xml.");
          return;
        }
        var out = null;
        try { out = proc.transformToDocument(xml); } catch (e) { out = null; }
        if (!out) { showError("Could not render tei.xml."); return; }
        var html = "<!DOCTYPE html>\n" + new XMLSerializer().serializeToString(out);
        document.open();
        document.write(html);
        document.close();
      }

      function showPicker() {
        app.innerHTML = "";
        var p = document.createElement("p");
        p.className = "notice";
        p.textContent = "tei.xml を自動で読み込めませんでした（ブラウザの file:// 制約）。"
          + "フォルダを HTTP で配信するか（例: python3 -m http.server）、"
          + "下のボタンで tei.xml を選んでください。 / "
          + "Could not load tei.xml automatically. Serve this folder over HTTP "
          + "(e.g. python3 -m http.server), or choose tei.xml below.";
        var label = document.createElement("label");
        label.className = "pick";
        label.textContent = "tei.xml を選択 / Choose tei.xml";
        var input = document.createElement("input");
        input.type = "file";
        input.accept = ".xml,application/xml,text/xml";
        input.style.display = "none";
        input.addEventListener("change", function () {
          var f = input.files && input.files[0];
          if (f) { f.text().then(render).catch(function (e) { showError(String(e)); }); }
        });
        label.appendChild(input);
        app.appendChild(p);
        app.appendChild(label);
      }

      // Served over HTTP: load tei.xml directly. Opened as a file (file://):
      // fetch is blocked, so fall back to a manual file picker.
      fetch("tei.xml")
        .then(function (r) { if (!r.ok) { throw new Error("HTTP " + r.status); } return r.text(); })
        .then(render)
        .catch(showPicker);
    })();
    </script>
    </body>
    </html>
    """#

    /// XSLT 1.0 stylesheet, embedded into `index.html` and run client-side by
    /// the browser's `XSLTProcessor`. For each `<pb>` it lays out the page
    /// image beside its numbered OCR lines; lines are grouped to their page by
    /// their nearest preceding `<pb>` sibling (the structure `TEIBuilder`
    /// emits). `<graphic url>` is relative (`images/…`), so images resolve
    /// against the bundle folder. Header/label text follows `xml:lang`.
    static let stylesheet: String = #"""
    <?xml version="1.0" encoding="UTF-8"?>
    <xsl:stylesheet version="1.0"
        xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
        xmlns:tei="http://www.tei-c.org/ns/1.0"
        exclude-result-prefixes="tei">

      <xsl:output method="html" encoding="UTF-8" indent="yes"/>

      <!-- `xml:id` / `xml:lang` matched by local name so the stylesheet works
           whether or not the processor keeps the `xml` namespace prefix. -->
      <xsl:key name="surface-by-id" match="tei:surface"
          use="@*[local-name() = 'id']"/>

      <xsl:variable name="title" select="normalize-space(//tei:titleStmt/tei:title)"/>

      <!-- Localized labels: Japanese when xml:lang starts with `ja`. -->
      <xsl:variable name="lang" select="translate(
          //tei:TEI/@*[local-name() = 'lang'],
          'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz')"/>
      <xsl:variable name="ja" select="starts-with($lang, 'ja')"/>
      <xsl:variable name="L_page">
        <xsl:choose><xsl:when test="$ja">ページ</xsl:when><xsl:otherwise>Page</xsl:otherwise></xsl:choose>
      </xsl:variable>
      <xsl:variable name="L_resp">
        <xsl:choose><xsl:when test="$ja">担当</xsl:when><xsl:otherwise>Resp</xsl:otherwise></xsl:choose>
      </xsl:variable>
      <xsl:variable name="L_date">
        <xsl:choose><xsl:when test="$ja">日付</xsl:when><xsl:otherwise>Date</xsl:otherwise></xsl:choose>
      </xsl:variable>
      <xsl:variable name="L_pages">
        <xsl:choose><xsl:when test="$ja">ページ数</xsl:when><xsl:otherwise>Pages</xsl:otherwise></xsl:choose>
      </xsl:variable>
      <xsl:variable name="L_empty">
        <xsl:choose><xsl:when test="$ja">(空行)</xsl:when><xsl:otherwise>(empty)</xsl:otherwise></xsl:choose>
      </xsl:variable>

      <xsl:template match="/">
        <html lang="{$lang}">
          <head>
            <meta charset="UTF-8"/>
            <meta name="viewport" content="width=device-width, initial-scale=1"/>
            <title><xsl:value-of select="$title"/></title>
            <style>
              body { font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
                     margin: 0; color: #1a1a1a; background: #fafafa; }
              header { padding: 1.5rem 2rem; background: #fff; border-bottom: 1px solid #ddd; }
              header h1 { margin: 0 0 .35rem; font-size: 1.35rem; }
              .meta { margin: 0; color: #666; font-size: .85rem; }
              .meta span { margin-right: 1.25rem; }
              .page { padding: 1.5rem 2rem; border-bottom: 1px solid #ececec; }
              .page h2 { margin: 0 0 .75rem; font-size: .95rem; color: #555;
                         letter-spacing: .04em; }
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
                  <span><xsl:value-of select="$L_resp"/>: <xsl:value-of select="//tei:respStmt/tei:name"/></span>
                </xsl:if>
                <xsl:if test="//tei:publicationStmt/tei:date/@when">
                  <span><xsl:value-of select="$L_date"/>: <xsl:value-of select="//tei:publicationStmt/tei:date/@when"/></span>
                </xsl:if>
                <span><xsl:value-of select="$L_pages"/>: <xsl:value-of select="count(//tei:body//tei:pb)"/></span>
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
          <h2><xsl:value-of select="$L_page"/><xsl:text> </xsl:text><xsl:value-of select="@n"/></h2>
          <div class="page-grid">
            <div class="image-col">
              <xsl:if test="$surface/tei:graphic/@url">
                <img src="{$surface/tei:graphic/@url}" alt="{$L_page} {@n}"/>
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
                      <span class="linetext empty"><xsl:value-of select="$L_empty"/></span>
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
