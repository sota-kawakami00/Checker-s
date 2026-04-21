// ============================================================
// 認証（ローカルストレージベース・デモ実装）
// 本番ではサーバー側で bcrypt 等で適切にハッシュ化すること
// ============================================================

const AUTH_KEY = "checker_s_users_v1";
const SESSION_KEY = "checker_s_session_v1";
const DEMO_USER = { email: "demo@checker.jp", password: "demo1234", name: "デモユーザー" };

// 簡易的なSHA-256ベースハッシュ（ブラウザ標準SubtleCrypto利用）
async function hashPassword(pw) {
  const enc = new TextEncoder().encode("checker-s-salt::" + pw);
  const buf = await crypto.subtle.digest("SHA-256", enc);
  return Array.from(new Uint8Array(buf)).map(b => b.toString(16).padStart(2, "0")).join("");
}

function loadUsers() {
  try {
    return JSON.parse(localStorage.getItem(AUTH_KEY) || "[]");
  } catch { return []; }
}

function saveUsers(users) {
  localStorage.setItem(AUTH_KEY, JSON.stringify(users));
}

async function ensureDemoUser() {
  const users = loadUsers();
  if (!users.find(u => u.email === DEMO_USER.email)) {
    users.push({
      email: DEMO_USER.email,
      name: DEMO_USER.name,
      passwordHash: await hashPassword(DEMO_USER.password),
      createdAt: Date.now()
    });
    saveUsers(users);
  }
}

async function registerUser({ name, email, password }) {
  const users = loadUsers();
  email = email.trim().toLowerCase();
  if (users.find(u => u.email === email)) {
    throw new Error("このメールアドレスは既に登録されています");
  }
  const user = {
    email,
    name: name.trim(),
    passwordHash: await hashPassword(password),
    createdAt: Date.now()
  };
  users.push(user);
  saveUsers(users);
  setSession(user);
  return user;
}

async function loginUser({ email, password }) {
  email = email.trim().toLowerCase();
  const users = loadUsers();
  const user = users.find(u => u.email === email);
  if (!user) throw new Error("ユーザーが見つかりません");
  const h = await hashPassword(password);
  if (user.passwordHash !== h) throw new Error("パスワードが正しくありません");
  setSession(user);
  return user;
}

function setSession(user) {
  const s = { email: user.email, name: user.name, loggedInAt: Date.now() };
  localStorage.setItem(SESSION_KEY, JSON.stringify(s));
}

function getSession() {
  try {
    return JSON.parse(localStorage.getItem(SESSION_KEY) || "null");
  } catch { return null; }
}

function clearSession() {
  localStorage.removeItem(SESSION_KEY);
}

window.CheckerAuth = {
  ensureDemoUser,
  registerUser,
  loginUser,
  getSession,
  clearSession
};
