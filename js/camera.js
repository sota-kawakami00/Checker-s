// ============================================================
// カメラ制御（getUserMedia + 撮影 + フレーム表示）
// ============================================================

const CheckerCamera = (() => {
  let stream = null;
  let currentFacing = "environment"; // "environment" or "user"
  const video = () => document.getElementById("camera-video");
  const canvas = () => document.getElementById("capture-canvas");

  async function start() {
    stop();
    const constraints = {
      audio: false,
      video: {
        facingMode: { ideal: currentFacing },
        width:  { ideal: 1920 },
        height: { ideal: 1080 }
      }
    };
    try {
      stream = await navigator.mediaDevices.getUserMedia(constraints);
      video().srcObject = stream;
      await video().play().catch(() => {});
      return true;
    } catch (err) {
      console.warn("カメラ取得失敗:", err);
      throw err;
    }
  }

  function stop() {
    if (stream) {
      stream.getTracks().forEach(t => t.stop());
      stream = null;
    }
    const v = video();
    if (v) v.srcObject = null;
  }

  async function switchFacing() {
    currentFacing = currentFacing === "environment" ? "user" : "environment";
    try { await start(); } catch(e) { /* ignore */ }
  }

  // 現在のビデオフレームをキャプチャしてdataURLを返す
  function capture() {
    const v = video();
    if (!v || !v.videoWidth) return null;
    const c = canvas();
    const maxW = 1280;
    const scale = Math.min(1, maxW / v.videoWidth);
    c.width = Math.round(v.videoWidth * scale);
    c.height = Math.round(v.videoHeight * scale);
    const ctx = c.getContext("2d");
    ctx.drawImage(v, 0, 0, c.width, c.height);
    return c.toDataURL("image/jpeg", 0.82);
  }

  // デモ用画像（カメラが使えないときのダミー）
  function generateDemoImage(shotLabel, colorHint) {
    const c = canvas();
    c.width = 800; c.height = 600;
    const ctx = c.getContext("2d");
    // 背景グラデーション
    const grad = ctx.createLinearGradient(0, 0, 0, 600);
    grad.addColorStop(0, "#111a2e");
    grad.addColorStop(1, "#2a1a4a");
    ctx.fillStyle = grad; ctx.fillRect(0, 0, 800, 600);
    // 車のシルエット
    ctx.fillStyle = colorHint || "#4cc9f0";
    ctx.beginPath();
    ctx.moveTo(120, 420);
    ctx.quadraticCurveTo(160, 300, 280, 290);
    ctx.lineTo(520, 290);
    ctx.quadraticCurveTo(640, 300, 680, 420);
    ctx.lineTo(680, 480);
    ctx.lineTo(120, 480);
    ctx.closePath();
    ctx.fill();
    // タイヤ
    ctx.fillStyle = "#000";
    ctx.beginPath(); ctx.arc(220, 490, 40, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(580, 490, 40, 0, Math.PI * 2); ctx.fill();
    // ラベル
    ctx.fillStyle = "#fff";
    ctx.font = "bold 28px sans-serif";
    ctx.textAlign = "center";
    ctx.fillText(shotLabel || "デモ画像", 400, 100);
    ctx.font = "14px sans-serif";
    ctx.fillStyle = "#9aa3b7";
    ctx.fillText("（カメラ未使用・デモモード）", 400, 130);
    return c.toDataURL("image/jpeg", 0.82);
  }

  return { start, stop, switchFacing, capture, generateDemoImage };
})();

window.CheckerCamera = CheckerCamera;
