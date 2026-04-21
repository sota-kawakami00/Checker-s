// ============================================================
// 車両データ・撮影手順・基準価格
// ============================================================

// メーカー別モデル + 基準価格（新車時・万円）
const CAR_DATA = {
  "トヨタ": {
    "プリウス":     { base: 320 },
    "アクア":       { base: 210 },
    "カローラ":     { base: 220 },
    "カムリ":       { base: 350 },
    "ヤリス":       { base: 180 },
    "ハリアー":     { base: 420 },
    "RAV4":         { base: 380 },
    "アルファード": { base: 560 },
    "ヴェルファイア":{ base: 580 },
    "ランドクルーザー":{ base: 780 },
    "ハイエース":   { base: 330 },
    "クラウン":     { base: 520 }
  },
  "ホンダ": {
    "フィット":     { base: 200 },
    "ヴェゼル":     { base: 290 },
    "フリード":     { base: 260 },
    "ステップワゴン":{ base: 320 },
    "シビック":     { base: 350 },
    "オデッセイ":   { base: 420 },
    "N-BOX":        { base: 170 },
    "N-WGN":        { base: 150 },
    "CR-V":         { base: 380 }
  },
  "日産": {
    "ノート":       { base: 220 },
    "セレナ":       { base: 310 },
    "エクストレイル":{ base: 360 },
    "スカイライン": { base: 500 },
    "フェアレディZ":{ base: 650 },
    "リーフ":       { base: 400 },
    "デイズ":       { base: 150 },
    "ルークス":     { base: 180 }
  },
  "マツダ": {
    "デミオ/MAZDA2":{ base: 200 },
    "MAZDA3":       { base: 280 },
    "CX-3":         { base: 260 },
    "CX-5":         { base: 320 },
    "CX-8":         { base: 400 },
    "ロードスター": { base: 330 }
  },
  "スバル": {
    "インプレッサ": { base: 250 },
    "フォレスター": { base: 320 },
    "レガシィ":     { base: 370 },
    "BRZ":          { base: 320 },
    "WRX":          { base: 450 }
  },
  "スズキ": {
    "ワゴンR":      { base: 140 },
    "ハスラー":     { base: 160 },
    "ジムニー":     { base: 220 },
    "スイフト":     { base: 190 },
    "アルト":       { base: 110 },
    "スペーシア":   { base: 170 }
  },
  "ダイハツ": {
    "タント":       { base: 160 },
    "ムーヴ":       { base: 140 },
    "タフト":       { base: 170 },
    "ロッキー":     { base: 200 },
    "ミラ":         { base: 110 }
  },
  "三菱": {
    "デリカD:5":    { base: 400 },
    "eKワゴン":     { base: 140 },
    "アウトランダー":{ base: 450 },
    "RVR":          { base: 260 }
  },
  "レクサス": {
    "IS":           { base: 620 },
    "RX":           { base: 680 },
    "NX":           { base: 550 },
    "LS":           { base: 1050 },
    "LX":           { base: 1250 },
    "UX":           { base: 440 }
  }
};

// 撮影手順（8箇所）
// フレームSVG は SVG viewBox="0 0 300 400" 基準でレンダリング
const CAPTURE_SHOTS = [
  {
    key: "front",
    label: "フロント",
    tip: "車両の正面からフロントグリップが中央に来るように",
    frame: `
      <rect x="40" y="90" width="220" height="220" rx="24" fill="none" stroke="#4cc9f0" stroke-width="3" stroke-dasharray="10 8"/>
      <path d="M70 200 h160" stroke="#4cc9f0" stroke-width="2" stroke-dasharray="4 4" opacity=".6"/>
      <path d="M150 110 v180" stroke="#4cc9f0" stroke-width="2" stroke-dasharray="4 4" opacity=".6"/>
      <text x="150" y="80" text-anchor="middle" fill="#4cc9f0" font-size="14" font-weight="700">フロント全景</text>
    `
  },
  {
    key: "rear",
    label: "リア",
    tip: "車両の真後ろから、テールランプを両側に収めて",
    frame: `
      <rect x="40" y="90" width="220" height="220" rx="24" fill="none" stroke="#4cc9f0" stroke-width="3" stroke-dasharray="10 8"/>
      <circle cx="80" cy="200" r="18" fill="none" stroke="#4cc9f0" stroke-width="2" opacity=".6"/>
      <circle cx="220" cy="200" r="18" fill="none" stroke="#4cc9f0" stroke-width="2" opacity=".6"/>
      <text x="150" y="80" text-anchor="middle" fill="#4cc9f0" font-size="14" font-weight="700">リア全景</text>
    `
  },
  {
    key: "side_left",
    label: "左サイド",
    tip: "車両の側面全体が画面に収まる位置から",
    frame: `
      <rect x="20" y="130" width="260" height="140" rx="18" fill="none" stroke="#4cc9f0" stroke-width="3" stroke-dasharray="10 8"/>
      <circle cx="70" cy="260" r="22" fill="none" stroke="#4cc9f0" stroke-width="2" opacity=".5"/>
      <circle cx="230" cy="260" r="22" fill="none" stroke="#4cc9f0" stroke-width="2" opacity=".5"/>
      <text x="150" y="120" text-anchor="middle" fill="#4cc9f0" font-size="14" font-weight="700">左サイド全景</text>
    `
  },
  {
    key: "side_right",
    label: "右サイド",
    tip: "車両の右側面全体が画面に収まる位置から",
    frame: `
      <rect x="20" y="130" width="260" height="140" rx="18" fill="none" stroke="#4cc9f0" stroke-width="3" stroke-dasharray="10 8"/>
      <circle cx="70" cy="260" r="22" fill="none" stroke="#4cc9f0" stroke-width="2" opacity=".5"/>
      <circle cx="230" cy="260" r="22" fill="none" stroke="#4cc9f0" stroke-width="2" opacity=".5"/>
      <text x="150" y="120" text-anchor="middle" fill="#4cc9f0" font-size="14" font-weight="700">右サイド全景</text>
    `
  },
  {
    key: "bonnet",
    label: "ボンネット",
    tip: "ボンネット前方から全体が見えるように",
    frame: `
      <path d="M50 120 L250 120 L270 280 L30 280 Z" fill="none" stroke="#4cc9f0" stroke-width="3" stroke-dasharray="10 8"/>
      <text x="150" y="100" text-anchor="middle" fill="#4cc9f0" font-size="14" font-weight="700">ボンネット</text>
    `
  },
  {
    key: "roof",
    label: "ルーフ",
    tip: "屋根の全体を斜め上から",
    frame: `
      <path d="M80 140 L220 140 L250 260 L50 260 Z" fill="none" stroke="#4cc9f0" stroke-width="3" stroke-dasharray="10 8"/>
      <text x="150" y="120" text-anchor="middle" fill="#4cc9f0" font-size="14" font-weight="700">ルーフ</text>
    `
  },
  {
    key: "interior",
    label: "内装（運転席）",
    tip: "運転席のハンドル・メーターが写るように",
    frame: `
      <rect x="30" y="100" width="240" height="200" rx="20" fill="none" stroke="#4cc9f0" stroke-width="3" stroke-dasharray="10 8"/>
      <circle cx="150" cy="200" r="50" fill="none" stroke="#4cc9f0" stroke-width="2" opacity=".6"/>
      <text x="150" y="90" text-anchor="middle" fill="#4cc9f0" font-size="14" font-weight="700">運転席周り</text>
    `
  },
  {
    key: "odometer",
    label: "走行距離メーター",
    tip: "メーターの数字がはっきり写るように近づいて",
    frame: `
      <rect x="60" y="150" width="180" height="100" rx="14" fill="none" stroke="#4cc9f0" stroke-width="3" stroke-dasharray="10 8"/>
      <text x="150" y="130" text-anchor="middle" fill="#4cc9f0" font-size="14" font-weight="700">走行距離メーター</text>
    `
  }
];

// 年式リスト
const CURRENT_YEAR = new Date().getFullYear();
const YEAR_LIST = [];
for (let y = CURRENT_YEAR; y >= CURRENT_YEAR - 30; y--) YEAR_LIST.push(y);

window.CheckerData = { CAR_DATA, CAPTURE_SHOTS, YEAR_LIST };
