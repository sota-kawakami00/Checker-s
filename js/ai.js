// ============================================================
// AI解析モック + 査定額計算エンジン
// ============================================================
// 実際のAIモデル連携（TensorFlow.js / APIなど）の代わりに、
// 撮影画像の画素統計（明るさ・分散・エッジ量）から
// 擬似的にダメージスコアを算出し、現実的な結果を返します。
// ============================================================

const CheckerAI = (() => {

  // ダメージカタログ: AIが検出しうる項目
  const DAMAGE_CATALOG = [
    { id: "scratch_small",  label: "小傷",           severity: "low",  deduct: 1.2 },
    { id: "scratch_large",  label: "深い擦り傷",     severity: "mid",  deduct: 4.0 },
    { id: "dent_small",     label: "軽微な凹み",     severity: "mid",  deduct: 3.5 },
    { id: "dent_large",     label: "大きな凹み",     severity: "high", deduct: 7.5 },
    { id: "repair",         label: "修復歴の痕跡",   severity: "high", deduct: 15.0 },
    { id: "paint_fade",     label: "塗装の色褪せ",   severity: "low",  deduct: 2.0 },
    { id: "rust",           label: "錆",             severity: "mid",  deduct: 4.5 },
    { id: "glass_chip",     label: "ガラスの欠け",   severity: "mid",  deduct: 3.0 },
    { id: "interior_stain", label: "内装の汚れ",     severity: "low",  deduct: 1.8 },
    { id: "interior_tear",  label: "シートの破れ",   severity: "mid",  deduct: 4.2 }
  ];

  // 画像（dataURL）を読み込み、キャンバス統計を取る
  async function analyzeImage(dataUrl) {
    return new Promise((resolve) => {
      const img = new Image();
      img.onload = () => {
        const w = 64, h = 64;
        const c = document.createElement("canvas");
        c.width = w; c.height = h;
        const ctx = c.getContext("2d");
        ctx.drawImage(img, 0, 0, w, h);
        const data = ctx.getImageData(0, 0, w, h).data;
        // 明度平均・分散・隣接差分（エッジ）
        let sum = 0, sum2 = 0, edge = 0;
        const lum = new Float32Array(w * h);
        for (let i = 0, p = 0; i < data.length; i += 4, p++) {
          const l = 0.299 * data[i] + 0.587 * data[i+1] + 0.114 * data[i+2];
          lum[p] = l; sum += l; sum2 += l * l;
        }
        const n = w * h;
        const mean = sum / n;
        const variance = Math.max(0, sum2 / n - mean * mean);
        for (let y = 0; y < h; y++) {
          for (let x = 0; x < w - 1; x++) {
            edge += Math.abs(lum[y*w + x + 1] - lum[y*w + x]);
          }
        }
        edge /= (h * (w - 1));
        resolve({ mean, variance, edge });
      };
      img.onerror = () => resolve({ mean: 128, variance: 800, edge: 10 });
      img.src = dataUrl;
    });
  }

  // 画像統計を元に、擬似的なダメージを生成する
  function detectDamagesFromStats(stats, shotKey, seed) {
    const damages = [];
    const rand = mulberry32(seed);
    // エッジ量が高いほど「キズ」が検出されやすい
    const edgeNorm  = Math.min(1, stats.edge / 30);
    const varNorm   = Math.min(1, stats.variance / 3000);
    const darkFactor= Math.max(0, 1 - stats.mean / 180); // 暗い=見づらい=ノイズも

    const candidates = [];
    if (shotKey === "front" || shotKey === "rear" || shotKey === "bonnet") {
      candidates.push("scratch_small", "dent_small", "paint_fade");
      if (edgeNorm > 0.45 && rand() < 0.55) candidates.push("scratch_large");
      if (varNorm > 0.55 && rand() < 0.35)  candidates.push("dent_large");
    }
    if (shotKey === "side_left" || shotKey === "side_right") {
      candidates.push("scratch_small", "scratch_large");
      if (rand() < 0.25) candidates.push("dent_small");
      if (rand() < 0.12 + darkFactor * 0.2) candidates.push("rust");
    }
    if (shotKey === "roof") {
      candidates.push("paint_fade");
      if (rand() < 0.18) candidates.push("scratch_small");
    }
    if (shotKey === "interior") {
      candidates.push("interior_stain");
      if (rand() < 0.35) candidates.push("interior_tear");
    }
    if (shotKey === "odometer") {
      // メーターは通常減点対象なし
    }

    // 修復歴：全体統計が極端なときに低確率で検出
    if (varNorm > 0.8 && rand() < 0.18) candidates.push("repair");

    // 候補の中からランダムに 0〜2 件採用
    const picked = [];
    const pickCount = Math.floor(rand() * 2.6);
    for (let i = 0; i < pickCount && candidates.length; i++) {
      const idx = Math.floor(rand() * candidates.length);
      const id = candidates.splice(idx, 1)[0];
      if (picked.includes(id)) continue;
      picked.push(id);
    }

    picked.forEach(id => {
      const src = DAMAGE_CATALOG.find(d => d.id === id);
      if (!src) return;
      const severityMul = 0.7 + rand() * 0.6; // 0.7〜1.3
      damages.push({
        ...src,
        location: shotKeyToLocation(shotKey),
        confidence: Math.round((0.68 + rand() * 0.3) * 100) / 100,
        deduct: Math.round(src.deduct * severityMul * 10) / 10
      });
    });
    return damages;
  }

  function shotKeyToLocation(key) {
    return {
      front: "フロント",
      rear: "リア",
      side_left: "左サイド",
      side_right: "右サイド",
      bonnet: "ボンネット",
      roof: "ルーフ",
      interior: "内装",
      odometer: "メーター"
    }[key] || key;
  }

  // 決定的乱数（シード固定）
  function mulberry32(seed) {
    let t = seed >>> 0;
    return function() {
      t += 0x6D2B79F5;
      let r = Math.imul(t ^ (t >>> 15), 1 | t);
      r ^= r + Math.imul(r ^ (r >>> 7), 61 | r);
      return ((r ^ (r >>> 14)) >>> 0) / 4294967296;
    };
  }

  // 査定額を計算する
  function calculateValuation({ vehicle, damages }) {
    const { CAR_DATA } = window.CheckerData;
    const makeData  = CAR_DATA[vehicle.make];
    const modelData = makeData ? makeData[vehicle.model] : null;
    const baseWan   = modelData ? modelData.base : 220; // 万円（新車時の目安）

    // 年式ディスカウント：初年度-8%、以降年率-7%（下限15%）
    const age = Math.max(0, (new Date().getFullYear()) - Number(vehicle.year));
    let yearFactor = 1;
    if (age >= 1) {
      yearFactor = 0.92;
      for (let i = 1; i < age; i++) yearFactor *= 0.93;
    }
    yearFactor = Math.max(0.15, yearFactor);

    // 走行距離ディスカウント：標準年1万km基準
    const mileage = Number(vehicle.mileage) || 0;
    const expected = age * 10000;
    const diff = mileage - expected; // 走りすぎならマイナス
    // 10,000km ごとに -3%
    const mileageFactor = Math.max(0.3, 1 - Math.max(0, diff) / 10000 * 0.03 + Math.max(-0.1, -Math.max(0, -diff) / 10000 * 0.01));

    // ミッション補正
    const transFactor = vehicle.transmission === "MT" ? 0.97 : 1.00;
    // カラー補正（人気色は +2%）
    const popularColors = ["ホワイト", "ブラック"];
    const colorFactor = popularColors.includes(vehicle.color) ? 1.02 : 1.0;

    // 市場係数：人気車種は +5%〜+8%
    const popularModels = ["プリウス", "アクア", "N-BOX", "ハスラー", "ジムニー", "アルファード", "ハリアー", "ランドクルーザー"];
    const marketFactor = popularModels.includes(vehicle.model) ? 1.06 : 1.0;

    const base = baseWan * 10000; // 円
    const preDeduct = Math.round(base * yearFactor * mileageFactor * transFactor * colorFactor * marketFactor);

    // ダメージ控除（万円単位）
    const damageDeductWan = damages.reduce((s, d) => s + d.deduct, 0);
    const damageDeductYen = Math.round(damageDeductWan * 10000);
    let final = preDeduct - damageDeductYen;
    if (final < 30000) final = 30000; // 最低値

    // レンジ（±7%）
    const low  = Math.round(final * 0.93 / 1000) * 1000;
    const high = Math.round(final * 1.07 / 1000) * 1000;

    const breakdown = [
      { label: "基準価格（新車相当）", value: base },
      { label: `年式係数（${age}年落ち）`, value: Math.round(base * (yearFactor - 1)) },
      { label: "走行距離補正", value: Math.round(base * yearFactor * (mileageFactor - 1)) },
      { label: "ミッション補正",
        value: Math.round(base * yearFactor * mileageFactor * (transFactor - 1)) },
      { label: "カラー補正",
        value: Math.round(base * yearFactor * mileageFactor * transFactor * (colorFactor - 1)) },
      { label: "市場係数",
        value: Math.round(base * yearFactor * mileageFactor * transFactor * colorFactor * (marketFactor - 1)) },
      { label: "AI検出ダメージ控除", value: -damageDeductYen },
      { label: "査定金額", value: final, bold: true }
    ];

    return {
      base, yearFactor, mileageFactor, transFactor, colorFactor, marketFactor,
      preDeduct,
      damageDeductYen,
      final, low, high,
      breakdown
    };
  }

  // 撮影画像一式からダメージを検出
  async function detectAll(captures) {
    const all = [];
    let i = 0;
    for (const cap of captures) {
      const stats = await analyzeImage(cap.dataUrl);
      const seed  = hashStr(cap.key + ":" + (cap.dataUrl || "").slice(-120)) + i++;
      const dmg   = detectDamagesFromStats(stats, cap.key, seed);
      all.push(...dmg);
    }
    return all;
  }

  function hashStr(s) {
    let h = 2166136261;
    for (let i = 0; i < s.length; i++) {
      h ^= s.charCodeAt(i);
      h = Math.imul(h, 16777619);
    }
    return h >>> 0;
  }

  return {
    DAMAGE_CATALOG,
    detectAll,
    calculateValuation
  };
})();

window.CheckerAI = CheckerAI;
