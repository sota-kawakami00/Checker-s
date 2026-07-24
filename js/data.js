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
// frame SVG は viewBox="0 0 300 400" 基準
// icon SVG は viewBox="0 0 40 40" 基準（撮影イントロ一覧用）
const CAPTURE_SHOTS = [
  {
    key: "front",
    label: "フロント",
    tip: "車両の正面から、左右のヘッドライトが同じ大きさに見える位置で",
    icon: `
      <!-- front view car face -->
      <path d="M8 14 Q8 10 12 10 L28 10 Q32 10 32 14 L32 28 Q32 32 28 32 L12 32 Q8 32 8 28 Z" fill="none"/>
      <ellipse cx="13" cy="20" rx="3" ry="2" fill="#4cc9f0" opacity=".8"/>
      <ellipse cx="27" cy="20" rx="3" ry="2" fill="#4cc9f0" opacity=".8"/>
      <rect x="16" y="24" width="8" height="4" rx="1"/>
    `,
    frame: `
      <!-- scan brackets (4 corners) -->
      <g stroke="#4cc9f0" stroke-width="2.5" fill="none" opacity=".8">
        <path d="M22 42 L22 22 L42 22"/>
        <path d="M258 22 L278 22 L278 42"/>
        <path d="M278 358 L278 378 L258 378"/>
        <path d="M42 378 L22 378 L22 358"/>
      </g>
      <!-- car body from front -->
      <path d="M60 140 Q60 115 85 115 L215 115 Q240 115 240 140 L240 295 Q240 315 220 315 L80 315 Q60 315 60 295 Z"
            fill="rgba(76,201,240,0.06)" stroke="#4cc9f0" stroke-width="3" stroke-dasharray="10 8"/>
      <!-- windshield -->
      <path d="M80 150 L220 150 L210 195 L90 195 Z"
            fill="none" stroke="#4cc9f0" stroke-width="2" opacity=".55"/>
      <!-- headlights -->
      <path d="M70 222 Q95 212 123 222 Q121 234 95 234 Q72 234 70 222 Z"
            fill="none" stroke="#4cc9f0" stroke-width="2" opacity=".85"/>
      <path d="M177 222 Q205 212 230 222 Q228 234 205 234 Q179 234 177 222 Z"
            fill="none" stroke="#4cc9f0" stroke-width="2" opacity=".85"/>
      <!-- grille -->
      <rect x="110" y="247" width="80" height="32" rx="4"
            fill="none" stroke="#4cc9f0" stroke-width="2" opacity=".7"/>
      <line x1="115" y1="258" x2="185" y2="258" stroke="#4cc9f0" stroke-width="1" opacity=".5"/>
      <line x1="115" y1="268" x2="185" y2="268" stroke="#4cc9f0" stroke-width="1" opacity=".5"/>
      <!-- mirrors -->
      <ellipse cx="55" cy="172" rx="10" ry="12" fill="none" stroke="#4cc9f0" stroke-width="2" opacity=".6"/>
      <ellipse cx="245" cy="172" rx="10" ry="12" fill="none" stroke="#4cc9f0" stroke-width="2" opacity=".6"/>
      <!-- license plate -->
      <rect x="120" y="288" width="60" height="18" rx="2"
            fill="none" stroke="#4cc9f0" stroke-width="2" opacity=".7"/>
      <text x="150" y="98" text-anchor="middle" fill="#4cc9f0" font-size="14" font-weight="700">フロント</text>
    `
  },
  {
    key: "rear",
    label: "リア",
    tip: "車両の真後ろから、左右のテールランプを均等に",
    icon: `
      <path d="M8 14 Q8 10 12 10 L28 10 Q32 10 32 14 L32 28 Q32 32 28 32 L12 32 Q8 32 8 28 Z" fill="none"/>
      <rect x="10" y="20" width="7" height="3" rx="1" fill="#4cc9f0" opacity=".85"/>
      <rect x="23" y="20" width="7" height="3" rx="1" fill="#4cc9f0" opacity=".85"/>
      <rect x="15" y="26" width="10" height="3" rx="1"/>
    `,
    frame: `
      <g stroke="#4cc9f0" stroke-width="2.5" fill="none" opacity=".8">
        <path d="M22 42 L22 22 L42 22"/>
        <path d="M258 22 L278 22 L278 42"/>
        <path d="M278 358 L278 378 L258 378"/>
        <path d="M42 378 L22 378 L22 358"/>
      </g>
      <path d="M60 140 Q60 115 85 115 L215 115 Q240 115 240 140 L240 295 Q240 315 220 315 L80 315 Q60 315 60 295 Z"
            fill="rgba(76,201,240,0.06)" stroke="#4cc9f0" stroke-width="3" stroke-dasharray="10 8"/>
      <!-- rear window -->
      <path d="M80 150 L220 150 L210 200 L90 200 Z"
            fill="none" stroke="#4cc9f0" stroke-width="2" opacity=".55"/>
      <!-- trunk line -->
      <line x1="80" y1="222" x2="220" y2="222" stroke="#4cc9f0" stroke-width="2" opacity=".5"/>
      <!-- taillights -->
      <rect x="70" y="230" width="62" height="22" rx="4"
            fill="none" stroke="#4cc9f0" stroke-width="2" opacity=".85"/>
      <rect x="168" y="230" width="62" height="22" rx="4"
            fill="none" stroke="#4cc9f0" stroke-width="2" opacity=".85"/>
      <!-- brake lamp bar -->
      <rect x="130" y="162" width="40" height="6" rx="2" fill="none" stroke="#4cc9f0" stroke-width="1.5" opacity=".6"/>
      <!-- license plate -->
      <rect x="115" y="270" width="70" height="22" rx="2"
            fill="none" stroke="#4cc9f0" stroke-width="2" opacity=".7"/>
      <!-- exhaust -->
      <circle cx="210" cy="302" r="5" fill="none" stroke="#4cc9f0" stroke-width="1.5" opacity=".6"/>
      <!-- bumper line -->
      <line x1="70" y1="300" x2="230" y2="300" stroke="#4cc9f0" stroke-width="2" opacity=".45"/>
      <text x="150" y="98" text-anchor="middle" fill="#4cc9f0" font-size="14" font-weight="700">リア</text>
    `
  },
  {
    key: "side_left",
    label: "左サイド",
    tip: "車両の左側面全体が収まる位置から水平に",
    icon: `
      <path d="M4 28 L6 22 Q8 19 13 18 L17 14 Q19 13 22 13 L30 13 Q33 13 34 15 L36 22 Q37 23 36 28 Z" fill="none"/>
      <circle cx="12" cy="28" r="3" fill="#4cc9f0"/>
      <circle cx="28" cy="28" r="3" fill="#4cc9f0"/>
      <path d="M18 18 L31 18" stroke="#4cc9f0" stroke-width="1" opacity=".5"/>
    `,
    frame: `
      <g stroke="#4cc9f0" stroke-width="2.5" fill="none" opacity=".8">
        <path d="M22 42 L22 22 L42 22"/>
        <path d="M258 22 L278 22 L278 42"/>
        <path d="M278 358 L278 378 L258 378"/>
        <path d="M42 378 L22 378 L22 358"/>
      </g>
      <!-- side silhouette with wheel arches (front on LEFT) -->
      <path d="M 62 248
               Q 65 218 95 218 Q 125 218 128 248
               L 182 248
               Q 185 218 215 218 Q 245 218 248 248
               L 272 248
               Q 272 218 268 210 L 250 200 L 233 175
               Q 227 168 215 167 L 158 167
               Q 144 168 138 175 L 118 200 L 90 208
               Q 62 215 62 248 Z"
            fill="rgba(76,201,240,0.06)"
            stroke="#4cc9f0" stroke-width="3" stroke-dasharray="10 8"/>
      <!-- wheels -->
      <circle cx="95" cy="248" r="25" fill="none" stroke="#4cc9f0" stroke-width="2.5" opacity=".95"/>
      <circle cx="95" cy="248" r="9" fill="none" stroke="#4cc9f0" stroke-width="1.5" opacity=".65"/>
      <circle cx="215" cy="248" r="25" fill="none" stroke="#4cc9f0" stroke-width="2.5" opacity=".95"/>
      <circle cx="215" cy="248" r="9" fill="none" stroke="#4cc9f0" stroke-width="1.5" opacity=".65"/>
      <!-- window glass (front/rear combined) -->
      <path d="M 144 180 L 225 180 L 218 198 L 150 198 Z"
            fill="none" stroke="#4cc9f0" stroke-width="1.5" opacity=".55"/>
      <!-- door split -->
      <line x1="180" y1="198" x2="180" y2="245" stroke="#4cc9f0" stroke-width="1.5" opacity=".45"/>
      <!-- door handles -->
      <line x1="160" y1="213" x2="172" y2="213" stroke="#4cc9f0" stroke-width="2" opacity=".7"/>
      <line x1="188" y1="213" x2="200" y2="213" stroke="#4cc9f0" stroke-width="2" opacity=".7"/>
      <!-- side mirror -->
      <path d="M 140 178 L 132 172 L 132 180 Z" fill="none" stroke="#4cc9f0" stroke-width="1.5" opacity=".6"/>
      <!-- direction arrow: front -->
      <path d="M 32 140 L 18 148 L 32 156" fill="none" stroke="#4cc9f0" stroke-width="2" opacity=".6"/>
      <text x="42" y="152" fill="#4cc9f0" font-size="11" opacity=".8">前</text>
      <text x="150" y="140" text-anchor="middle" fill="#4cc9f0" font-size="14" font-weight="700">左サイド</text>
    `
  },
  {
    key: "side_right",
    label: "右サイド",
    tip: "車両の右側面全体が収まる位置から水平に",
    icon: `
      <path d="M4 28 Q3 23 4 22 L6 15 Q7 13 10 13 L18 13 Q21 13 23 14 L27 18 Q32 19 34 22 L36 28 Z" fill="none"/>
      <circle cx="12" cy="28" r="3" fill="#4cc9f0"/>
      <circle cx="28" cy="28" r="3" fill="#4cc9f0"/>
      <path d="M9 18 L22 18" stroke="#4cc9f0" stroke-width="1" opacity=".5"/>
    `,
    frame: `
      <g stroke="#4cc9f0" stroke-width="2.5" fill="none" opacity=".8">
        <path d="M22 42 L22 22 L42 22"/>
        <path d="M258 22 L278 22 L278 42"/>
        <path d="M278 358 L278 378 L258 378"/>
        <path d="M42 378 L22 378 L22 358"/>
      </g>
      <!-- side silhouette mirrored: front to the RIGHT -->
      <g transform="translate(300,0) scale(-1,1)">
        <path d="M 62 248
                 Q 65 218 95 218 Q 125 218 128 248
                 L 182 248
                 Q 185 218 215 218 Q 245 218 248 248
                 L 272 248
                 Q 272 218 268 210 L 250 200 L 233 175
                 Q 227 168 215 167 L 158 167
                 Q 144 168 138 175 L 118 200 L 90 208
                 Q 62 215 62 248 Z"
              fill="rgba(76,201,240,0.06)"
              stroke="#4cc9f0" stroke-width="3" stroke-dasharray="10 8"/>
        <circle cx="95" cy="248" r="25" fill="none" stroke="#4cc9f0" stroke-width="2.5" opacity=".95"/>
        <circle cx="95" cy="248" r="9" fill="none" stroke="#4cc9f0" stroke-width="1.5" opacity=".65"/>
        <circle cx="215" cy="248" r="25" fill="none" stroke="#4cc9f0" stroke-width="2.5" opacity=".95"/>
        <circle cx="215" cy="248" r="9" fill="none" stroke="#4cc9f0" stroke-width="1.5" opacity=".65"/>
        <path d="M 144 180 L 225 180 L 218 198 L 150 198 Z"
              fill="none" stroke="#4cc9f0" stroke-width="1.5" opacity=".55"/>
        <line x1="180" y1="198" x2="180" y2="245" stroke="#4cc9f0" stroke-width="1.5" opacity=".45"/>
        <line x1="160" y1="213" x2="172" y2="213" stroke="#4cc9f0" stroke-width="2" opacity=".7"/>
        <line x1="188" y1="213" x2="200" y2="213" stroke="#4cc9f0" stroke-width="2" opacity=".7"/>
        <path d="M 140 178 L 132 172 L 132 180 Z" fill="none" stroke="#4cc9f0" stroke-width="1.5" opacity=".6"/>
      </g>
      <path d="M 268 140 L 282 148 L 268 156" fill="none" stroke="#4cc9f0" stroke-width="2" opacity=".6"/>
      <text x="250" y="152" fill="#4cc9f0" font-size="11" opacity=".8">前</text>
      <text x="150" y="140" text-anchor="middle" fill="#4cc9f0" font-size="14" font-weight="700">右サイド</text>
    `
  },
  {
    key: "bonnet",
    label: "ボンネット",
    tip: "前方斜めからボンネット全体が台形に収まるように",
    icon: `
      <path d="M12 10 L28 10 L32 30 L8 30 Z" fill="none"/>
      <line x1="20" y1="12" x2="20" y2="30" stroke="#4cc9f0" stroke-width="1" opacity=".5"/>
      <circle cx="20" cy="28" r="1.5" fill="#4cc9f0"/>
    `,
    frame: `
      <g stroke="#4cc9f0" stroke-width="2.5" fill="none" opacity=".8">
        <path d="M22 42 L22 22 L42 22"/>
        <path d="M258 22 L278 22 L278 42"/>
        <path d="M278 358 L278 378 L258 378"/>
        <path d="M42 378 L22 378 L22 358"/>
      </g>
      <!-- Hood trapezoid (wider at near/bottom) -->
      <path d="M 75 115 L 225 115 L 255 305 L 45 305 Z"
            fill="rgba(76,201,240,0.06)"
            stroke="#4cc9f0" stroke-width="3" stroke-dasharray="10 8"/>
      <!-- center crease -->
      <line x1="150" y1="120" x2="150" y2="300" stroke="#4cc9f0" stroke-width="1.5" opacity=".45" stroke-dasharray="5 4"/>
      <!-- side character lines -->
      <line x1="98" y1="125" x2="80" y2="295" stroke="#4cc9f0" stroke-width="1" opacity=".35"/>
      <line x1="202" y1="125" x2="220" y2="295" stroke="#4cc9f0" stroke-width="1" opacity=".35"/>
      <!-- badge at front edge -->
      <circle cx="150" cy="303" r="11" fill="none" stroke="#4cc9f0" stroke-width="2" opacity=".7"/>
      <!-- wipers hint at windshield base (top) -->
      <path d="M 110 122 L 120 135 L 130 122" fill="none" stroke="#4cc9f0" stroke-width="1.5" opacity=".4"/>
      <path d="M 170 122 L 180 135 L 190 122" fill="none" stroke="#4cc9f0" stroke-width="1.5" opacity=".4"/>
      <text x="150" y="100" text-anchor="middle" fill="#4cc9f0" font-size="14" font-weight="700">ボンネット</text>
    `
  },
  {
    key: "roof",
    label: "ルーフ",
    tip: "斜め上から屋根全体が台形に収まるように",
    icon: `
      <path d="M14 8 L26 8 Q29 8 29 11 L32 30 Q32 32 30 32 L10 32 Q8 32 8 30 L11 11 Q11 8 14 8 Z" fill="none"/>
      <rect x="14" y="14" width="12" height="12" rx="1.5" opacity=".6"/>
    `,
    frame: `
      <g stroke="#4cc9f0" stroke-width="2.5" fill="none" opacity=".8">
        <path d="M22 42 L22 22 L42 22"/>
        <path d="M258 22 L278 22 L278 42"/>
        <path d="M278 358 L278 378 L258 378"/>
        <path d="M42 378 L22 378 L22 358"/>
      </g>
      <!-- Roof plan view -->
      <path d="M 95 120
               L 205 120
               Q 222 120 224 135
               L 240 290
               Q 240 305 225 305
               L 75 305
               Q 60 305 60 290
               L 76 135
               Q 78 120 95 120 Z"
            fill="rgba(76,201,240,0.06)"
            stroke="#4cc9f0" stroke-width="3" stroke-dasharray="10 8"/>
      <!-- Front windshield hint -->
      <line x1="82" y1="140" x2="218" y2="140" stroke="#4cc9f0" stroke-width="1.5" opacity=".4" stroke-dasharray="4 4"/>
      <!-- Rear windshield hint -->
      <line x1="68" y1="285" x2="232" y2="285" stroke="#4cc9f0" stroke-width="1.5" opacity=".4" stroke-dasharray="4 4"/>
      <!-- Sunroof / panel -->
      <rect x="115" y="160" width="70" height="100" rx="8"
            fill="none" stroke="#4cc9f0" stroke-width="2" opacity=".6"/>
      <line x1="150" y1="160" x2="150" y2="260" stroke="#4cc9f0" stroke-width="1" opacity=".35"/>
      <!-- Antenna tip -->
      <circle cx="225" cy="300" r="4" fill="none" stroke="#4cc9f0" stroke-width="1.5" opacity=".6"/>
      <text x="150" y="105" text-anchor="middle" fill="#4cc9f0" font-size="14" font-weight="700">ルーフ</text>
    `
  },
  {
    key: "interior",
    label: "内装（運転席）",
    tip: "ハンドルとメーターパネルが中央に大きく写るように",
    icon: `
      <circle cx="20" cy="24" r="9" fill="none"/>
      <circle cx="20" cy="24" r="3" fill="#4cc9f0"/>
      <line x1="20" y1="17" x2="20" y2="31" stroke="#4cc9f0" stroke-width="1.5"/>
      <line x1="13" y1="24" x2="27" y2="24" stroke="#4cc9f0" stroke-width="1.5"/>
      <path d="M7 10 Q20 7 33 10" stroke="#4cc9f0" stroke-width="1.5" fill="none" opacity=".6"/>
    `,
    frame: `
      <g stroke="#4cc9f0" stroke-width="2.5" fill="none" opacity=".8">
        <path d="M22 42 L22 22 L42 22"/>
        <path d="M258 22 L278 22 L278 42"/>
        <path d="M278 358 L278 378 L258 378"/>
        <path d="M42 378 L22 378 L22 358"/>
      </g>
      <!-- Dashboard curve -->
      <path d="M 15 160 Q 150 135 285 160 L 285 220 Q 150 200 15 220 Z"
            fill="rgba(76,201,240,0.05)"
            stroke="#4cc9f0" stroke-width="2" opacity=".6" stroke-dasharray="8 6"/>
      <!-- Air vents -->
      <rect x="40" y="176" width="30" height="14" rx="3" fill="none" stroke="#4cc9f0" stroke-width="1.5" opacity=".5"/>
      <rect x="230" y="176" width="30" height="14" rx="3" fill="none" stroke="#4cc9f0" stroke-width="1.5" opacity=".5"/>
      <!-- Center console screen -->
      <rect x="125" y="175" width="50" height="30" rx="3" fill="none" stroke="#4cc9f0" stroke-width="1.5" opacity=".55"/>
      <!-- Instrument cluster -->
      <rect x="90" y="220" width="120" height="60" rx="10" fill="none" stroke="#4cc9f0" stroke-width="2" opacity=".55"/>
      <circle cx="120" cy="250" r="18" fill="none" stroke="#4cc9f0" stroke-width="1.5" opacity=".55"/>
      <circle cx="180" cy="250" r="18" fill="none" stroke="#4cc9f0" stroke-width="1.5" opacity=".55"/>
      <!-- Steering wheel (the main target) -->
      <circle cx="150" cy="310" r="62"
              fill="rgba(76,201,240,0.08)"
              stroke="#4cc9f0" stroke-width="3" stroke-dasharray="10 8"/>
      <circle cx="150" cy="310" r="22" fill="none" stroke="#4cc9f0" stroke-width="2" opacity=".7"/>
      <!-- T-spokes -->
      <line x1="150" y1="288" x2="150" y2="332" stroke="#4cc9f0" stroke-width="2.5" opacity=".7"/>
      <line x1="128" y1="310" x2="172" y2="310" stroke="#4cc9f0" stroke-width="2.5" opacity=".7"/>
      <!-- Horn/logo in the middle -->
      <rect x="138" y="302" width="24" height="16" rx="2" fill="none" stroke="#4cc9f0" stroke-width="1.5" opacity=".6"/>
      <text x="150" y="128" text-anchor="middle" fill="#4cc9f0" font-size="14" font-weight="700">運転席まわり</text>
    `
  },
  {
    key: "odometer",
    label: "走行距離メーター",
    tip: "メーター盤面全体が画面内に大きく写るように近づいて",
    icon: `
      <rect x="5" y="12" width="30" height="18" rx="3" fill="none"/>
      <circle cx="13" cy="21" r="5" fill="none"/>
      <circle cx="27" cy="21" r="5" fill="none"/>
      <line x1="13" y1="21" x2="16" y2="18" stroke="#4cc9f0" stroke-width="1.2"/>
      <line x1="27" y1="21" x2="24" y2="18" stroke="#4cc9f0" stroke-width="1.2"/>
    `,
    frame: `
      <g stroke="#4cc9f0" stroke-width="2.5" fill="none" opacity=".8">
        <path d="M22 42 L22 22 L42 22"/>
        <path d="M258 22 L278 22 L278 42"/>
        <path d="M278 358 L278 378 L258 378"/>
        <path d="M42 378 L22 378 L22 358"/>
      </g>
      <!-- Cluster bezel -->
      <rect x="35" y="150" width="230" height="170" rx="20"
            fill="rgba(76,201,240,0.06)"
            stroke="#4cc9f0" stroke-width="3" stroke-dasharray="10 8"/>
      <!-- Speedometer -->
      <circle cx="100" cy="230" r="55" fill="none" stroke="#4cc9f0" stroke-width="2.5" opacity=".9"/>
      <circle cx="100" cy="230" r="6" fill="#4cc9f0" opacity=".7"/>
      <!-- Tachometer -->
      <circle cx="200" cy="230" r="55" fill="none" stroke="#4cc9f0" stroke-width="2.5" opacity=".9"/>
      <circle cx="200" cy="230" r="6" fill="#4cc9f0" opacity=".7"/>
      <!-- Needles -->
      <line x1="100" y1="230" x2="130" y2="200" stroke="#4cc9f0" stroke-width="2.5" opacity=".8"/>
      <line x1="200" y1="230" x2="178" y2="195" stroke="#4cc9f0" stroke-width="2.5" opacity=".8"/>
      <!-- Tick marks (around each gauge, 12 ticks) -->
      <g stroke="#4cc9f0" stroke-width="1.5" opacity=".55">
        <line x1="100" y1="182" x2="100" y2="190"/>
        <line x1="100" y1="270" x2="100" y2="278"/>
        <line x1="52" y1="230" x2="60" y2="230"/>
        <line x1="140" y1="230" x2="148" y2="230"/>
        <line x1="67" y1="197" x2="73" y2="203"/>
        <line x1="127" y1="263" x2="133" y2="257"/>
        <line x1="67" y1="263" x2="73" y2="257"/>
        <line x1="127" y1="197" x2="133" y2="203"/>

        <line x1="200" y1="182" x2="200" y2="190"/>
        <line x1="200" y1="270" x2="200" y2="278"/>
        <line x1="152" y1="230" x2="160" y2="230"/>
        <line x1="240" y1="230" x2="248" y2="230"/>
        <line x1="167" y1="197" x2="173" y2="203"/>
        <line x1="227" y1="263" x2="233" y2="257"/>
        <line x1="167" y1="263" x2="173" y2="257"/>
        <line x1="227" y1="197" x2="233" y2="203"/>
      </g>
      <!-- Digital odometer display between gauges -->
      <rect x="125" y="290" width="50" height="22" rx="3"
            fill="rgba(0,0,0,0.4)" stroke="#4cc9f0" stroke-width="2" opacity=".9"/>
      <text x="150" y="306" text-anchor="middle" fill="#4cc9f0" font-size="11" font-weight="700" opacity=".85" font-family="monospace">km</text>
      <text x="150" y="135" text-anchor="middle" fill="#4cc9f0" font-size="14" font-weight="700">走行距離メーター</text>
    `
  }
];

// 年式リスト
const CURRENT_YEAR = new Date().getFullYear();
const YEAR_LIST = [];
for (let y = CURRENT_YEAR; y >= CURRENT_YEAR - 30; y--) YEAR_LIST.push(y);

window.CheckerData = { CAR_DATA, CAPTURE_SHOTS, YEAR_LIST };
