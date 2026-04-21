// ============================================================
// 見積書 PDF 生成 & 共有
// jsPDF (UMD) を利用。日本語フォントは埋め込まず、
// 英数記号ベース + 日本語部分は Canvas でラスタライズして埋め込み。
// ============================================================

const CheckerPDF = (() => {

  // 日本語テキストを Canvas に描画 → PNG として返す
  function renderTextToPng(text, options = {}) {
    const {
      fontSize = 16,
      color = "#111",
      weight = "normal",
      maxWidth = 520,
      lineHeight = 1.5,
      align = "left"
    } = options;

    const tempCtx = document.createElement("canvas").getContext("2d");
    tempCtx.font = `${weight} ${fontSize}px "Hiragino Sans","Noto Sans JP","Yu Gothic",sans-serif`;
    // 折り返し処理
    const lines = [];
    const paragraphs = String(text).split("\n");
    for (const para of paragraphs) {
      let cur = "";
      for (const ch of para) {
        const w = tempCtx.measureText(cur + ch).width;
        if (w > maxWidth && cur) { lines.push(cur); cur = ch; }
        else cur += ch;
      }
      if (cur) lines.push(cur);
      else lines.push("");
    }
    const lh = Math.round(fontSize * lineHeight);
    const ratio = 2;
    const canvas = document.createElement("canvas");
    const longestWidth = Math.min(maxWidth, Math.max(
      1, ...lines.map(l => tempCtx.measureText(l).width)
    ));
    canvas.width  = Math.ceil(longestWidth * ratio) + 4;
    canvas.height = Math.ceil(lh * lines.length * ratio) + 4;
    const ctx = canvas.getContext("2d");
    ctx.scale(ratio, ratio);
    ctx.font = `${weight} ${fontSize}px "Hiragino Sans","Noto Sans JP","Yu Gothic",sans-serif`;
    ctx.fillStyle = color;
    ctx.textBaseline = "top";
    lines.forEach((line, i) => {
      let x = 0;
      if (align === "center") x = (canvas.width/ratio - ctx.measureText(line).width)/2;
      if (align === "right")  x = (canvas.width/ratio - ctx.measureText(line).width);
      ctx.fillText(line, x, i * lh + 2);
    });
    return { dataUrl: canvas.toDataURL("image/png"), widthPt: canvas.width/ratio, heightPt: canvas.height/ratio };
  }

  function yen(n) {
    return "¥" + Number(n).toLocaleString("ja-JP");
  }

  async function generatePdfBlob(result) {
    const { jsPDF } = window.jspdf;
    const doc = new jsPDF({ unit: "pt", format: "a4" });
    const pageW = doc.internal.pageSize.getWidth();
    const pageH = doc.internal.pageSize.getHeight();
    const margin = 40;
    let y = margin;

    // ---- ヘッダーバー
    doc.setFillColor(10, 17, 40);
    doc.rect(0, 0, pageW, 70, "F");
    doc.setFillColor(76, 201, 240);
    doc.rect(0, 66, pageW, 4, "F");

    // ブランドロゴ（文字は英数字で直接描画可能）
    doc.setTextColor(255, 255, 255);
    doc.setFont("helvetica", "bold");
    doc.setFontSize(22);
    doc.text("Checker-S", margin, 40);
    doc.setFontSize(10);
    doc.setFont("helvetica", "normal");
    doc.text("AI Used Car Valuation Report", margin, 56);

    // 日付（右上）
    const dateStr = new Date().toLocaleDateString("ja-JP", {
      year: "numeric", month: "2-digit", day: "2-digit"
    });
    const ref = "Ref: " + Date.now().toString(36).toUpperCase();
    doc.setFontSize(10);
    doc.text(dateStr, pageW - margin, 40, { align: "right" });
    doc.text(ref, pageW - margin, 56, { align: "right" });

    y = 100;

    // ---- タイトル
    drawJP(doc, "中古車査定 見積書", margin, y, {
      fontSize: 22, weight: "bold", color: "#0a1128"
    });
    y += 34;

    // ---- 宛名
    drawJP(doc, "お客様名: " + (result.customer || "お客様"), margin, y, { fontSize: 12, color: "#333" });
    y += 20;
    drawJP(doc, "以下の内容にて査定金額をご提示いたします。", margin, y, { fontSize: 11, color: "#555" });
    y += 26;

    // ---- 査定金額ボックス
    doc.setFillColor(246, 248, 255);
    doc.roundedRect(margin, y, pageW - margin * 2, 86, 8, 8, "F");
    doc.setDrawColor(76, 201, 240);
    doc.setLineWidth(1.2);
    doc.roundedRect(margin, y, pageW - margin * 2, 86, 8, 8, "S");
    drawJP(doc, "AI査定金額", margin + 16, y + 14, { fontSize: 11, color: "#4a556b" });
    // 金額は英数字なので直接描画
    doc.setTextColor(10, 17, 40);
    doc.setFont("helvetica", "bold");
    doc.setFontSize(32);
    doc.text(yen(result.final), margin + 16, y + 58);
    doc.setFontSize(10);
    doc.setFont("helvetica", "normal");
    doc.setTextColor(90, 90, 90);
    doc.text(
      "Range: " + yen(result.low) + "  -  " + yen(result.high),
      margin + 16, y + 76
    );
    y += 100;

    // ---- 車両情報テーブル
    drawJP(doc, "車両情報", margin, y, { fontSize: 14, weight: "bold", color: "#0a1128" });
    y += 18;
    const v = result.vehicle;
    const rows = [
      ["メーカー", v.make],
      ["車種", v.model],
      ["年式", String(v.year) + " 年"],
      ["走行距離", Number(v.mileage).toLocaleString("ja-JP") + " km"],
      ["ボディカラー", v.color],
      ["ミッション", v.transmission],
      ["車両ナンバー", v.plate || "-"]
    ];
    doc.setDrawColor(220, 225, 235);
    doc.setLineWidth(0.6);
    const tableW = pageW - margin * 2;
    const col1W = 150;
    rows.forEach((row, i) => {
      const rowY = y + i * 22;
      if (i % 2 === 0) { doc.setFillColor(248, 250, 255); doc.rect(margin, rowY, tableW, 22, "F"); }
      drawJP(doc, row[0], margin + 10, rowY + 4, { fontSize: 11, color: "#5a6277" });
      drawJP(doc, row[1], margin + col1W, rowY + 4, { fontSize: 11, color: "#111" });
      doc.line(margin, rowY + 22, margin + tableW, rowY + 22);
    });
    y += rows.length * 22 + 14;

    // ---- AI検出ダメージ
    drawJP(doc, "AI検出ダメージ", margin, y, { fontSize: 14, weight: "bold", color: "#0a1128" });
    y += 18;
    if (!result.damages.length) {
      drawJP(doc, "目立ったダメージは検出されませんでした。", margin + 10, y + 4, { fontSize: 11, color: "#3a7d44" });
      y += 24;
    } else {
      result.damages.forEach((d, i) => {
        if (y > pageH - 160) { doc.addPage(); y = margin; }
        const rowY = y + i * 22;
        if (i % 2 === 0) { doc.setFillColor(255, 248, 250); doc.rect(margin, rowY, tableW, 22, "F"); }
        drawJP(doc, d.location + " / " + d.label, margin + 10, rowY + 4, { fontSize: 11, color: "#111" });
        drawJP(doc, "信頼度 " + Math.round(d.confidence * 100) + "%",
               margin + 260, rowY + 4, { fontSize: 10, color: "#5a6277" });
        doc.setTextColor(200, 30, 80);
        doc.setFont("helvetica", "bold");
        doc.setFontSize(11);
        doc.text("- " + yen(Math.round(d.deduct * 10000)),
                 margin + tableW - 10, rowY + 16, { align: "right" });
        doc.setFont("helvetica", "normal");
      });
      y += result.damages.length * 22 + 14;
    }

    // ---- 内訳
    if (y > pageH - 180) { doc.addPage(); y = margin; }
    drawJP(doc, "査定内訳", margin, y, { fontSize: 14, weight: "bold", color: "#0a1128" });
    y += 18;
    result.breakdown.forEach((b, i) => {
      if (y > pageH - 80) { doc.addPage(); y = margin; }
      const rowY = y + i * 22;
      if (b.bold) { doc.setFillColor(232, 244, 255); doc.rect(margin, rowY, tableW, 22, "F"); }
      else if (i % 2 === 0) { doc.setFillColor(250, 251, 255); doc.rect(margin, rowY, tableW, 22, "F"); }
      drawJP(doc, b.label, margin + 10, rowY + 4, { fontSize: 11, color: b.bold ? "#0a1128" : "#333", weight: b.bold ? "bold" : "normal" });
      doc.setTextColor(b.bold ? 10 : (b.value < 0 ? 200 : 40),
                       b.bold ? 17 : (b.value < 0 ? 30  : 40),
                       b.bold ? 40 : (b.value < 0 ? 80  : 40));
      doc.setFont("helvetica", b.bold ? "bold" : "normal");
      doc.setFontSize(b.bold ? 13 : 11);
      doc.text((b.value >= 0 ? "" : "-") + yen(Math.abs(b.value)),
               margin + tableW - 10, rowY + 16, { align: "right" });
      doc.setFont("helvetica", "normal");
    });
    y += result.breakdown.length * 22 + 18;

    // ---- 撮影写真（縮小）
    const caps = (result.captures || []).slice(0, 8);
    if (caps.length) {
      if (y > pageH - 220) { doc.addPage(); y = margin; }
      drawJP(doc, "撮影画像", margin, y, { fontSize: 14, weight: "bold", color: "#0a1128" });
      y += 14;
      const cols = 4;
      const gap = 8;
      const cellW = (tableW - gap * (cols - 1)) / cols;
      const cellH = cellW * 0.75;
      caps.forEach((c, i) => {
        const col = i % cols;
        const row = Math.floor(i / cols);
        const cx = margin + col * (cellW + gap);
        const cy = y + row * (cellH + 20);
        try { doc.addImage(c.dataUrl, "JPEG", cx, cy, cellW, cellH, undefined, "FAST"); } catch(e) {}
        drawJP(doc, c.label, cx, cy + cellH + 1, { fontSize: 9, color: "#555" });
      });
      const rows2 = Math.ceil(caps.length / cols);
      y += rows2 * (cellH + 20) + 8;
    }

    // ---- フッター
    const footerY = pageH - 40;
    doc.setDrawColor(220, 225, 235);
    doc.line(margin, footerY - 10, pageW - margin, footerY - 10);
    drawJP(doc, "本見積書はAIによる参考価格であり、実際の買取査定額は車両状態確認後に変動する場合があります。",
           margin, footerY - 4, { fontSize: 8, color: "#888", maxWidth: pageW - margin * 2 });
    doc.setTextColor(136,136,136);
    doc.setFontSize(8);
    doc.setFont("helvetica", "normal");
    doc.text("Generated by Checker-S  /  " + dateStr,
             pageW - margin, footerY + 8, { align: "right" });

    return doc.output("blob");
  }

  // 日本語対応テキスト描画（Canvas→PNGを貼り付け）
  function drawJP(doc, text, x, y, opt = {}) {
    const png = renderTextToPng(text, opt);
    try {
      doc.addImage(png.dataUrl, "PNG", x, y, png.widthPt, png.heightPt);
    } catch(e) {}
  }

  function buildFileName(vehicle) {
    const name = [vehicle.make, vehicle.model, vehicle.year].filter(Boolean).join("_");
    const d = new Date();
    const pad = n => String(n).padStart(2, "0");
    return `Checker-S_Quote_${name}_${d.getFullYear()}${pad(d.getMonth()+1)}${pad(d.getDate())}.pdf`;
  }

  async function download(result) {
    const blob = await generatePdfBlob(result);
    const url  = URL.createObjectURL(blob);
    const a    = document.createElement("a");
    a.href = url;
    a.download = buildFileName(result.vehicle);
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 4000);
  }

  async function share(result) {
    const blob = await generatePdfBlob(result);
    const fname = buildFileName(result.vehicle);
    const file  = new File([blob], fname, { type: "application/pdf" });

    if (navigator.canShare && navigator.canShare({ files: [file] })) {
      try {
        await navigator.share({
          title: "中古車査定 見積書",
          text: `【Checker-S 査定】${result.vehicle.make} ${result.vehicle.model}（${result.vehicle.year}年式）\n査定金額: ¥${result.final.toLocaleString()}`,
          files: [file]
        });
        return { shared: true };
      } catch (e) {
        if (e && e.name === "AbortError") return { shared: false, aborted: true };
        // fallback へ
      }
    }
    // Web Share API 未対応の場合はダウンロードに fallback
    await download(result);
    return { shared: false, fallback: "download" };
  }

  return { download, share, generatePdfBlob };
})();

window.CheckerPDF = CheckerPDF;
