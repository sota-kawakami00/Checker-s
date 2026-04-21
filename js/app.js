// ============================================================
// アプリ本体：画面遷移・フォーム制御・撮影フロー結線
// ============================================================

const App = (() => {
  const $  = (sel) => document.querySelector(sel);
  const $$ = (sel) => document.querySelectorAll(sel);

  const state = {
    user: null,
    vehicle: null,
    shotIdx: 0,
    captures: [],    // { key, label, dataUrl }
    lastResult: null
  };

  const HISTORY_KEY = "checker_s_history_v1";

  // ---------- View切替 ----------
  function showView(id) {
    $$(".view").forEach(v => v.classList.remove("active"));
    const el = document.getElementById(id);
    if (el) el.classList.add("active");
    window.scrollTo(0, 0);
  }

  // ---------- ローダー ----------
  function loader(show, text, sub) {
    const L = $("#loader");
    if (text) $(".loader-text", L) && ($(".loader-text").textContent = text);
    if (sub)  $("#loaderSub") && ($("#loaderSub").textContent = sub);
    L.classList.toggle("hidden", !show);
  }

  // ---------- 認証画面 ----------
  function initAuthView() {
    $$(".auth-tabs .tab").forEach(t => {
      t.addEventListener("click", () => {
        $$(".auth-tabs .tab").forEach(x => x.classList.remove("active"));
        t.classList.add("active");
        $$(".auth-form").forEach(f => f.classList.remove("active"));
        const target = t.dataset.tab === "login" ? "#form-login" : "#form-register";
        $(target).classList.add("active");
      });
    });

    $("#form-login").addEventListener("submit", async (e) => {
      e.preventDefault();
      try {
        loader(true, "ログイン中", "認証情報を確認しています");
        const u = await CheckerAuth.loginUser({
          email: $("#login-email").value,
          password: $("#login-password").value
        });
        state.user = u;
        loader(false);
        enterHome();
      } catch (err) {
        loader(false);
        alert(err.message || "ログインに失敗しました");
      }
    });

    $("#form-register").addEventListener("submit", async (e) => {
      e.preventDefault();
      try {
        loader(true, "登録中", "アカウントを作成しています");
        const u = await CheckerAuth.registerUser({
          name: $("#reg-name").value,
          email: $("#reg-email").value,
          password: $("#reg-password").value
        });
        state.user = u;
        loader(false);
        enterHome();
      } catch (err) {
        loader(false);
        alert(err.message || "登録に失敗しました");
      }
    });
  }

  // ---------- ホーム ----------
  function enterHome() {
    const u = state.user || CheckerAuth.getSession();
    state.user = u;
    const name = u?.name || "ゲスト";
    $("#home-username").textContent = name;
    $("#home-avatar").textContent = (name[0] || "U").toUpperCase();
    renderHistory();
    showView("view-home");
  }

  function initHome() {
    $("#btn-start").addEventListener("click", () => enterVehicle());
    $("#btn-logout").addEventListener("click", () => {
      if (!confirm("ログアウトしますか？")) return;
      CheckerAuth.clearSession();
      state.user = null;
      showView("view-auth");
    });
  }

  function loadHistory() {
    try { return JSON.parse(localStorage.getItem(HISTORY_KEY) || "[]"); }
    catch { return []; }
  }
  function saveHistoryItem(item) {
    const list = loadHistory();
    list.unshift(item);
    if (list.length > 20) list.length = 20;
    localStorage.setItem(HISTORY_KEY, JSON.stringify(list));
  }
  function renderHistory() {
    const list = loadHistory();
    const box = $("#history-list");
    if (!list.length) {
      box.innerHTML = '<div class="empty">まだ査定履歴はありません</div>';
      return;
    }
    box.innerHTML = list.map((it, i) => `
      <div class="history-item" data-idx="${i}">
        <img class="thumb" src="${it.thumb || ''}" alt=""/>
        <div class="info">
          <div class="title">${escapeHtml(it.vehicle.make)} ${escapeHtml(it.vehicle.model)}</div>
          <div class="sub">${it.vehicle.year}年 / ${Number(it.vehicle.mileage).toLocaleString()}km / ${new Date(it.createdAt).toLocaleDateString("ja-JP")}</div>
        </div>
        <div class="price">¥${Number(it.final).toLocaleString()}</div>
      </div>
    `).join("");
    box.querySelectorAll(".history-item").forEach(el => {
      el.addEventListener("click", () => {
        const idx = Number(el.dataset.idx);
        const it  = list[idx];
        if (!it) return;
        state.lastResult = it;
        renderResult(it);
        showView("view-result");
      });
    });
  }

  function escapeHtml(s) {
    return String(s || "").replace(/[&<>"']/g, c => ({
      "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"
    }[c]));
  }

  // ---------- 車両入力 ----------
  function enterVehicle() {
    populateMakes();
    populateYears();
    showView("view-vehicle");
  }
  function populateMakes() {
    const sel = $("#v-make");
    sel.innerHTML = '<option value="">選択してください</option>' +
      Object.keys(CheckerData.CAR_DATA).map(m => `<option value="${m}">${m}</option>`).join("");
  }
  function populateModels(make) {
    const sel = $("#v-model");
    if (!make) {
      sel.disabled = true;
      sel.innerHTML = '<option value="">メーカーを先に選択</option>';
      return;
    }
    const models = Object.keys(CheckerData.CAR_DATA[make] || {});
    sel.disabled = false;
    sel.innerHTML = '<option value="">選択してください</option>' +
      models.map(m => `<option value="${m}">${m}</option>`).join("");
  }
  function populateYears() {
    const sel = $("#v-year");
    sel.innerHTML = CheckerData.YEAR_LIST.map(y => `<option value="${y}">${y}</option>`).join("");
  }

  function initVehicle() {
    $("#v-make").addEventListener("change", (e) => populateModels(e.target.value));
    $("#form-vehicle").addEventListener("submit", (e) => {
      e.preventDefault();
      const v = {
        make:         $("#v-make").value,
        model:        $("#v-model").value,
        year:         $("#v-year").value,
        mileage:      $("#v-mileage").value,
        color:        $("#v-color").value,
        transmission: $("#v-transmission").value,
        plate:        $("#v-plate").value.trim()
      };
      if (!v.make || !v.model || !v.year || v.mileage === "") {
        alert("必須項目を入力してください");
        return;
      }
      state.vehicle = v;
      state.captures = [];
      state.shotIdx = 0;
      enterCaptureIntro();
    });
  }

  // ---------- 撮影イントロ ----------
  function enterCaptureIntro() {
    $("#intro-shot-count").textContent = CheckerData.CAPTURE_SHOTS.length;
    const grid = $("#shot-grid");
    grid.innerHTML = CheckerData.CAPTURE_SHOTS.map((s, i) => `
      <div class="cell">
        <svg viewBox="0 0 40 40" fill="none" stroke="#4cc9f0" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
          ${s.icon || `<rect x="6" y="10" width="28" height="22" rx="4"/>`}
        </svg>
        <div>${i+1}.${s.label}</div>
      </div>
    `).join("");
    showView("view-capture-intro");
  }

  function initCaptureIntro() {
    $("#btn-start-capture").addEventListener("click", () => {
      state.shotIdx = 0;
      state.captures = [];
      beginCamera();
    });
    // Back buttons (共通)
    document.body.addEventListener("click", (e) => {
      const el = e.target.closest("[data-back]");
      if (el) showView(el.dataset.back);
    });
  }

  // ---------- カメラ撮影 ----------
  async function beginCamera() {
    renderCameraShot();
    showCameraView();
    $("#camera-error").classList.add("hidden");
    try {
      await CheckerCamera.start();
    } catch (e) {
      $("#camera-error").classList.remove("hidden");
    }
  }

  function showCameraView() {
    // camera-view は position:fixed で active クラスで表示
    $$(".view").forEach(v => v.classList.remove("active"));
    $("#view-camera").classList.add("active");
  }

  function renderCameraShot() {
    const total = CheckerData.CAPTURE_SHOTS.length;
    const shot  = CheckerData.CAPTURE_SHOTS[state.shotIdx];
    $("#shot-title-label").textContent = `${shot.label} を撮影`;
    $("#shot-title-step").textContent  = `${state.shotIdx + 1} / ${total}`;
    $("#camera-tip").textContent = shot.tip;
    $("#frame-svg").innerHTML = shot.frame;
    renderThumbStrip();
  }

  function renderThumbStrip() {
    const strip = $("#thumb-strip");
    strip.innerHTML = CheckerData.CAPTURE_SHOTS.map((s, i) => {
      const cap = state.captures[i];
      const classes = ["thumb"];
      if (cap) classes.push("captured");
      if (i === state.shotIdx) classes.push("active");
      if (cap) return `<img class="${classes.join(' ')}" src="${cap.dataUrl}" alt="${s.label}" data-idx="${i}"/>`;
      return `<div class="${classes.join(' ')}" data-idx="${i}" title="${s.label}"></div>`;
    }).join("");
    strip.querySelectorAll("[data-idx]").forEach(el => {
      el.addEventListener("click", () => {
        state.shotIdx = Number(el.dataset.idx);
        renderCameraShot();
      });
    });
  }

  function initCamera() {
    $("#btn-shutter").addEventListener("click", onShutter);
    $("#btn-switch-camera").addEventListener("click", () => CheckerCamera.switchFacing());
    $("#btn-cancel-camera").addEventListener("click", () => {
      CheckerCamera.stop();
      enterCaptureIntro();
    });
    $("#btn-camera-retry").addEventListener("click", async () => {
      $("#camera-error").classList.add("hidden");
      try { await CheckerCamera.start(); }
      catch(e) { $("#camera-error").classList.remove("hidden"); }
    });
    $("#btn-camera-simulate").addEventListener("click", () => {
      $("#camera-error").classList.add("hidden");
      // デモモードで全撮影を埋める
      state.captures = CheckerData.CAPTURE_SHOTS.map(s => ({
        key: s.key, label: s.label,
        dataUrl: CheckerCamera.generateDemoImage(s.label, pickColor())
      }));
      CheckerCamera.stop();
      enterReview();
    });
  }

  function pickColor() {
    const map = { "ホワイト":"#f2f3f7","ブラック":"#202630","シルバー":"#b9c0cc","グレー":"#636b77",
                  "レッド":"#c0392b","ブルー":"#2b6cc0","その他":"#6a7ea1" };
    return map[state.vehicle?.color] || "#4cc9f0";
  }

  function onShutter() {
    let dataUrl = CheckerCamera.capture();
    if (!dataUrl) {
      const shot = CheckerData.CAPTURE_SHOTS[state.shotIdx];
      dataUrl = CheckerCamera.generateDemoImage(shot.label, pickColor());
    }
    const shot = CheckerData.CAPTURE_SHOTS[state.shotIdx];
    state.captures[state.shotIdx] = { key: shot.key, label: shot.label, dataUrl };
    // flash effect
    flash();
    const total = CheckerData.CAPTURE_SHOTS.length;
    // 未撮影の次のindexを探す
    let next = -1;
    for (let i = 0; i < total; i++) {
      if (!state.captures[i]) { next = i; break; }
    }
    if (next === -1) {
      CheckerCamera.stop();
      enterReview();
      return;
    }
    state.shotIdx = next;
    renderCameraShot();
  }

  function flash() {
    const v = $("#view-camera");
    const f = document.createElement("div");
    f.style.cssText = "position:absolute;inset:0;background:#fff;opacity:.85;z-index:20;pointer-events:none;transition:opacity .3s;";
    v.appendChild(f);
    requestAnimationFrame(() => f.style.opacity = "0");
    setTimeout(() => f.remove(), 320);
  }

  // ---------- レビュー ----------
  function enterReview() {
    const grid = $("#review-grid");
    grid.innerHTML = state.captures.map((c, i) => `
      <div class="cell" data-idx="${i}">
        <img src="${c.dataUrl}" alt="${c.label}"/>
        <div class="label">${i+1}. ${c.label}</div>
        <button class="retake" data-retake="${i}">撮り直す</button>
      </div>
    `).join("");
    grid.querySelectorAll("[data-retake]").forEach(b => {
      b.addEventListener("click", (e) => {
        e.stopPropagation();
        state.shotIdx = Number(b.dataset.retake);
        state.captures[state.shotIdx] = null;
        beginCamera();
      });
    });
    showView("view-review");
  }

  function initReview() {
    $("#btn-review-back").addEventListener("click", () => enterCaptureIntro());
    $("#btn-analyze").addEventListener("click", runAnalysis);
  }

  // ---------- AI解析 & 結果 ----------
  async function runAnalysis() {
    const steps = [
      "画像を前処理しています",
      "特徴量を抽出しています",
      "傷・凹み・修復歴を検出中",
      "市場データと照合中",
      "最終査定を算出中"
    ];
    loader(true, "AI解析中...", steps[0]);
    let i = 0;
    const timer = setInterval(() => {
      i = Math.min(steps.length - 1, i + 1);
      const sub = $("#loaderSub"); if (sub) sub.textContent = steps[i];
    }, 700);

    try {
      const damages = await CheckerAI.detectAll(state.captures);
      const calc    = CheckerAI.calculateValuation({ vehicle: state.vehicle, damages });
      const result  = {
        vehicle: state.vehicle,
        damages,
        ...calc,
        captures: state.captures,
        createdAt: Date.now(),
        customer: state.user?.name,
        thumb: state.captures[0]?.dataUrl || null
      };
      // 合計確認用に少し待機してリアリティ演出
      await wait(1600);
      state.lastResult = result;
      renderResult(result);
      saveHistoryItem({
        vehicle: result.vehicle,
        final:   result.final,
        low:     result.low,
        high:    result.high,
        damages: result.damages,
        breakdown: result.breakdown,
        captures: result.captures,
        thumb:   result.thumb,
        createdAt: result.createdAt,
        customer: result.customer
      });
      showView("view-result");
    } catch (e) {
      alert("解析に失敗しました: " + (e.message || e));
    } finally {
      clearInterval(timer);
      loader(false);
    }
  }

  function wait(ms) { return new Promise(r => setTimeout(r, ms)); }

  function renderResult(r) {
    $("#result-price").textContent = "¥" + Number(r.final).toLocaleString();
    $("#result-range").textContent = `¥${Number(r.low).toLocaleString()} 〜 ¥${Number(r.high).toLocaleString()}`;
    $("#result-vehicle").textContent = `${r.vehicle.make} ${r.vehicle.model}`;
    $("#result-year").textContent    = r.vehicle.year + "年";
    $("#result-mileage").textContent = Number(r.vehicle.mileage).toLocaleString() + " km";
    $("#result-color").textContent   = r.vehicle.color;

    // damages
    const box = $("#damage-list");
    if (!r.damages.length) {
      box.innerHTML = `<div class="damage-item"><div class="damage-icon low">◎</div><div class="info"><div class="title">目立ったダメージは検出されませんでした</div><div class="sub">良好なコンディションです</div></div></div>`;
    } else {
      box.innerHTML = r.damages.map(d => `
        <div class="damage-item">
          <div class="damage-icon ${d.severity}">${d.severity === 'high' ? '!' : d.severity === 'mid' ? '▲' : '･'}</div>
          <div class="info">
            <div class="title">${escapeHtml(d.location)} / ${escapeHtml(d.label)}</div>
            <div class="sub">信頼度 ${Math.round(d.confidence*100)}%</div>
          </div>
          <div class="deduct">-¥${Math.round(d.deduct*10000).toLocaleString()}</div>
        </div>
      `).join("");
    }

    // breakdown
    $("#breakdown").innerHTML = r.breakdown.map(b => `
      <div class="breakdown-row">
        <span>${escapeHtml(b.label)}</span>
        <span class="${b.value < 0 ? 'minus' : ''}">${b.value < 0 ? '-' : ''}¥${Math.abs(b.value).toLocaleString()}</span>
      </div>
    `).join("");
  }

  function initResult() {
    $("#btn-download-pdf").addEventListener("click", async () => {
      if (!state.lastResult) return;
      try {
        loader(true, "PDFを生成中...", "見積書を作成しています");
        await CheckerPDF.download(state.lastResult);
      } catch (e) {
        alert("PDF生成に失敗しました: " + (e.message || e));
      } finally {
        loader(false);
      }
    });
    $("#btn-share-pdf").addEventListener("click", async () => {
      if (!state.lastResult) return;
      try {
        loader(true, "PDFを生成中...", "共有用ファイルを準備しています");
        await CheckerPDF.share(state.lastResult);
      } catch (e) {
        alert("共有に失敗しました: " + (e.message || e));
      } finally {
        loader(false);
      }
    });
    $("#btn-new-assessment").addEventListener("click", () => {
      state.vehicle = null;
      state.captures = [];
      state.shotIdx = 0;
      state.lastResult = null;
      enterHome();
    });
  }

  // ---------- 起動 ----------
  async function boot() {
    await CheckerAuth.ensureDemoUser();

    initAuthView();
    initHome();
    initVehicle();
    initCaptureIntro();
    initCamera();
    initReview();
    initResult();

    const s = CheckerAuth.getSession();
    if (s) {
      state.user = s;
      enterHome();
    } else {
      showView("view-auth");
    }

    // Service Worker 登録
    if ("serviceWorker" in navigator) {
      navigator.serviceWorker.register("service-worker.js").catch(() => {});
    }
  }

  return { boot };
})();

document.addEventListener("DOMContentLoaded", () => App.boot());
