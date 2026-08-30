/*
 * 트레이닝 랩 — 오케스트레이터
 *
 * 세션 백엔드는 드라이버로 분리:
 *   DRIVER=sim      세션 = 로컬 디렉터리 + kubectl/virtctl 시뮬레이터 (클러스터 불필요)
 *   DRIVER=kubevirt 세션 = snacklab 네임스페이스의 실제 KubeVirt VM
 *                   터미널 = virtctl console, 검증 = checker pod 경유 SSH
 *   DRIVER=pod      세션 = systemd가 PID 1로 도는 privileged pod (리눅스 랩)
 *                   터미널 = kubectl exec + su - learner, 검증 = kubectl exec bash -s
 */
const express = require('express');
const http = require('http');
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');
const { spawn, execFile } = require('child_process');
const { WebSocketServer } = require('ws');

const ROOT = __dirname;
const CONTENT = path.join(ROOT, 'content');
const SESSIONS_DIR = path.join(ROOT, 'sessions');
const SIMBIN = path.join(ROOT, 'simbin');
const VM_TEMPLATE = path.join(ROOT, '..', 'deploy', 'learner-vm.template.yaml');
const DISK_TEMPLATE = path.join(ROOT, '..', 'deploy', 'learner-disk.template.yaml');
const POD_TEMPLATE = process.env.POD_TEMPLATE || path.join(ROOT, '..', 'deploy', 'learner-pod.template.yaml');
// Registry prefix prepended to image refs that carry no registry/namespace of their own
// (i.e. no "/" in the ref). Lets course bundles name images portably ("snacklab-k8s:v5")
// while each site picks its registry via IMAGE_REGISTRY.
const IMAGE_REGISTRY = (process.env.IMAGE_REGISTRY || 'ghcr.io/admuppy').replace(/\/$/, '');
const resolveImage = ref => (ref && !ref.includes('/')) ? `${IMAGE_REGISTRY}/${ref}` : ref;
// 기본 학습자 환경(pod 드라이버) — 과목(course.json)이 image/resources를 선언하면 그 값으로 치환
const LEARNER_IMAGE = resolveImage(process.env.LEARNER_IMAGE || 'snacklab-linux:v2');
// ephemeral-storage: 노드 디스크 고갈 방지. 실측(2026-08-04) CKA 전 문항 완주 시 kubelet 계상
// 756MiB — 한도는 폭주 감지용으로 넉넉히, requests 는 스케줄러가 랩 파드를 노드에 몰아넣지 않도록.
// (privileged 라 호스트 디스크를 직접 마운트하면 이 한도를 우회할 수 있다 — 사고 방지용이지
//  악의적 사용자 차단용이 아니다. 그쪽은 NetworkPolicy·전용 노드풀이 담당한다.)
const LEARNER_RES = {
  reqCpu: process.env.LEARNER_CPU_REQUEST || '250m',
  reqMem: process.env.LEARNER_MEM_REQUEST || '1Gi',
  reqEph: process.env.LEARNER_EPH_REQUEST || '2Gi',
  limCpu: process.env.LEARNER_CPU_LIMIT || '2',
  limMem: process.env.LEARNER_MEM_LIMIT || '4Gi',
  limEph: process.env.LEARNER_EPH_LIMIT || '8Gi',
};

const DRIVER = process.env.DRIVER || 'sim';
const NS = process.env.LAB_NAMESPACE || 'snacklab';
const PORT = Number(process.env.PORT || 3000);
const TTL_MINUTES = Number(process.env.TTL_MINUTES || 60);
const EXTEND_MINUTES = Number(process.env.EXTEND_MINUTES || 30);
const WARM_POOL_SIZE = Number(process.env.WARM_POOL_SIZE || 2);
// 부팅+SSH까지 마친 대기 VM 수 — 세션 시작이 수 초가 된다 (TCG 부팅 ~5분을 미리 치름)
const WARM_VM_POOL = Number(process.env.WARM_VM_POOL || 2);
// 노드 용량 보호: 활성(Provisioning/Running) 세션 상한 — 초과 시 429
// pod는 VM(6.4Gi 고정)과 달리 burstable 1Gi 요청이라 기본 상한을 높게 잡는다
const MAX_SESSIONS = Number(process.env.MAX_SESSIONS ||
  ({ pod: 16, docker: 8 }[process.env.DRIVER] || 4)); // docker = single host, keep it modest
// 사용자당 동시 세션 상한 (admin 제외, 0 = 무제한)
const MAX_SESSIONS_PER_USER = Number(process.env.MAX_SESSIONS_PER_USER || 1);
// 웜풀 동적 조정: 최근 30분 할당 수요만큼 min~max 사이에서 목표치 결정 — 유휴 시간대엔 min까지 축소
// min/max 는 관리자 대시보드에서 런타임 조정 가능(let) — PVC(warmpool.json)에 영속되어 재시작에도 유지.
let WARM_POOL_MAX = Number(process.env.WARM_POOL_MAX || WARM_POOL_SIZE);
let WARM_POOL_MIN = Number(process.env.WARM_POOL_MIN ?? Math.min(1, WARM_POOL_MAX));
const WARM_POOL_HARD_CAP = Number(process.env.WARM_POOL_HARD_CAP || 10);
const WARMPOOL_FILE = path.join(SESSIONS_DIR, 'warmpool.json');
(function loadWarmCfg() {
  try {
    const o = JSON.parse(fs.readFileSync(WARMPOOL_FILE, 'utf8'));
    if (Number.isInteger(o.min) && Number.isInteger(o.max) &&
        o.min >= 0 && o.min <= o.max && o.max <= WARM_POOL_HARD_CAP) {
      WARM_POOL_MIN = o.min; WARM_POOL_MAX = o.max;
      console.log(`[warmpool] 오버라이드 로드: min=${o.min} max=${o.max}`);
    }
  } catch { /* 파일 없음/손상 → env 기본값 유지 */ }
})();
function saveWarmCfg() {
  try {
    fs.mkdirSync(SESSIONS_DIR, { recursive: true });
    const tmp = WARMPOOL_FILE + '.tmp';
    fs.writeFileSync(tmp, JSON.stringify({ min: WARM_POOL_MIN, max: WARM_POOL_MAX }, null, 2));
    fs.renameSync(tmp, WARMPOOL_FILE);
  } catch (e) { console.error('[warmpool] 저장 실패:', e.message); }
}
// 유휴 회수: 터미널 입력·검증이 IDLE_MINUTES 동안 없으면 터미널에 경고, GRACE 뒤에도 없으면 회수 (0 = 비활성)
const IDLE_MINUTES = Number(process.env.IDLE_MINUTES ?? 15);
const IDLE_GRACE_MINUTES = Number(process.env.IDLE_GRACE_MINUTES || 5);

/* ── 인증 (Keycloak OIDC) ────────────────────────── */
// .oidc.env 는 register-kc-client.sh 가 생성 (issuer/client_id/client_secret).
// 환경변수가 우선. OIDC_ISSUER 미설정 시 인증 비활성(sim 로컬 개발용) — 전원 anonymous/admin.
const OIDC_ENV_FILE = path.join(ROOT, '.oidc.env');
if (fs.existsSync(OIDC_ENV_FILE)) {
  for (const line of fs.readFileSync(OIDC_ENV_FILE, 'utf8').split('\n')) {
    const m = line.match(/^(\w+)=(.*)$/);
    // 미정의일 때만 채움 — `OIDC_ISSUER= node server.js`처럼 빈 값으로 명시적으로 끌 수 있어야 한다
    if (m && !(m[1] in process.env)) process.env[m[1]] = m[2];
  }
}
const OIDC_ISSUER = process.env.OIDC_ISSUER || '';
const OIDC_CLIENT_ID = process.env.OIDC_CLIENT_ID || 'snacklab';
const OIDC_CLIENT_SECRET = process.env.OIDC_CLIENT_SECRET || '';
const PUBLIC_URL = (process.env.PUBLIC_URL || 'http://localhost:3000').replace(/\/$/, '');
const ADMIN_USERS = (process.env.ADMIN_USERS || 'admin').split(',').map(s => s.trim());
// 인증 모드: AUTH_MODE env로 강제(off|local|oidc), 미지정/auto면 자동 결정 —
// OIDC_ISSUER 설정 → oidc / 아니면 users.json 존재 → local(내장 로그인) / 둘 다 없으면 off
const USERS_FILE = process.env.USERS_FILE || path.join(ROOT, 'users.json');
// 시드: 읽기전용 소스(예: k8s Secret 마운트)에서 최초 1회 복사 — 이후는 USERS_FILE(쓰기 가능)이 원본.
// 가입/승인이 파일을 수정하므로 USERS_FILE은 쓰기 가능한 경로(PVC 등)여야 한다.
const USERS_SEED_FILE = process.env.USERS_SEED_FILE || '';
if (USERS_SEED_FILE && !fs.existsSync(USERS_FILE) && fs.existsSync(USERS_SEED_FILE)) {
  fs.mkdirSync(path.dirname(USERS_FILE), { recursive: true });
  fs.copyFileSync(USERS_SEED_FILE, USERS_FILE);
  console.log(`[auth] users 시드 복사: ${USERS_SEED_FILE} → ${USERS_FILE}`);
}
const AUTH_MODE = (() => {
  const m = (process.env.AUTH_MODE || 'auto').trim();
  if (m === 'auto' || m === '') return OIDC_ISSUER ? 'oidc' : (fs.existsSync(USERS_FILE) ? 'local' : 'off');
  if (!['off', 'local', 'oidc'].includes(m)) { console.error(`[auth] AUTH_MODE=${m} — off|local|oidc|auto 중 하나여야 합니다`); process.exit(1); }
  if (m === 'oidc' && !OIDC_ISSUER) { console.error('[auth] AUTH_MODE=oidc 인데 OIDC_ISSUER가 비어 있습니다'); process.exit(1); }
  if (m === 'local' && !fs.existsSync(USERS_FILE)) console.error(`[auth] 경고: AUTH_MODE=local 인데 ${USERS_FILE} 없음 — 계정을 만들 때까지 모든 로그인이 실패합니다 (userctl.js add)`);
  return m;
})();
console.log(`[auth] mode=${AUTH_MODE}`);
const AUTH_ON = AUTH_MODE !== 'off';
const AUTH_TTL_MS = Number(process.env.AUTH_TTL_HOURS || 12) * 3600_000;
// 쿠키 서명 키 — OIDC client secret과 분리된 전용 시크릿 (이 키를 알면 임의 사용자 쿠키 위조 가능).
// COOKIE_SECRET env 우선, 없으면 .cookie-secret 파일(첫 기동 시 자동 생성, mode 600)로 재기동 간 유지.
const COOKIE_SECRET_FILE = path.join(ROOT, '.cookie-secret');
let cookieSecret = process.env.COOKIE_SECRET || '';
if (!cookieSecret) {
  try { cookieSecret = fs.readFileSync(COOKIE_SECRET_FILE, 'utf8').trim(); } catch {}
  if (!cookieSecret) {
    cookieSecret = crypto.randomBytes(32).toString('hex');
    fs.writeFileSync(COOKIE_SECRET_FILE, cookieSecret + '\n', { mode: 0o600 });
    console.log('[auth] 쿠키 서명 시크릿 생성: .cookie-secret');
  }
}
const COOKIE_KEY = crypto.createHash('sha256').update('lab-cookie:' + cookieSecret).digest();

let oidc = null; // discovery 문서 (기동 시 로드, 실패하면 재시도)
async function discoverOIDC() {
  while (AUTH_MODE === 'oidc' && !oidc) {
    try {
      const r = await fetch(OIDC_ISSUER + '/.well-known/openid-configuration');
      if (r.ok) { oidc = await r.json(); console.log(`[auth] OIDC discovery 완료: ${oidc.issuer}`); return; }
    } catch {}
    console.error('[auth] OIDC discovery 실패 — 10초 후 재시도');
    await new Promise(r => setTimeout(r, 10_000));
  }
}
discoverOIDC();

const b64u = s => Buffer.from(s).toString('base64url');
function signToken(obj) {
  const p = b64u(JSON.stringify(obj));
  return p + '.' + crypto.createHmac('sha256', COOKIE_KEY).update(p).digest('base64url');
}
function verifyToken(tok) {
  const [p, mac] = String(tok || '').split('.');
  if (!p || !mac) return null;
  const want = crypto.createHmac('sha256', COOKIE_KEY).update(p).digest('base64url');
  if (mac.length !== want.length || !crypto.timingSafeEqual(Buffer.from(mac), Buffer.from(want))) return null;
  try {
    const obj = JSON.parse(Buffer.from(p, 'base64url').toString());
    return obj.exp > Date.now() ? obj : null;
  } catch { return null; }
}
function parseCookies(req) {
  const out = {};
  for (const kv of (req.headers.cookie || '').split(';')) {
    const i = kv.indexOf('=');
    if (i > 0) out[kv.slice(0, i).trim()] = decodeURIComponent(kv.slice(i + 1).trim());
  }
  return out;
}
// 요청의 인증 주체 (없으면 null). WS upgrade 요청에도 그대로 사용.
// admin = ADMIN_USERS 목록 또는 로그인 시점의 users.json admin 플래그(토큰 a=1)
function authOf(req) {
  if (!AUTH_ON) return { user: 'anonymous', name: 'anonymous', admin: true };
  const p = verifyToken(parseCookies(req).lab_auth);
  return p ? { user: p.u, name: p.n, admin: ADMIN_USERS.includes(p.u) || !!p.a } : null;
}

/* ── 내장 로그인 (local 모드: users.json + scrypt) ── */
// users.json 항목: { "user": "...", "name": "...", "admin": true?, "hash": "scrypt:<salt b64>:<hash b64>" }
// 계정 관리는 userctl.js (add/del/list). 파일은 요청 시마다 읽어 재기동 없이 반영.
function loadUsers() {
  try { return JSON.parse(fs.readFileSync(USERS_FILE, 'utf8')); } catch { return []; }
}
function verifyLocal(user, pass, cb) {
  const u = loadUsers().find(x => x.user === user);
  const [algo, saltB64, hashB64] = String(u && u.hash || '').split(':');
  if (algo !== 'scrypt' || !saltB64 || !hashB64) return cb(null);
  const want = Buffer.from(hashB64, 'base64');
  crypto.scrypt(pass, Buffer.from(saltB64, 'base64'), want.length, (err, got) =>
    cb(!err && crypto.timingSafeEqual(got, want) ? u : null));
}
const loginFails = new Map(); // ip → { n, until } — 5회 실패 시 60초 잠금

// 셀프 가입 + 관리자 승인: 가입 계정은 approved:false로 시작, 승인 전에는 랩 API 차단.
// 구계정(approved 필드 없음 — userctl.js/시드 출신)은 승인된 것으로 본다.
const SIGNUP_ENABLED = process.env.SIGNUP_ENABLED !== '0';
const approvedOf = u => !!u && u.approved !== false;
function pendingLocal(auth) {
  if (AUTH_MODE !== 'local' || !auth || auth.admin) return false;
  return !approvedOf(loadUsers().find(x => x.user === auth.user));
}
function writeUsers(users) {
  const tmp = USERS_FILE + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(users, null, 2) + '\n', { mode: 0o600 });
  fs.renameSync(tmp, USERS_FILE);
}
const signupHits = new Map(); // ip → { n, resetAt } — 10분당 5회

/* ── 로케일 ──────────────────────────────────────── */
// 콘텐츠 문자열(title/desc/steps[].title)은 평문(공용) 또는 { ko, en } 객체 — loc()이 해석.
// guide는 guide.<locale>.md → guide.en.md → guide.md 순으로 폴백(로케일 코드에 하이픈 허용: zh-CN).
const LOCALES = ['ko', 'en', 'ja', 'zh-CN', 'zh-TW', 'es', 'de'];
const DEFAULT_LOCALE = LOCALES.includes(process.env.DEFAULT_LOCALE) ? process.env.DEFAULT_LOCALE : 'ko';
// 브라우저 언어 태그 → 지원 로케일. 지역 코드까지 일치하면 그대로(zh-TW), 아니면 기본 변형으로
// (zh → zh-CN, zh-HK/zh-MO/Hant → zh-TW). public/i18n.js 의 matchLocale 과 같은 규칙.
function matchLocale(tag) {
  const s = String(tag || '').toLowerCase().replace('_', '-').split(';')[0].trim();
  if (!s) return null;
  for (const l of LOCALES) if (l.toLowerCase() === s) return l;
  const base = s.split('-')[0];
  if (base === 'zh') return (s === 'zh-tw' || s === 'zh-hk' || s === 'zh-mo' || s.includes('hant')) ? 'zh-TW' : 'zh-CN';
  for (const l of LOCALES) if (l.toLowerCase().split('-')[0] === base) return l;
  return null;
}
function localeOf(req) {
  const q = req.query && req.query.lang;
  if (LOCALES.includes(q)) return q;
  const c = parseCookies(req).lab_lang;
  if (LOCALES.includes(c)) return c;
  // Accept-Language: q 값 순서까지는 보지 않고 나열 순서대로 첫 매치
  for (const tag of String(req.headers['accept-language'] || '').split(',')) {
    const m = matchLocale(tag);
    if (m) return m;
  }
  return DEFAULT_LOCALE;
}
// 같은 언어의 다른 지역 변형 (zh-TW → zh-CN). 특정 언어로만 제공되는 과목(CKA 는 시험 자체가
// en/ja/zh 만 지원)에서 번체 사용자가 영어로 떨어지지 않도록 하는 중간 폴백이다.
const localeFamily = lang => LOCALES.filter(l => l !== lang && l.split('-')[0] === String(lang).split('-')[0]);
// 콘텐츠 문자열 폴백: 요청 로케일 → 같은 언어의 다른 변형 → en → 기본 로케일 → 아무 값.
// (en 을 기본 로케일보다 앞에 둔다 — 미번역 과목에서 한국어보다 영어가 실용적이고,
//  guide 파일 폴백 순서와도 맞는다.)
function loc(v, lang) {
  if (v == null || typeof v !== 'object') return v;
  if (v[lang] != null) return v[lang];
  for (const l of localeFamily(lang)) if (v[l] != null) return v[l];
  return v.en ?? v[DEFAULT_LOCALE] ?? v.ko ?? Object.values(v)[0];
}
// 사용자 대면 메시지 (서버 발신: API 에러, 터미널 경고) — 키 기반, 사전은 messages.js.
// 폴백: 요청 로케일 → en → ko → 키 이름. 값이 함수면 args 를 적용한다.
const { MESSAGES } = require('./messages');
function t(lang, key, ...args) {
  const v = (MESSAGES[lang] && MESSAGES[lang][key])
    ?? (MESSAGES.en && MESSAGES.en[key]) ?? (MESSAGES.ko && MESSAGES.ko[key]) ?? key;
  return typeof v === 'function' ? v(...args) : v;
}

/* ── 콘텐츠 카탈로그 ─────────────────────────────── */
// 콘텐츠 루트(콜론 구분, 기본 ./content). 루트 형식 두 가지:
//   ① catalog.json + 모듈 디렉터리들 (내장 형식)
//   ② course.json + modules/<id>/ (과목 번들 — docs/course-packaging-design.md)
// 루트에 둘 다 없으면 바로 아래 디렉터리들을 스캔 — 과목 마운트 지점(/courses)을 통째로 지정 가능.
// 주입 방식(내장/ConfigMap/콘텐츠 이미지 initContainer)은 포털 입장에선 전부 "디렉터리"로 동일.
const CONTENT_DIRS = (process.env.CONTENT_DIRS || CONTENT).split(':').filter(Boolean);
const catalog = [];           // [{id, no, track, trackTitle?, title?, desc?, ...}]
const labDirs = new Map();    // labId → 모듈 디렉터리
const labCourses = new Map(); // labId → course.json (자체 환경 이미지·리소스 선언 시)

// 모듈 번들 검증 — 어긋난 모듈은 카탈로그에서 제외하고 기동 로그로 보고
function moduleErrors(dir) {
  let meta;
  try { meta = JSON.parse(fs.readFileSync(path.join(dir, 'meta.json'), 'utf8')); }
  catch (e) { return [`meta.json 읽기 실패: ${e.message}`]; }
  const errs = [];
  const steps = Array.isArray(meta.steps) ? meta.steps : null;
  if (!steps || !steps.length) errs.push('meta.steps가 비어 있음');
  for (const [i, st] of (steps || []).entries())
    if (!st.check || !fs.existsSync(path.join(dir, 'checks', st.check)))
      errs.push(`step${i + 1} check 스크립트 없음: checks/${st.check}`);
  for (const g of fs.readdirSync(dir).filter(f => /^(guide|explain)(\.[\w-]+)?\.md$/.test(f))) {
    const n = (fs.readFileSync(path.join(dir, g), 'utf8').match(/^## /gm) || []).length;
    if (steps && n !== steps.length) errs.push(`${g} '## ' 섹션 수(${n}) ≠ steps 수(${steps.length})`);
  }
  // 시험형 랩(meta.exam)은 문항 배점이 있어야 채점 결과를 합산할 수 있다
  if (meta.exam) for (const [i, st] of (steps || []).entries())
    if (!(Number(st.points) > 0)) errs.push(`step${i + 1} points 없음 (시험형 랩은 배점 필수)`);
  return errs;
}

function addModule(id, dir, entry, course) {
  const errs = labDirs.has(id) ? ['모듈 id 중복 — 뒤 항목 무시'] : moduleErrors(dir);
  if (errs.length) return console.error(`[content] ${id} 제외 (${dir}): ${errs.join(' / ')}`);
  labDirs.set(id, dir);
  if (course) labCourses.set(id, course);
  catalog.push(entry);
}

function loadContentRoot(root, depth = 0) {
  const courseFile = path.join(root, 'course.json');
  const catFile = path.join(root, 'catalog.json');
  try {
    if (fs.existsSync(courseFile)) {
      const c = JSON.parse(fs.readFileSync(courseFile, 'utf8'));
      (c.modules || []).forEach((m, i) => addModule(m, path.join(root, 'modules', m),
        { id: m, no: i + 1, track: c.id, trackTitle: c.title, trackDesc: c.desc }, c));
    } else if (fs.existsSync(catFile)) {
      for (const e of JSON.parse(fs.readFileSync(catFile, 'utf8'))) addModule(e.id, path.join(root, e.id), e);
    } else if (depth === 0 && fs.existsSync(root)) {
      for (const d of fs.readdirSync(root, { withFileTypes: true }))
        if (d.isDirectory()) loadContentRoot(path.join(root, d.name), 1);
    } else if (depth === 0) console.error(`[content] 루트 없음: ${root}`);
  } catch (e) { console.error(`[content] ${root} 로드 실패: ${e.message}`); }
}
for (const r of CONTENT_DIRS) loadContentRoot(r);
console.log(`[content] 모듈 ${catalog.length}개 로드 (roots: ${CONTENT_DIRS.join(', ')})`);

const labPath = (labId, ...p) => path.join(labDirs.get(labId) || path.join(CONTENT, labId), ...p);
function labMeta(labId) {
  const p = labPath(labId, 'meta.json');
  return fs.existsSync(p) ? JSON.parse(fs.readFileSync(p, 'utf8')) : null;
}
function labAvailable(meta) {
  if (!meta || !meta.available) return false;
  const d = meta.driver || 'sim';
  // The docker driver provides the same learner environment contract as pod
  // (privileged systemd container, checks via `su - learner`), so pod content runs as-is.
  return d === DRIVER || (DRIVER === 'docker' && d === 'pod');
}

/* ── 체크 메시지 다국어 ──────────────────────────
 * 체크 스크립트는 학습자 환경(파드) 안에서 돌기 때문에 포털의 로케일 사전을 볼 수 없다. 그래서
 * 스크립트는 **키와 인자만** 내보내고(아래 labmsg), 포털이 모듈의 checks/messages.json 을 보고
 * 세션 로케일로 렌더링한다. 스크립트에 번역문을 넣지 않으므로 언어 추가 = JSON 에 블록 추가.
 *   스크립트:  labmsg web_missing "$name" ; exit 1
 *   출력:      \x01labmsg\x01web_missing\x01<arg1>…
 *   messages.json: { "web_missing": { "ko": "FAIL: … {0} …", "en": …, "ja": … } }
 * 키를 못 찾거나 아직 변환하지 않은 모듈이면 원문 줄을 그대로 통과시킨다(하위 호환). */
const MSG_SEP = '\x01';
// 부분점수(시험형 랩): 채점 항목 하나마다 획득/배점과 메시지 키를 내보낸다. labmsg 와 같은 규약이며
// 앞에 점수 두 칸이 더 붙는다.  스크립트:  part 2 3 q1c2 "$img"
//                              출력:      \x01labpart\x012\x013\x01q1c2\x01<arg1>…
// part 줄이 하나도 없으면 종료코드로 통과/실패를 가리는 기존 방식 그대로다(하위 호환).
const CHECK_PREAMBLE =
  `labmsg() { printf '${MSG_SEP}labmsg'; for __a in "$@"; do printf '${MSG_SEP}%s' "$__a"; done; printf '\\n'; }\n` +
  `part() { printf '${MSG_SEP}labpart${MSG_SEP}%s${MSG_SEP}%s' "$1" "$2"; shift 2; ` +
  `for __a in "$@"; do printf '${MSG_SEP}%s' "$__a"; done; printf '\\n'; }\n`;
const checkMsgCache = new Map(); // labId → {catalog} | null
function checkMessages(labId) {
  if (!checkMsgCache.has(labId)) {
    const p = labPath(labId, 'checks', 'messages.json');
    let v = null;
    try { if (fs.existsSync(p)) v = JSON.parse(fs.readFileSync(p, 'utf8')); }
    catch (e) { console.error(`[content] ${labId} checks/messages.json 파싱 실패:`, e.message); }
    checkMsgCache.set(labId, v);
  }
  return checkMsgCache.get(labId);
}
function renderMsg(cat, key, args, lang) {
  const tpl = cat[key] && loc(cat[key], lang);
  if (!tpl) return key || '';                                  // 사전에 없으면 키라도 보여준다
  return tpl.replace(/\{(\d+)\}/g, (m, n) => args[Number(n)] ?? m);
}
function renderCheckOutput(out, labId, lang) {
  if (!out || out.indexOf(MSG_SEP) === -1) return out;
  const cat = checkMessages(labId) || {};
  return out.split('\n').map(line => {
    const i = line.indexOf(MSG_SEP + 'labmsg' + MSG_SEP);
    if (i === -1) return line.includes(MSG_SEP) ? line.split(MSG_SEP)[0] : line;
    const [key, ...args] = line.slice(i + 8).split(MSG_SEP);
    return line.slice(0, i) + renderMsg(cat, key, args, lang);
  }).join('\n');
}
// 부분점수 채점 결과 파싱 — part 줄을 항목 목록으로 걷어내고, 나머지 줄은 기존대로 렌더링한다.
// part 줄이 없으면 parts=[] 로 돌려주므로 호출부가 종료코드 기준으로 판정하면 된다.
function parseCheckResult(raw, labId, lang) {
  const cat = checkMessages(labId) || {};
  const parts = [], rest = [];
  for (const line of String(raw || '').split('\n')) {
    const i = line.indexOf(MSG_SEP + 'labpart' + MSG_SEP);
    if (i === -1) { rest.push(line); continue; }
    const [earned, max, key, ...args] = line.slice(i + 9).split(MSG_SEP);
    parts.push({
      earned: Math.max(0, Number(earned) || 0),
      max: Math.max(0, Number(max) || 0),
      text: renderMsg(cat, key, args, lang),
    });
  }
  return {
    parts,
    earned: parts.reduce((a, p) => a + p.earned, 0),
    max: parts.reduce((a, p) => a + p.max, 0),
    output: renderCheckOutput(rest.join('\n'), labId, lang).trim(),
  };
}

/* ── 진행상황·뱃지 ──────────────────────────────── */
// 사용자별 스텝 통과·모듈 이수 기록 — progress.json에 영속 (세션 회수·서버 재기동과 무관하게 유지).
// 뱃지는 저장하지 않고 진행상황에서 파생: 모듈 이수 뱃지 + 트랙(과목) 전 모듈 완주 특별 뱃지.
const PROGRESS_FILE = process.env.PROGRESS_FILE || path.join(ROOT, 'progress.json');
let progress = {};
try { progress = JSON.parse(fs.readFileSync(PROGRESS_FILE, 'utf8')); } catch {}
function saveProgress() {
  const tmp = PROGRESS_FILE + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(progress, null, 2));
  fs.renameSync(tmp, PROGRESS_FILE);
}
const trackOf = labId => (catalog.find(c => c.id === labId) || {}).track;

// 모듈 이수 확정(뱃지 발급) + 트랙 완주 판정 — 저장은 호출부에서 한 번만 한다.
function markLabCompleted(u, user, labId) {
  const lab = u.labs[labId];
  if (lab.completedAt) return { labCompleted: false, trackCompleted: false };
  lab.completedAt = Date.now();
  console.log(`[badge] ${user} 모듈 이수: ${labId}`);
  let trackCompleted = false;
  const track = trackOf(labId);
  const mods = catalog.filter(c => c.track === track);
  u.tracks = u.tracks || {};
  if (track && !u.tracks[track] && mods.length && mods.every(c => (u.labs[c.id] || {}).completedAt)) {
    u.tracks[track] = Date.now();
    trackCompleted = true;
    console.log(`[badge] 🏆 ${user} 트랙 완주: ${track} (${mods.length}개 모듈)`);
  }
  return { labCompleted: true, trackCompleted };
}

// 스텝 통과 기록 → { labCompleted, trackCompleted } ("이번에 새로" 달성한 것만 true)
function recordStepPass(user, labId, step, meta) {
  const u = progress[user] = progress[user] || { labs: {}, tracks: {} };
  const lab = u.labs[labId] = u.labs[labId] || { steps: {} };
  lab.steps[step] = lab.steps[step] || Date.now();
  const steps = meta.steps || [];
  const done = steps.length && steps.every((_, i) => lab.steps[i]);
  const earned = done ? markLabCompleted(u, user, labId) : { labCompleted: false, trackCompleted: false };
  saveProgress();
  return earned;
}

// 시험형 랩 제출 기록 → 기준 점수를 넘겼으면 모듈 이수(뱃지). 전 문항 만점이 아니어도 이수다.
// 최고 점수만 갱신하고, 만점 문항은 스텝 통과로도 남겨 진행도 표시에 쓴다.
function recordExamResult(user, labId, results, total, max, passed) {
  const u = progress[user] = progress[user] || { labs: {}, tracks: {} };
  const lab = u.labs[labId] = u.labs[labId] || { steps: {} };
  const now = Date.now();
  for (const r of results) if (r.max > 0 && r.earned >= r.max) lab.steps[r.step] = lab.steps[r.step] || now;
  const prev = lab.exam || { attempts: 0, best: 0 };
  lab.exam = {
    attempts: prev.attempts + 1,
    best: Math.max(prev.best || 0, total),
    max, last: total, lastAt: now,
    passed: !!(prev.passed || passed),
  };
  const earned = passed ? markLabCompleted(u, user, labId) : { labCompleted: false, trackCompleted: false };
  saveProgress();
  return earned;
}

function badgesOf(user, lang) {
  const u = progress[user];
  if (!u) return [];
  const out = [];
  for (const c of catalog) {
    const lab = u.labs[c.id];
    if (lab && lab.completedAt) out.push({
      type: 'module', labId: c.id, no: c.no, track: c.track,
      title: loc(c.title ?? (labMeta(c.id) || {}).title, lang), earnedAt: lab.completedAt,
    });
  }
  for (const [track, at] of Object.entries(u.tracks || {})) {
    const mods = catalog.filter(c => c.track === track);
    out.push({
      type: 'track', track, total: mods.length,
      trackTitle: loc((mods[0] || {}).trackTitle, lang) || track, earnedAt: at,
    });
  }
  return out;
}

function progressView(user, lang) {
  const u = progress[user] || { labs: {}, tracks: {} };
  const labs = {};
  for (const c of catalog) {
    const lab = u.labs[c.id];
    if (!lab) continue;
    const stepTimes = Object.values(lab.steps || {});
    labs[c.id] = {
      passed: stepTimes.length,
      total: ((labMeta(c.id) || {}).steps || []).length,
      completedAt: lab.completedAt || null,
      lastAt: stepTimes.length ? Math.max(...stepTimes) : (lab.exam || {}).lastAt || null,
      exam: lab.exam || null,
    };
  }
  return { labs, tracks: u.tracks || {}, badges: badgesOf(user, lang) };
}

function kubectl(args, opts = {}) {
  return new Promise(resolve => {
    execFile('kubectl', args, { timeout: 20_000, ...opts }, (err, stdout, stderr) =>
      resolve({ ok: !err, stdout: stdout || '', stderr: stderr || '' }));
  });
}

function docker(args, opts = {}) {
  return new Promise(resolve => {
    execFile('docker', args, { timeout: 60_000, ...opts }, (err, stdout, stderr) =>
      resolve({ ok: !err, stdout: stdout || '', stderr: stderr || '' }));
  });
}

/* ── 드라이버 ────────────────────────────────────── */
// 각 드라이버는 alloc()으로 세션 환경을 내주고, 웜풀을 스스로 관리한다.
//   sim      웜풀 = 미리 만든 세션 디렉터리
//   kubevirt 웜풀 = 미리 클론해 둔 골든 디스크(DataVolume) — VM은 세션 시작 시 생성 (유휴 CPU/RAM 0)
const drivers = {
  /* 로컬 시뮬레이션: 세션 = 디렉터리, 터미널 = bash, 체크 = 로컬 실행 */
  sim: {
    warmMs: 1200, coldMs: 6000,
    pool: [],
    init() { this.refill(); },
    refill() { while (this.pool.length < warmTarget()) this.pool.push(this.newEnv()); },
    warmCount() { return this.pool.length; },
    alloc() {
      const warm = this.pool.length > 0;
      const env = warm ? this.pool.shift() : this.newEnv();
      if (warm) setTimeout(() => this.refill(), 3000);
      return { ...env, warm };
    },
    newEnv() {
      const id = crypto.randomBytes(4).toString('hex');
      const dir = path.join(SESSIONS_DIR, id);
      fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(path.join(dir, 'state.json'), JSON.stringify({ vms: {} }));
      fs.writeFileSync(path.join(dir, '.bashrc'), [
        `export PATH="${SIMBIN}:$PATH"`,
        'export LAB_STATE="$HOME/state.json"',
        'export TERM=xterm-256color',
        "export PS1='\\[\\e[38;5;42m\\]learner@lab\\[\\e[0m\\]:\\[\\e[38;5;110m\\]\\w\\[\\e[0m\\]\\$ '",
        'cd "$HOME"',
      ].join('\n') + '\n');
      return { id, dir };
    },
    prepare(s, labId) {
      const src = labPath(labId, 'manifests');
      if (fs.existsSync(src)) {
        const dst = path.join(s.dir, 'manifests');
        fs.mkdirSync(dst, { recursive: true });
        for (const f of fs.readdirSync(src)) fs.copyFileSync(path.join(src, f), path.join(dst, f));
      }
      const ip = labPath(labId, 'init-state.json');
      if (fs.existsSync(ip)) {
        const init = JSON.parse(fs.readFileSync(ip, 'utf8'));
        const past = Date.now() - 600_000;
        for (const k of ['operatorAt', 'crAt']) if (init[k] === true) init[k] = past;
        init.vms = init.vms || {};
        fs.writeFileSync(path.join(s.dir, 'state.json'), JSON.stringify(init, null, 2));
      }
    },
    async checkReady(s) { return Date.now() >= s.readyAt; },
    envOf(s) {
      return { ...process.env, HOME: s.dir, LAB_STATE: path.join(s.dir, 'state.json'), PATH: `${SIMBIN}:${process.env.PATH}` };
    },
    spawnTerminal(s) {
      return spawn('python3', [path.join(ROOT, 'ptybridge.py'), 'bash'],
        { cwd: s.dir, stdio: ['pipe', 'pipe', 'pipe', 'pipe'], env: this.envOf(s) });
    },
    // 다른 드라이버와 같이 프리앰블(labmsg/part)을 앞에 붙여 stdin 으로 넘긴다 —
    // 파일을 직접 실행하면 헬퍼가 없어 메시지·부분점수가 그대로 새어 나온다.
    runCheck(s, script, cb, timeoutMs = 15_000) {
      const child = spawn('bash', ['-s'], { cwd: s.dir, env: this.envOf(s), stdio: ['pipe', 'pipe', 'pipe'] });
      let out = '';
      child.stdout.on('data', d => out += d);
      child.stderr.on('data', d => out += d);
      const t = setTimeout(() => child.kill('SIGKILL'), timeoutMs);
      child.on('exit', code => { clearTimeout(t); cb(code === 0, out.trim()); });
      child.stdin.end(CHECK_PREAMBLE + fs.readFileSync(script));
    },
    async reap(s) { try { fs.rmSync(s.dir, { recursive: true, force: true }); } catch {} },
  },

  /* 실제 KubeVirt: 세션 = VM, 터미널 = virtctl console, 체크 = checker pod 경유 SSH */
  kubevirt: {
    warmMs: 0, coldMs: 0,
    template: null, diskTemplate: null,
    warmReady: [],        // Succeeded 상태 웜 디스크 이름 (poller가 갱신)
    consumed: new Set(),  // 세션에 할당된 웜 디스크 — 라벨 전환이 반영될 때까지 poll 결과에서 제외
    warmVMsReady: [],     // 부팅+SSH 응답까지 확인된 웜 VM 이름 (poller가 갱신)
    vmConsumed: new Set(),
    init() {
      this.maintainWarmDisks();
      this.maintainWarmVMs();
      setInterval(() => this.maintainWarmDisks(), 20_000);
      setInterval(() => this.maintainWarmVMs(), 25_000);
    },
    applyYaml(yaml) {
      const child = spawn('kubectl', ['apply', '-f', '-'], { stdio: ['pipe', 'ignore', 'inherit'] });
      child.stdin.end(yaml.replace(/__NS__/g, NS));
    },
    // 웜 디스크 풀 유지: 진행 중 포함 총량이 WARM_POOL_SIZE가 되도록 클론 생성, 준비된 목록 캐시
    async maintainWarmDisks() {
      const r = await kubectl(['get', 'dv', '-n', NS, '-l', 'snacklab/kind=warm-disk', '-o', 'json']);
      if (!r.ok) return;
      let items;
      try { items = JSON.parse(r.stdout).items; } catch { return; }
      for (const name of [...this.consumed]) {
        if (!items.some(d => d.metadata.name === name)) this.consumed.delete(name); // 라벨 전환 반영됨
      }
      const live = items.filter(d => !this.consumed.has(d.metadata.name));
      this.warmReady = live.filter(d => (d.status || {}).phase === 'Succeeded').map(d => d.metadata.name);
      this.diskTemplate = this.diskTemplate || fs.readFileSync(DISK_TEMPLATE, 'utf8');
      for (let i = live.length; i < WARM_POOL_SIZE; i++) {
        const name = 'warm-' + crypto.randomBytes(4).toString('hex');
        this.applyYaml(this.diskTemplate.replace(/__NAME__/g, name).replace(/__KIND__/g, 'warm-disk'));
        console.log(`[warmpool] 웜 디스크 클론 시작: ${name}`);
      }
    },
    // 웜 VM 풀 유지: 웜 디스크로 VM을 미리 부팅해 두고 SSH 응답까지 확인된 것만 할당 대상에 올린다
    async maintainWarmVMs() {
      if (this._vmMaint) return; // SSH probe가 겹치지 않게
      this._vmMaint = true;
      try {
        const r = await kubectl(['get', 'vm', '-n', NS, '-l', 'snacklab/kind=warm-vm', '-o', 'json']);
        if (!r.ok) return;
        let items;
        try { items = JSON.parse(r.stdout).items; } catch { return; }
        for (const name of [...this.vmConsumed]) {
          if (!items.some(v => v.metadata.name === name)) this.vmConsumed.delete(name);
        }
        const live = items.filter(v => !this.vmConsumed.has(v.metadata.name));
        const ready = [];
        for (const v of live) {
          const ip = await this.vmiIP(v.metadata.name);
          if (ip && await this.probeSSH(ip)) ready.push(v.metadata.name);
        }
        this.warmVMsReady = ready;
        this.template = this.template || fs.readFileSync(VM_TEMPLATE, 'utf8');
        this.diskTemplate = this.diskTemplate || fs.readFileSync(DISK_TEMPLATE, 'utf8');
        for (let i = live.length; i < WARM_VM_POOL; i++) {
          let disk = this.warmReady.shift(); // 준비된 웜 디스크 우선, 없으면 새 클론
          if (disk) this.consumed.add(disk);
          else {
            disk = 'warm-' + crypto.randomBytes(4).toString('hex');
            this.applyYaml(this.diskTemplate.replace(/__NAME__/g, disk).replace(/__KIND__/g, 'warmvm-disk'));
          }
          kubectl(['label', 'dv', disk, '-n', NS, 'snacklab/kind=warmvm-disk', '--overwrite']);
          const vm = 'warmvm-' + disk.replace(/^warm-/, '');
          this.applyYaml(this.template.replace(/__NAME__/g, vm).replace(/__DISK__/g, disk).replace(/__KIND__/g, 'warm-vm'));
          console.log(`[warmpool] 웜 VM 부팅 시작: ${vm} (disk=${disk})`);
        }
      } finally { this._vmMaint = false; }
    },
    async vmiIP(name) {
      const r = await kubectl(['get', 'vmi', name, '-n', NS, '-o', 'jsonpath={.status.phase} {.status.interfaces[0].ipAddress}']);
      if (!r.ok) return null;
      const [phase, ip] = r.stdout.trim().split(/\s+/);
      return phase === 'Running' && ip ? ip : null;
    },
    probeSSH(ip) {
      const ssh = `ssh -i /keys/id -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=4 learner@${ip} true`;
      return new Promise(res =>
        execFile('kubectl', ['exec', '-n', NS, 'deploy/checker', '--', 'sh', '-c', ssh],
          { timeout: 15_000 }, err => res(!err)));
    },
    warmCount() { return this.warmVMsReady.length + this.warmReady.length; },
    alloc() {
      const id = 'lab-' + crypto.randomBytes(4).toString('hex');
      this.template = this.template || fs.readFileSync(VM_TEMPLATE, 'utf8');
      this.diskTemplate = this.diskTemplate || fs.readFileSync(DISK_TEMPLATE, 'utf8');
      // 1순위: 부팅 완료 웜 VM — 라벨 전환으로 세션에 귀속, 수 초 내 Running
      const wvm = this.warmVMsReady.shift();
      if (wvm) {
        this.vmConsumed.add(wvm);
        const disk = wvm.replace(/^warmvm-/, 'warm-');
        kubectl(['label', 'vm', wvm, '-n', NS, 'snacklab/kind=learner-vm', '--overwrite']);
        kubectl(['label', 'dv', disk, '-n', NS, 'snacklab/kind=learner-disk', '--overwrite']);
        setTimeout(() => this.maintainWarmVMs(), 3000);
        return { id, vmName: wvm, diskName: disk, warm: true };
      }
      // 2순위: 웜 디스크로 새 VM 부팅 / 3순위: 콜드 클론
      let disk = this.warmReady.shift();
      const warm = !!disk;
      if (warm) {
        this.consumed.add(disk);
        kubectl(['label', 'dv', disk, '-n', NS, 'snacklab/kind=learner-disk', '--overwrite']);
      } else {
        disk = id + '-disk';
        this.applyYaml(this.diskTemplate.replace(/__NAME__/g, disk).replace(/__KIND__/g, 'learner-disk'));
      }
      this.applyYaml(this.template.replace(/__NAME__/g, id).replace(/__DISK__/g, disk).replace(/__KIND__/g, 'learner-vm'));
      return { id, vmName: id, diskName: disk, warm };
    },
    prepare() {},
    // 준비 = VMI Running → SSH 응답 → (있다면) 모듈 bootstrap 완료
    async checkReady(s) {
      if (!s.vmIP) {
        const r = await kubectl(['get', 'vmi', s.vmName, '-n', NS, '-o', 'jsonpath={.status.phase} {.status.interfaces[0].ipAddress}']);
        if (!r.ok) return false;
        const [phase, ip] = r.stdout.trim().split(/\s+/);
        if (!(phase === 'Running' && ip)) return false;
        s.vmIP = ip;
      }
      if (!s.sshOk) {
        const ok = await new Promise(res => this.execInVM(s, 'true', out => res(out !== null)));
        if (!ok) return false;
        s.sshOk = true;
      }
      const bs = labPath(s.labId, 'bootstrap.sh');
      if (fs.existsSync(bs) && !s.bootstrapDone) {
        if (!s.bootstrapping) {
          s.bootstrapping = true;
          this.runCheck(s, bs, (pass, out) => {
            s.bootstrapping = false;
            s.bootstrapDone = pass;
            if (!pass) console.error(`[bootstrap] ${s.id} 실패:`, out.slice(-300));
          }, 420_000);
        }
        return false;
      }
      return true;
    },
    // VM 안에서 단일 명령 실행 (성공 시 출력, 실패 시 null)
    execInVM(s, cmd, cb) {
      const ssh = `ssh -i /keys/id -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=4 learner@${s.vmIP} ${JSON.stringify(cmd)}`;
      execFile('kubectl', ['exec', '-n', NS, 'deploy/checker', '--', 'sh', '-c', ssh],
        { timeout: 15_000 }, (err, stdout) => cb(err ? null : stdout));
    },
    spawnTerminal(s) {
      return spawn('python3', [path.join(ROOT, 'ptybridge.py'), 'virtctl', 'console', s.vmName, '-n', NS],
        { stdio: ['pipe', 'pipe', 'pipe', 'pipe'], env: process.env });
    },
    runCheck(s, script, cb, timeoutMs = 20_000) {
      if (!s.vmIP) return cb(false, '학습자 VM IP를 아직 알 수 없습니다.');
      const ssh = `ssh -i /keys/id -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5 learner@${s.vmIP} bash -s`;
      const child = spawn('kubectl', ['exec', '-i', '-n', NS, 'deploy/checker', '--', 'sh', '-c', ssh],
        { stdio: ['pipe', 'pipe', 'pipe'] });
      let out = '';
      child.stdout.on('data', d => out += d);
      child.stderr.on('data', d => out += d);
      const t = setTimeout(() => child.kill('SIGKILL'), timeoutMs);
      child.on('exit', code => { clearTimeout(t); cb(code === 0, out.trim()); });
      child.stdin.end(CHECK_PREAMBLE + fs.readFileSync(script));
    },
    async reap(s) {
      await kubectl(['delete', 'vm', s.vmName, '-n', NS, '--wait=false']);
      if (s.diskName) await kubectl(['delete', 'dv', s.diskName, '-n', NS, '--wait=false']);
    },
  },

  /* 리눅스 랩: 세션 = systemd pod, 터미널 = kubectl exec + su - learner, 체크 = kubectl exec bash -s
   * 웜풀 = 미리 Ready까지 띄워 둔 pod — 이미지가 캐시된 노드면 콜드도 ~10초라 풀은 얇게 유지 */
  pod: {
    warmMs: 0, coldMs: 0,
    template: null,
    warmReady: [],       // Ready 상태 웜 pod 이름 (poller가 갱신)
    consumed: new Set(), // 세션에 할당된 웜 pod — 라벨 전환 반영까지 poll 결과에서 제외
    init() {
      this.maintain();
      setInterval(() => this.maintain(), 15_000);
    },
    applyYaml(yaml) {
      const child = spawn('kubectl', ['apply', '-f', '-'], { stdio: ['pipe', 'ignore', 'inherit'] });
      child.stdin.end(yaml.replace(/__NS__/g, NS));
    },
    newPod(name, kind, course) {
      this.template = this.template || fs.readFileSync(POD_TEMPLATE, 'utf8');
      // 과목별 환경은 화이트리스트 키만 치환(image + resources 4값) — 임의 spec 병합 금지 (신뢰 경계)
      const r = (course && course.resources) || {};
      // hostModules 는 불리언 플래그일 뿐 — 붙는 마운트는 아래 고정 스니펫(호스트 /lib/modules ro).
      // 파드 안 k3s(kube-router)가 ip_tables·br_netfilter 를 modprobe 해야 기동된다.
      const hostMods = !!(course && course.hostModules);
      const extraMounts = hostMods
        ? '        - { name: host-modules, mountPath: /lib/modules, readOnly: true }' : '';
      const extraVolumes = hostMods
        ? '    - { name: host-modules, hostPath: { path: /lib/modules, type: Directory } }' : '';
      // clusterInit is a boolean flag like hostModules — it only picks the value of a
      // fixed env var in the template; lab-init switches k3s to embedded etcd on "true".
      this.applyYaml(this.template
        .replace(/__NAME__/g, name).replace(/__KIND__/g, kind)
        .replace(/__EXTRA_MOUNTS__/g, extraMounts)
        .replace(/__EXTRA_VOLUMES__/g, extraVolumes)
        .replace(/__CLUSTER_INIT__/g, (course && course.clusterInit) ? 'true' : 'false')
        .replace(/__IMAGE__/g, resolveImage(course && course.image) || LEARNER_IMAGE)
        .replace(/__CPU_REQ__/g, (r.requests || {}).cpu || LEARNER_RES.reqCpu)
        .replace(/__MEM_REQ__/g, (r.requests || {}).memory || LEARNER_RES.reqMem)
        .replace(/__EPH_REQ__/g, (r.requests || {})['ephemeral-storage'] || LEARNER_RES.reqEph)
        .replace(/__CPU_LIM__/g, (r.limits || {}).cpu || LEARNER_RES.limCpu)
        .replace(/__MEM_LIM__/g, (r.limits || {}).memory || LEARNER_RES.limMem)
        .replace(/__EPH_LIM__/g, (r.limits || {})['ephemeral-storage'] || LEARNER_RES.limEph));
    },
    async maintain() {
      const r = await kubectl(['get', 'pods', '-n', NS, '-l', 'snacklab/kind=warm-pod', '-o', 'json']);
      if (!r.ok) return;
      let items;
      try { items = JSON.parse(r.stdout).items; } catch { return; }
      for (const name of [...this.consumed]) {
        if (!items.some(p => p.metadata.name === name)) this.consumed.delete(name); // 라벨 전환 반영됨
      }
      let live = items.filter(p => !this.consumed.has(p.metadata.name) && !p.metadata.deletionTimestamp);
      // 이미지 업그레이드 대응: 웜풀은 항상 기본 LEARNER_IMAGE 로만 생성되므로, 현재 LEARNER_IMAGE 와
      // 다른 이미지로 뜬 웜 pod = 구버전. 학습자에게 배정되지 않도록 폐기하고 target 재충전에서 제외한다.
      const stale = live.filter(p => ((p.spec.containers || [])[0] || {}).image !== LEARNER_IMAGE);
      for (const p of stale) {
        kubectl(['delete', 'pod', p.metadata.name, '-n', NS, '--wait=false']);
        console.log(`[warmpool] 구 이미지 웜 pod 폐기: ${p.metadata.name} (${((p.spec.containers||[])[0]||{}).image} ≠ ${LEARNER_IMAGE})`);
      }
      if (stale.length) live = live.filter(p => !stale.includes(p));
      this.warmReady = live
        .filter(p => (p.status.conditions || []).some(c => c.type === 'Ready' && c.status === 'True'))
        .map(p => p.metadata.name);
      const target = warmTarget();
      for (let i = live.length; i < target; i++) {
        const name = 'warmpod-' + crypto.randomBytes(4).toString('hex');
        this.newPod(name, 'warm-pod');
        console.log(`[warmpool] 웜 pod 기동 시작: ${name}`);
      }
      // 수요가 줄면 Ready 웜부터 회수 (기동 중인 것은 Ready 후 다음 틱에 회수)
      let excess = live.length - target;
      while (excess-- > 0 && this.warmReady.length) {
        const name = this.warmReady.pop();
        kubectl(['delete', 'pod', name, '-n', NS, '--wait=false']);
        console.log(`[warmpool] 웜 pod 축소 회수: ${name}`);
      }
    },
    warmCount() { return this.warmReady.length; },
    alloc(course) {
      const id = 'lab-' + crypto.randomBytes(4).toString('hex');
      // 웜풀은 기본 환경으로만 유지 — 자체 image/resources를 선언한 과목은 콜드 부팅
      // (clusterInit too: a warm pod already booted k3s on sqlite, so it can never serve
      //  an etcd-datastore course — force a cold boot with the right env.)
      const custom = !!(course && (course.image || course.resources || course.clusterInit));
      const wp = custom ? null : this.warmReady.shift();
      if (wp) {
        this.consumed.add(wp);
        kubectl(['label', 'pod', wp, '-n', NS, 'snacklab/kind=learner-pod', '--overwrite']);
        setTimeout(() => this.maintain(), 3000);
        return { id, vmName: wp, warm: true }; // vmName = 환경 이름 (admin UI 호환)
      }
      this.newPod(id, 'learner-pod', course);
      return { id, vmName: id, warm: false };
    },
    prepare() {},
    // 준비 = pod Ready(systemd 부팅 완료) → (있다면) 모듈 bootstrap 완료
    async checkReady(s) {
      if (!s.podReady) {
        const r = await kubectl(['get', 'pod', s.vmName, '-n', NS, '-o',
          'jsonpath={.status.conditions[?(@.type=="Ready")].status}']);
        if (!(r.ok && r.stdout.trim() === 'True')) return false;
        s.podReady = true;
      }
      const bs = labPath(s.labId, 'bootstrap.sh');
      if (fs.existsSync(bs) && !s.bootstrapDone) {
        if (!s.bootstrapping) {
          s.bootstrapping = true;
          this.runCheck(s, bs, (pass, out) => {
            s.bootstrapping = false;
            s.bootstrapDone = pass;
            if (!pass) console.error(`[bootstrap] ${s.id} 실패:`, out.slice(-300));
          }, 180_000);
        }
        return false;
      }
      return true;
    },
    spawnTerminal(s) {
      return spawn('python3', [path.join(ROOT, 'ptybridge.py'),
        'kubectl', 'exec', '-it', '-n', NS, s.vmName, '--', 'su', '-', 'learner'],
        { stdio: ['pipe', 'pipe', 'pipe', 'pipe'], env: process.env });
    },
    // 스크립트를 pod 안에서 learner로 실행 (learner는 NOPASSWD sudo 보유)
    runCheck(s, script, cb, timeoutMs = 20_000) {
      const child = spawn('kubectl',
        ['exec', '-i', '-n', NS, s.vmName, '--', 'su', '-', 'learner', '-c', 'bash -s'],
        { stdio: ['pipe', 'pipe', 'pipe'] });
      let out = '';
      child.stdout.on('data', d => out += d);
      child.stderr.on('data', d => out += d);
      const t = setTimeout(() => child.kill('SIGKILL'), timeoutMs);
      child.on('exit', code => { clearTimeout(t); cb(code === 0, out.trim()); });
      child.stdin.end(CHECK_PREAMBLE + fs.readFileSync(script));
    },
    async reap(s) {
      await kubectl(['delete', 'pod', s.vmName, '-n', NS, '--wait=false']);
    },
  },

  /* Docker (compose) driver: session = privileged systemd container on the local docker
   * daemon (the portal mounts /var/run/docker.sock and spawns sibling containers).
   * Same learner-environment contract as the pod driver — identical images, warm pool,
   * checks via `su - learner` — so all `driver: "pod"` content runs unchanged.
   * Naming is the identity mechanism (docker labels are immutable): warmpod-* = warm,
   * lab-* = bound to a session; a warm claim is just `docker rename`. */
  docker: {
    warmMs: 0, coldMs: 0,
    warmReady: [],       // names of warm containers that passed the systemd readiness probe
    init() {
      this.maintain();
      setInterval(() => this.maintain(), 15_000);
    },
    // k8s resource quantities → docker flags ('4Gi'→'4g', '256Mi'→'256m', '250m' cpu→'0.25')
    memFlag(q) { return String(q).replace(/Gi$/, 'g').replace(/Mi$/, 'm'); },
    cpuFlag(q) { q = String(q); return q.endsWith('m') ? String(Number(q.slice(0, -1)) / 1000) : q; },
    newContainer(name, kind, course) {
      // Whitelisted per-course keys only, mirroring the pod template substitutions
      // (image + resource limits + hostModules/clusterInit flags) — no arbitrary spec merge.
      const lim = ((course && course.resources) || {}).limits || {};
      const args = ['run', '-d', '--name', name, '--hostname', 'lab',
        '--label', `snacklab.kind=${kind}`,
        '--privileged', '--stop-timeout', '5',
        '--tmpfs', '/run', '--tmpfs', '/run/lock', '--tmpfs', '/tmp',
        '--cpus', this.cpuFlag(lim.cpu || LEARNER_RES.limCpu),
        '--memory', this.memFlag(lim.memory || LEARNER_RES.limMem),
        '-e', `K3S_CLUSTER_INIT=${(course && course.clusterInit) ? 'true' : 'false'}`];
      if (course && course.hostModules) args.push('-v', '/lib/modules:/lib/modules:ro');
      if (process.env.DOCKER_NETWORK) args.push('--network', process.env.DOCKER_NETWORK);
      args.push(resolveImage(course && course.image) || LEARNER_IMAGE);
      docker(args, { timeout: 300_000 }) // cold pull of a learner image can take a while
        .then(r => { if (!r.ok) console.error(`[docker] run ${name} 실패:`, r.stderr.trim().slice(-300)); });
    },
    // systemd finished booting (degraded allowed — some units failing is normal in a container)
    probeReady(name) {
      return docker(['exec', name, 'sh', '-c',
        "systemctl is-system-running 2>/dev/null | grep -qE 'running|degraded'"]).then(r => r.ok);
    },
    async maintain() {
      if (this._maint) return; // readiness probes must not overlap
      this._maint = true;
      try {
        const r = await docker(['ps', '-a', '--filter', 'name=^warmpod-',
          '--format', '{{.Names}}\t{{.Image}}\t{{.State}}']);
        if (!r.ok) return;
        const rows = r.stdout.trim() ? r.stdout.trim().split('\n').map(l => l.split('\t')) : [];
        const live = [];
        for (const [name, image, state] of rows) {
          if (state !== 'running' || image !== LEARNER_IMAGE) {
            docker(['rm', '-f', name]); // exited or built from a previous LEARNER_IMAGE
            if (image !== LEARNER_IMAGE) console.log(`[warmpool] 구 이미지 웜 컨테이너 폐기: ${name} (${image} ≠ ${LEARNER_IMAGE})`);
            continue;
          }
          live.push(name);
        }
        const ready = [];
        for (const name of live) if (await this.probeReady(name)) ready.push(name);
        this.warmReady = ready;
        const target = warmTarget();
        for (let i = live.length; i < target; i++) {
          const name = 'warmpod-' + crypto.randomBytes(4).toString('hex');
          this.newContainer(name, 'warm-pod');
          console.log(`[warmpool] 웜 컨테이너 기동 시작: ${name}`);
        }
        let excess = live.length - target;
        while (excess-- > 0 && this.warmReady.length) {
          const name = this.warmReady.pop();
          docker(['rm', '-f', name]);
          console.log(`[warmpool] 웜 컨테이너 축소 회수: ${name}`);
        }
      } finally { this._maint = false; }
    },
    warmCount() { return this.warmReady.length; },
    alloc(course) {
      const id = 'lab-' + crypto.randomBytes(4).toString('hex');
      // Warm pool holds default-environment containers only — courses with a custom
      // image/resources/clusterInit cold-boot (same rule as the pod driver).
      const custom = !!(course && (course.image || course.resources || course.clusterInit));
      const wp = custom ? null : this.warmReady.shift();
      if (wp) {
        docker(['rename', wp, id]);
        setTimeout(() => this.maintain(), 3000);
        return { id, vmName: id, warm: true };
      }
      this.newContainer(id, 'learner-pod', course);
      return { id, vmName: id, warm: false };
    },
    prepare() {},
    // ready = systemd booted → (if present) module bootstrap finished
    async checkReady(s) {
      if (!s.podReady) {
        if (!(await this.probeReady(s.vmName))) return false;
        s.podReady = true;
      }
      const bs = labPath(s.labId, 'bootstrap.sh');
      if (fs.existsSync(bs) && !s.bootstrapDone) {
        if (!s.bootstrapping) {
          s.bootstrapping = true;
          this.runCheck(s, bs, (pass, out) => {
            s.bootstrapping = false;
            s.bootstrapDone = pass;
            if (!pass) console.error(`[bootstrap] ${s.id} 실패:`, out.slice(-300));
          }, 180_000);
        }
        return false;
      }
      return true;
    },
    spawnTerminal(s) {
      return spawn('python3', [path.join(ROOT, 'ptybridge.py'),
        'docker', 'exec', '-it', s.vmName, 'su', '-', 'learner'],
        { stdio: ['pipe', 'pipe', 'pipe', 'pipe'], env: process.env });
    },
    // run a script inside the container as learner (learner has NOPASSWD sudo)
    runCheck(s, script, cb, timeoutMs = 20_000) {
      const child = spawn('docker',
        ['exec', '-i', s.vmName, 'su', '-', 'learner', '-c', 'bash -s'],
        { stdio: ['pipe', 'pipe', 'pipe'] });
      let out = '';
      child.stdout.on('data', d => out += d);
      child.stderr.on('data', d => out += d);
      const t = setTimeout(() => child.kill('SIGKILL'), timeoutMs);
      child.on('exit', code => { clearTimeout(t); cb(code === 0, out.trim()); });
      child.stdin.end(CHECK_PREAMBLE + fs.readFileSync(script));
    },
    async reap(s) {
      await docker(['rm', '-f', s.vmName]);
    },
  },
};
const driver = drivers[DRIVER];
if (!driver) { console.error(`unknown DRIVER=${DRIVER}`); process.exit(1); }

/* ── 세션 매니저 ─────────────────────────────────── */
const sessions = new Map();

// 최근 30분 할당 이력 → 웜풀 목표치 (min ≤ 수요 ≤ max)
// kubevirt 웜 "디스크"는 스토리지만 점유하므로 동적 대상에서 제외(정적 WARM_POOL_SIZE 유지)
const allocLog = [];
function warmTarget() {
  const cut = Date.now() - 30 * 60_000;
  while (allocLog.length && allocLog[0] < cut) allocLog.shift();
  return Math.min(WARM_POOL_MAX, Math.max(WARM_POOL_MIN, allocLog.length));
}

// 활동 갱신: 터미널 접속/입력, 스텝 검증, 연장 — 유휴 판정의 기준 시각
function touchSession(s) { s.lastActivityAt = Date.now(); s.idleWarned = false; }

// 기동 시 고아 학습자 VM·디스크 정리 후 웜풀 유지 시작
// (웜 디스크(warm-disk)는 클러스터에 남아 재기동 후에도 재사용됨)
async function startupGC() {
  if (DRIVER === 'kubevirt') {
    await kubectl(['delete', 'vm', '-n', NS, '-l', 'snacklab/kind=learner-vm', '--wait=false']);
    await kubectl(['delete', 'dv', '-n', NS, '-l', 'snacklab/kind=learner-disk', '--wait=false']);
  }
  if (DRIVER === 'pod') {
    await kubectl(['delete', 'pod', '-n', NS, '-l', 'snacklab/kind=learner-pod', '--wait=false']);
  }
  if (DRIVER === 'docker') {
    // orphaned learner containers from a previous run; warm ones survive and get reused
    const r = await docker(['ps', '-aq', '--filter', 'name=^lab-']);
    if (r.ok && r.stdout.trim()) await docker(['rm', '-f', ...r.stdout.trim().split('\n')]);
  }
  driver.init();
}
startupGC();

function createSession(labId, user, locale) {
  const meta = labMeta(labId);
  if (!labAvailable(meta)) return null;

  const course = labCourses.get(labId);
  const env = driver.alloc(course);

  // 랩별 TTL·유휴 오버라이드 — 모의고사처럼 120분 단위로 붙잡고 있어야 하는 랩이 있다.
  // 우선순위: 모듈 meta > 코스 course.json > 전역 env. 전역보다 짧게도 길게도 잡을 수 있다.
  const ttlMinutes = Number(meta.ttlMinutes ?? course?.ttlMinutes ?? TTL_MINUTES);
  const idleMinutes = Number(meta.idleMinutes ?? course?.idleMinutes ?? IDLE_MINUTES);

  const now = Date.now();
  allocLog.push(now);
  const s = {
    ...env,
    id: crypto.randomBytes(4).toString('hex'),
    // 상단 랩 제목도 문항과 같은 언어로 맞춘다(시험 언어가 강제되는 랩이면 그 언어)
    labId, labTitle: loc(meta.title, examContentLang(meta, locale)),
    locale: locale || DEFAULT_LOCALE, user: user || 'anonymous',
    state: 'Provisioning',
    createdAt: now, lastActivityAt: now,
    ttlMinutes, idleMinutes,
    readyAt: now + (env.warm ? driver.warmMs : driver.coldMs),
    expiresAt: now + ttlMinutes * 60 * 1000,
    extended: false, checks: {}, ptys: new Set(), wsClients: new Set(),
  };
  driver.prepare(s, labId);
  sessions.set(s.id, s);
  return s;
}

function sessionView(s) {
  return {
    id: s.id, labId: s.labId, labTitle: s.labTitle, user: s.user,
    state: s.state, warm: s.warm, vmName: s.vmName || null, vmIP: s.vmIP || null,
    createdAt: s.createdAt, expiresAt: s.expiresAt,
    extended: s.extended, checks: s.checks,
    grading: s.grading || null, exam: s.exam || null, examError: s.examError || null,
    remainingSec: Math.max(0, Math.floor((s.expiresAt - Date.now()) / 1000)),
    idleSec: Math.floor((Date.now() - (s.lastActivityAt || s.createdAt)) / 1000),
  };
}

function reapSession(s, reason) {
  s.state = reason; // 'Expired' | 'Terminated' | 'Idle'
  for (const p of s.ptys) { try { p.kill('SIGTERM'); } catch {} }
  s.ptys.clear();
  for (const w of s.wsClients || []) { try { w.close(); } catch {} }
  driver.reap(s);
}

// 준비 상태 폴러: Provisioning → Running
setInterval(async () => {
  for (const s of sessions.values()) {
    if (s.state !== 'Provisioning') continue;
    if (Date.now() > s.expiresAt) { reapSession(s, 'Expired'); continue; }
    if (await driver.checkReady(s)) s.state = 'Running';
  }
}, 3000);

// TTL + 유휴 컨트롤러
setInterval(() => {
  const now = Date.now();
  for (const s of sessions.values()) {
    if (s.state !== 'Running') continue;
    if (now > s.expiresAt) { reapSession(s, 'Expired'); continue; }
    const idleLimit = s.idleMinutes ?? IDLE_MINUTES;
    if (idleLimit <= 0) continue;
    const idleMs = now - (s.lastActivityAt || s.createdAt);
    if (idleMs > (idleLimit + IDLE_GRACE_MINUTES) * 60_000) {
      console.log(`[idle] ${s.id} (${s.user}/${s.labId}) 유휴 ${Math.round(idleMs / 60_000)}분 — 회수`);
      reapSession(s, 'Idle');
    } else if (idleMs > idleLimit * 60_000 && !s.idleWarned) {
      s.idleWarned = true;
      const msg = '\r\n\x1b[33m[lab] ' + t(s.locale, 'idleWarn', idleLimit, IDLE_GRACE_MINUTES) + '\x1b[0m\r\n';
      for (const w of s.wsClients) { try { w.send(msg); } catch {} }
    }
  }
}, 10_000);

// WS keepalive: 30초마다 ping — pong 없는 좀비 연결은 종료해 pty를 회수
setInterval(() => {
  for (const s of sessions.values()) {
    for (const w of s.wsClients) {
      if (w.isAlive === false) { try { w.terminate(); } catch {} continue; }
      w.isAlive = false;
      try { w.ping(); } catch {}
    }
  }
}, 30_000);

/* ── HTTP API ───────────────────────────────────── */
const app = express();
app.use(express.json());

/* 인증 게이트: /auth/* 는 통과, API는 401 JSON, 페이지는 로그인으로 리다이렉트 */
app.use((req, res, next) => {
  req.auth = authOf(req);
  if (req.auth || req.path.startsWith('/auth/')) return next();
  if (req.path.startsWith('/api/')) return res.status(401).json({ error: t(localeOf(req), 'loginRequired') });
  if ((req.path === '/' || req.path.endsWith('.html')) && !['/login.html', '/signup.html'].includes(req.path)) {
    return res.redirect('/auth/login?next=' + encodeURIComponent(req.originalUrl));
  }
  next(); // css/js 등 정적 자산은 공개
});
/* 승인 게이트: 승인 대기 계정은 확인용 API(/api/me·info) 외 전부 403 — 첫 화면이 안내를 띄운다 */
app.use((req, res, next) => {
  if (req.path.startsWith('/api/') && !['/api/me', '/api/info'].includes(req.path) && pendingLocal(req.auth)) {
    return res.status(403).json({ error: t(localeOf(req), 'approvalPending'), pending: true });
  }
  next();
});
app.use(express.static(path.join(ROOT, 'public')));

/* ── 로그인 (OIDC authorization code) ────────────── */
const AUTH_COOKIE = { httpOnly: true, secure: PUBLIC_URL.startsWith('https'), sameSite: 'lax' };

app.get('/auth/login', (req, res) => {
  if (!AUTH_ON) return res.redirect('/');
  if (AUTH_MODE === 'local') return res.sendFile(path.join(ROOT, 'public', 'login.html'));
  if (!oidc) return res.status(503).send('인증 서버 준비 중입니다. 잠시 후 다시 시도하세요.');
  const state = crypto.randomBytes(16).toString('hex');
  const nextRaw = String(req.query.next || '/');
  const next = nextRaw.startsWith('/') && !nextRaw.startsWith('//') ? nextRaw : '/';
  res.cookie('lab_state', signToken({ s: state, n: next, exp: Date.now() + 600_000 }),
    { ...AUTH_COOKIE, maxAge: 600_000 });
  res.redirect(oidc.authorization_endpoint + '?' + new URLSearchParams({
    client_id: OIDC_CLIENT_ID, response_type: 'code', scope: 'openid profile email',
    redirect_uri: PUBLIC_URL + '/auth/callback', state,
  }));
});

app.get('/auth/callback', async (req, res) => {
  const st = verifyToken(parseCookies(req).lab_state);
  if (!oidc || !st || st.s !== req.query.state || !req.query.code) {
    return res.status(400).send('로그인 상태가 유효하지 않습니다. <a href="/auth/login">다시 로그인</a>');
  }
  const tr = await fetch(oidc.token_endpoint, {
    method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'authorization_code', code: String(req.query.code),
      redirect_uri: PUBLIC_URL + '/auth/callback',
      client_id: OIDC_CLIENT_ID, client_secret: OIDC_CLIENT_SECRET,
    }),
  }).then(r => r.json()).catch(() => null);
  if (!tr || !tr.access_token) return res.status(502).send('토큰 교환에 실패했습니다. <a href="/auth/login">다시 로그인</a>');
  const ui = await fetch(oidc.userinfo_endpoint, { headers: { Authorization: 'Bearer ' + tr.access_token } })
    .then(r => r.json()).catch(() => null);
  if (!ui || !ui.preferred_username) return res.status(502).send('사용자 정보 조회에 실패했습니다.');
  res.clearCookie('lab_state');
  res.cookie('lab_auth',
    signToken({ u: ui.preferred_username, n: ui.name || ui.preferred_username, exp: Date.now() + AUTH_TTL_MS }),
    { ...AUTH_COOKIE, maxAge: AUTH_TTL_MS });
  res.redirect(st.n);
});

app.post('/auth/local', (req, res) => {
  if (AUTH_MODE !== 'local') return res.status(404).json({ error: 'not in local auth mode' });
  const lang = localeOf(req);
  const ip = req.ip;
  const f = loginFails.get(ip);
  if (f && f.until > Date.now()) {
    return res.status(429).json({ error: t(lang, 'tooManyLogins') });
  }
  verifyLocal(String(req.body.user || ''), String(req.body.pass || ''), u => {
    if (!u) {
      const n = (f && f.until === 0 ? f.n : 0) + 1;
      loginFails.set(ip, { n, until: n >= 5 ? Date.now() + 60_000 : 0 });
      return res.status(401).json({ error: t(lang, 'badCredentials') });
    }
    loginFails.delete(ip);
    res.cookie('lab_auth',
      signToken({ u: u.user, n: u.name || u.user, a: u.admin ? 1 : 0, exp: Date.now() + AUTH_TTL_MS }),
      { ...AUTH_COOKIE, maxAge: AUTH_TTL_MS });
    const nextRaw = String(req.body.next || '/');
    res.json({ next: nextRaw.startsWith('/') && !nextRaw.startsWith('//') ? nextRaw : '/' });
  });
});

// 셀프 가입: 팀·이름·계정명·비밀번호·이메일 → approved:false로 저장, 관리자 승인 후 사용 가능
app.post('/auth/signup', (req, res) => {
  if (AUTH_MODE !== 'local' || !SIGNUP_ENABLED) return res.status(404).json({ error: 'signup disabled' });
  const lang = localeOf(req);
  const h = signupHits.get(req.ip);
  if (h && h.resetAt > Date.now() && h.n >= 5) {
    return res.status(429).json({ error: t(lang, 'tooManySignups') });
  }
  const user = String(req.body.user || '').trim().toLowerCase();
  const name = String(req.body.name || '').trim();
  const team = String(req.body.team || '').trim();
  const email = String(req.body.email || '').trim();
  const pass = String(req.body.pass || '');
  const bad = msg => res.status(400).json({ error: msg });
  if (!/^[a-z0-9][a-z0-9_-]{2,31}$/.test(user)) return bad(t(lang, 'badUsername'));
  if (!name || name.length > 64) return bad(t(lang, 'needName'));
  if (!team || team.length > 64) return bad(t(lang, 'needTeam'));
  if (!/^\S+@\S+\.\S+$/.test(email) || email.length > 128) return bad(t(lang, 'badEmail'));
  if (pass.length < 8) return bad(t(lang, 'shortPassword'));
  const users = loadUsers();
  if (users.some(x => x.user === user)) return res.status(409).json({ error: t(lang, 'userTaken') });
  const salt = crypto.randomBytes(16);
  const hash = 'scrypt:' + salt.toString('base64') + ':' + crypto.scryptSync(pass, salt, 32).toString('base64');
  users.push({ user, name, team, email, hash, approved: false, createdAt: Date.now() });
  try { writeUsers(users); } catch (e) {
    console.error('[auth] users.json 쓰기 실패:', e.message);
    return res.status(500).json({ error: t(lang, 'saveFailed') });
  }
  const live = h && h.resetAt > Date.now();
  signupHits.set(req.ip, { n: (live ? h.n : 0) + 1, resetAt: live ? h.resetAt : Date.now() + 600_000 });
  console.log(`[auth] 가입: ${user} (${team} / ${name}) — 승인 대기`);
  res.status(201).json({ ok: true });
});

app.get('/auth/logout', (req, res) => {
  res.clearCookie('lab_auth');
  if (!AUTH_ON || !oidc) return res.redirect('/');
  res.redirect(oidc.end_session_endpoint + '?' + new URLSearchParams({
    client_id: OIDC_CLIENT_ID, post_logout_redirect_uri: PUBLIC_URL,
  }));
});

app.get('/api/me', (req, res) => res.json({ ...req.auth, approved: !pendingLocal(req.auth), authOn: AUTH_ON }));

app.get('/api/info', (req, res) => res.json({
  driver: DRIVER, ttlMinutes: TTL_MINUTES, idleMinutes: IDLE_MINUTES,
  locale: localeOf(req), defaultLocale: DEFAULT_LOCALE, locales: LOCALES,
}));

// meta를 로케일로 평탄화 (title, steps[].title)
function locMeta(meta, lang) {
  if (!meta) return meta;
  return {
    ...meta, title: loc(meta.title, lang),
    steps: (meta.steps || []).map(st => ({ ...st, title: loc(st.title, lang) })),
  };
}

app.get('/api/labs', (req, res) => {
  const lang = localeOf(req);
  res.json(catalog.map(c => {
    const meta = labMeta(c.id) || {};
    return { ...c, ...locMeta(meta, lang), title: loc(c.title ?? meta.title, lang), desc: loc(c.desc ?? meta.desc, lang),
      trackTitle: loc(c.trackTitle, lang), trackDesc: loc(c.trackDesc, lang), available: labAvailable(meta) };
  }));
});

// 콘텐츠 파일 폴백: <base>.<로케일>.md → 같은 언어의 다른 변형 → .en.md → .md(기본 로케일 원문).
// 미번역 로케일 사용자에게 기본 로케일(한국어) 원문보다 영어가 실용적이라 en 을 앞에 둔다.
// 단 요청이 기본 로케일 자체라면 확장자 없는 원문(<base>.md)이 그 로케일의 정본이므로 먼저 본다
// — 이 순서를 빠뜨리면 한국어 사용자에게 영어 가이드가 나간다.
const contentFiles = (base, lang) => [
  `${base}.${lang}.md`,
  ...(lang === DEFAULT_LOCALE ? [`${base}.md`] : []),
  ...localeFamily(lang).map(l => `${base}.${l}.md`),
  `${base}.en.md`, `${base}.md`,
];

/* ── 시험 언어 ───────────────────────────────────
 * 자격시험 모의고사는 **실제 시험이 제공하는 언어**로 푸는 것이 연습이 된다. meta.exam.languages
 * 에 그 목록을 두면(CKA = en·ja·zh-CN), 미지원 로케일 사용자에게는 콘텐츠를 영어로 내린다.
 * 포털 UI 언어는 그대로 두고 **문항·채점 메시지·해설만** 시험 언어로 바꾼다.
 * 학습자가 자기 언어 번역을 굳이 보겠다고 하면 `?native=1` 로 그 강제를 해제한다(연습용 선택). */
function examLangs(meta) {
  const l = meta && meta.exam && meta.exam.languages;
  return Array.isArray(l) && l.length ? l : null;
}
function examContentLang(meta, lang) {
  const langs = examLangs(meta);
  if (!langs || langs.includes(lang)) return lang;
  // 시험 언어 중 같은 언어의 변형이 있으면 그쪽이 영어보다 가깝다 (zh-TW → 시험이 제공하는 zh-CN)
  const family = langs.find(l => l.split('-')[0] === String(lang).split('-')[0]);
  return family || (langs.includes('en') ? 'en' : langs[0]);
}
// 학습자 로케일 번역본이 실제로 있는지 (팝업에서 "그래도 내 언어로 보기" 를 줄지 판단)
function hasNativeContent(labId, lang) {
  return fs.existsSync(labPath(labId, `guide.${lang}.md`))
    || (lang === DEFAULT_LOCALE && fs.existsSync(labPath(labId, 'guide.md')));
}
// Content locale of a request — applies the exam-language forcing (+ ?native=1 opt-out).
// ?examLang= is the exam language the learner picked in the popup (valid only within the
// exam's language list) — it changes the task language without touching the portal locale.
function contentLocaleOf(req, meta) {
  const lang = localeOf(req);
  if (req.query && req.query.native === '1') return lang;
  const langs = examLangs(meta);
  const choice = req.query && req.query.examLang;
  if (choice && langs && langs.includes(choice)) return choice;
  return examContentLang(meta, lang);
}

app.get('/api/labs/:id/guide', (req, res) => {
  const lang = localeOf(req);
  const meta = labMeta(req.params.id);
  if (!meta) return res.status(404).json({ error: 'lab not found' });
  const contentLang = contentLocaleOf(req, meta);
  const guidePath = contentFiles('guide', contentLang)
    .map(f => labPath(req.params.id, f)).find(p => fs.existsSync(p));
  if (!guidePath) return res.status(404).json({ error: 'lab not found' });
  res.json({
    meta: locMeta(meta, contentLang), markdown: fs.readFileSync(guidePath, 'utf8'),
    userLang: lang, contentLang, examLanguages: examLangs(meta),
    examName: (meta.exam && meta.exam.name) || null,
    nativeAvailable: hasNativeContent(req.params.id, lang),
  });
});

app.post('/api/sessions', (req, res) => {
  const lang = localeOf(req);
  const act = [...sessions.values()].filter(s => s.state === 'Running' || s.state === 'Provisioning');
  if (MAX_SESSIONS_PER_USER > 0 && !req.auth.admin) {
    const mine = act.filter(s => s.user === req.auth.user);
    if (mine.length >= MAX_SESSIONS_PER_USER) {
      return res.status(409).json({ error: t(lang, 'sessionAlreadyActive', mine[0].labTitle) });
    }
  }
  if (act.length >= MAX_SESSIONS) {
    return res.status(429).json({ error: t(lang, 'sessionsFull', act.length, MAX_SESSIONS) });
  }
  const s = createSession(req.body.labId, req.auth.user, lang);
  if (!s) return res.status(400).json({ error: t(lang, 'moduleUnavailable') });
  res.status(201).json(sessionView(s));
});

// 본인 세션만 접근 (admin은 전체) — 실패 시 응답까지 처리하고 null 반환
function ownedSession(req, res) {
  const s = sessions.get(req.params.id);
  if (!s) { res.status(404).json({ error: 'session not found' }); return null; }
  if (s.user !== req.auth.user && !req.auth.admin) { res.status(403).json({ error: t(localeOf(req), 'notYourSession') }); return null; }
  return s;
}

app.get('/api/sessions', (req, res) =>
  res.json([...sessions.values()].filter(s => req.auth.admin || s.user === req.auth.user).map(sessionView)));

app.get('/api/sessions/:id', (req, res) => {
  const s = ownedSession(req, res);
  if (s) res.json(sessionView(s));
});

app.post('/api/sessions/:id/extend', (req, res) => {
  const s = ownedSession(req, res);
  if (!s) return;
  if (s.extended) return res.status(409).json({ error: t(localeOf(req), 'extendOnce') });
  s.extended = true;
  s.expiresAt += EXTEND_MINUTES * 60 * 1000;
  touchSession(s);
  res.json(sessionView(s));
});

app.delete('/api/sessions/:id', (req, res) => {
  const s = ownedSession(req, res);
  if (!s) return;
  if (s.state === 'Running' || s.state === 'Provisioning') reapSession(s, 'Terminated');
  res.json(sessionView(s));
});

app.post('/api/sessions/:id/verify', (req, res) => {
  const s = ownedSession(req, res);
  if (!s) return;
  if (s.state !== 'Running') return res.status(409).json({ error: t(localeOf(req), 'sessionState', s.state) });

  const step = Number(req.body.step);
  const meta = labMeta(s.labId);
  const check = meta && meta.steps && meta.steps[step] && meta.steps[step].check;
  if (!check) return res.status(400).json({ error: 'invalid step' });

  touchSession(s);
  driver.runCheck(s, labPath(s.labId, 'checks', check), (pass, rawOutput) => {
    const output = renderCheckOutput(rawOutput, s.labId, localeOf(req));
    s.checks[step] = { pass, at: Date.now() };
    // 통과 시 사용자 진행상황에 영속 기록 — 모듈 이수/트랙 완주 뱃지가 새로 달성되면 응답에 실어 축하
    const earned = pass ? recordStepPass(s.user, s.labId, step, meta) : {};
    res.json({ pass, output: output.slice(0, 2000), ...earned });
  });
});

/* ── 시험형 랩(제출·일괄채점) ─────────────────────
 * meta.exam 이 있는 랩은 문항마다 [체크] 하지 않고 [제출] 한 번으로 전 문항을 채점한다.
 * 점수는 체크 스크립트가 내보내는 part 줄(부분점수)을 합산하고, 기준 점수를 넘기면
 * 만점이 아니어도 모듈 이수 뱃지를 준다. 틀린 문항 해설은 채점 응답에만 실어 보낸다
 * (제출 전에는 어떤 경로로도 내려주지 않는다). */
const explainCache = new Map(); // `${labId}:${lang}` → string[]
function explainSections(labId, lang) {
  const key = labId + ':' + lang;
  if (!explainCache.has(key)) {
    const p = contentFiles('explain', lang)
      .map(f => labPath(labId, f)).find(f => fs.existsSync(f));
    let secs = [];
    try {
      if (p) secs = fs.readFileSync(p, 'utf8').split(/\n(?=## )/).map(x => x.trim()).filter(x => x.startsWith('## '));
    } catch (e) { console.error(`[content] ${labId} 해설 읽기 실패:`, e.message); }
    explainCache.set(key, secs);
  }
  return explainCache.get(key);
}
const examPassScore = (meta, max) =>
  Math.ceil((Number((meta.exam || {}).passPercent) || 66) * max / 100);

// 15문항을 순서대로 돌리면 1~2분 걸린다 — 응답을 붙들고 있으면 앞단 프록시의 읽기 타임아웃에
// 걸리므로 채점은 백그라운드로 돌리고, 클라이언트는 세션 폴링(grading/exam)으로 결과를 받아간다.
async function gradeExam(s, meta, lang) {
  const steps = meta.steps || [];
  const explains = explainSections(s.labId, lang);
  const results = [];
  for (const [i, st] of steps.entries()) {
    const r = await new Promise(resolve => driver.runCheck(s, labPath(s.labId, 'checks', st.check),
      (pass, raw) => resolve({ pass, raw }), 45_000));
    const p = parseCheckResult(r.raw, s.labId, lang);
    // part 줄을 쓰지 않는 스크립트는 통과/실패 이분법 — meta 의 배점을 통째로 준다.
    const max = p.parts.length ? p.max : (Number(st.points) || 0);
    const earned = p.parts.length ? p.earned : (r.pass ? max : 0);
    results.push({
      step: i, title: loc(st.title, lang), earned, max,
      parts: p.parts, output: p.output.slice(0, 1000),
      explain: earned < max ? (explains[i] || null) : null,
    });
    s.checks[i] = { pass: max > 0 && earned >= max, at: Date.now(), earned, max };
    s.grading = { done: i + 1, total: steps.length };
    touchSession(s);
  }
  const total = results.reduce((a, r) => a + r.earned, 0);
  const max = results.reduce((a, r) => a + r.max, 0);
  const passScore = examPassScore(meta, max);
  const passed = max > 0 && total >= passScore;
  const earned = recordExamResult(s.user, s.labId, results, total, max, passed);
  console.log(`[exam] ${s.user} ${s.labId} 제출: ${total}/${max} (기준 ${passScore}) ${passed ? 'PASS' : 'FAIL'}`);
  // 뱃지는 "이번 제출에서 새로" 딴 것만 실어 보낸다 — 축하는 한 번이면 된다
  s.exam = { results, total, max, passScore, passed, at: Date.now(), ...earned };
}

app.post('/api/sessions/:id/submit', (req, res) => {
  const s = ownedSession(req, res);
  if (!s) return;
  const lang = localeOf(req);
  if (s.state !== 'Running') return res.status(409).json({ error: t(lang, 'sessionState', s.state) });
  const meta = labMeta(s.labId);
  if (!meta || !meta.exam) return res.status(400).json({ error: 'not an exam lab' });
  if (s.grading) return res.status(409).json({ error: t(lang, 'examGrading') });

  s.grading = { done: 0, total: (meta.steps || []).length };
  s.examError = null;
  touchSession(s);
  // 채점 메시지·해설도 문항과 같은 언어로 (시험 미지원 로케일이면 영어)
  gradeExam(s, meta, contentLocaleOf(req, meta))
    .catch(e => {
      console.error(`[exam] ${s.id} 채점 실패:`, e.message);
      s.examError = t(lang, 'examFailed');
    })
    .finally(() => { s.grading = null; });
  res.status(202).json({ started: true, total: s.grading.total });
});

/* ── 진행상황·뱃지 API ───────────────────────────── */
app.get('/api/progress', (req, res) => res.json(progressView(req.auth.user, localeOf(req))));

// 상황판(수료 현황): 전체 사용자의 모듈 이수·트랙 완주 뱃지
app.get('/api/admin/progress', (req, res) => {
  if (!req.auth.admin) return res.status(403).json({ error: t(localeOf(req), 'adminRequired') });
  const lang = localeOf(req);
  res.json({
    modules: catalog.map(c => ({
      id: c.id, no: c.no, track: c.track,
      title: loc(c.title ?? (labMeta(c.id) || {}).title, lang),
    })),
    users: Object.keys(progress).sort()
      .map(user => ({ user, ...progressView(user, lang) })),
  });
});

app.get('/api/admin/summary', (req, res) => {
  if (!req.auth.admin) return res.status(403).json({ error: t(localeOf(req), 'adminRequired') });
  const lang = localeOf(req);
  // labTitle 은 세션 생성 시 학습자 로케일로 고정되므로, 관리자 화면에서는 현재 관리자 로케일로 다시 로케일라이즈
  const localizeTitle = s => {
    const meta = labMeta(s.labId);
    return { ...s, labTitle: (meta && loc(meta.title, lang)) || s.labTitle };
  };
  res.json({
    driver: DRIVER,
    sessions: [...sessions.values()].map(sessionView).map(localizeTitle),
    warmPool: driver.warmCount(), warmPoolSize: WARM_POOL_SIZE,
    warmTarget: warmTarget(), warmPoolMin: WARM_POOL_MIN, warmPoolMax: WARM_POOL_MAX,
    warmPoolHardCap: WARM_POOL_HARD_CAP,
    ttlMinutes: TTL_MINUTES, idleMinutes: IDLE_MINUTES,
    maxSessions: MAX_SESSIONS, maxSessionsPerUser: MAX_SESSIONS_PER_USER,
  });
});

// 웜풀 min/max 런타임 조정 (admin 전용). min=max 로 고정, 0 이면 웜풀 비활성.
app.post('/api/admin/warmpool', (req, res) => {
  const lang = localeOf(req);
  if (!req.auth.admin) return res.status(403).json({ error: t(lang, 'adminRequired') });
  const min = Number((req.body || {}).min);
  const max = Number((req.body || {}).max);
  if (!Number.isInteger(min) || !Number.isInteger(max))
    return res.status(400).json({ error: t(lang, 'minMaxInt') });
  if (min < 0 || min > max || max > WARM_POOL_HARD_CAP)
    return res.status(400).json({ error: t(lang, 'minMaxRange', WARM_POOL_HARD_CAP) });
  WARM_POOL_MIN = min; WARM_POOL_MAX = max;
  saveWarmCfg();
  if (typeof driver.maintain === 'function') driver.maintain(); // 즉시 반영(기동/축소)
  console.log(`[warmpool] 관리자 조정: min=${min} max=${max} (by ${req.auth.user})`);
  res.json({ warmPoolMin: WARM_POOL_MIN, warmPoolMax: WARM_POOL_MAX, warmTarget: warmTarget(), warmPoolHardCap: WARM_POOL_HARD_CAP });
});

/* ── 계정 관리 API (local 모드 · admin 전용) ── */
function adminLocalGuard(req, res) {
  if (!req.auth.admin) { res.status(403).json({ error: t(localeOf(req), 'adminRequired') }); return false; }
  if (AUTH_MODE !== 'local') { res.status(400).json({ error: 'not in local auth mode' }); return false; }
  return true;
}
app.get('/api/admin/users', (req, res) => {
  if (!req.auth.admin) return res.status(403).json({ error: t(localeOf(req), 'adminRequired') });
  if (AUTH_MODE !== 'local') return res.json({ mode: AUTH_MODE, users: [] });
  res.json({ mode: 'local', users: loadUsers().map(({ hash, ...u }) => ({ ...u, approved: approvedOf(u) })) });
});
app.post('/api/admin/users/:user/approve', (req, res) => {
  if (!adminLocalGuard(req, res)) return;
  const users = loadUsers();
  const u = users.find(x => x.user === req.params.user);
  if (!u) return res.status(404).json({ error: 'user not found' });
  u.approved = true; u.approvedAt = Date.now(); u.approvedBy = req.auth.user;
  writeUsers(users);
  console.log(`[auth] 승인: ${u.user} (by ${req.auth.user})`);
  res.json({ ok: true });
});
app.delete('/api/admin/users/:user', (req, res) => {
  if (!adminLocalGuard(req, res)) return;
  const target = req.params.user;
  const users = loadUsers();
  const u = users.find(x => x.user === target);
  if (!u) return res.status(404).json({ error: 'user not found' });
  if (target === req.auth.user || ADMIN_USERS.includes(target) || u.admin) {
    return res.status(400).json({ error: t(localeOf(req), 'cannotDeleteSelfOrAdmin') });
  }
  writeUsers(users.filter(x => x.user !== target));
  console.log(`[auth] 계정 삭제: ${target} (by ${req.auth.user})`);
  res.json({ ok: true });
});

/* ── 웹터미널: WS ↔ ptybridge.py ↔ (bash | virtctl console) ── */
const server = http.createServer(app);
const wss = new WebSocketServer({ noServer: true });

server.on('upgrade', (req, socket, head) => {
  const auth = authOf(req);
  const m = req.url.match(/^\/ws\/term\/([\w-]+)$/);
  const s = m && sessions.get(m[1]);
  if (!auth || pendingLocal(auth) || !s || s.state !== 'Running' || (s.user !== auth.user && !auth.admin)) { socket.destroy(); return; }
  wss.handleUpgrade(req, socket, head, ws => {
    const child = driver.spawnTerminal(s);
    s.ptys.add(child);
    s.wsClients.add(ws);
    touchSession(s);
    ws.isAlive = true;
    ws.on('pong', () => { ws.isAlive = true; });
    child.stdout.on('data', d => ws.readyState === 1 && ws.send(d));
    child.stderr.on('data', d => ws.readyState === 1 && ws.send(d));
    child.on('exit', () => { s.ptys.delete(child); try { ws.close(); } catch {} });
    ws.on('message', (data, isBinary) => {
      if (isBinary) {
        try {
          const c = JSON.parse(data.toString());
          if (c.type === 'resize') child.stdio[3].write(`resize:${c.cols}x${c.rows}\n`);
        } catch {}
      } else {
        touchSession(s);
        child.stdin.write(data.toString());
      }
    });
    ws.on('close', () => { try { child.kill('SIGTERM'); } catch {} s.ptys.delete(child); s.wsClients.delete(ws); });
  });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`[snacklab] listening on http://0.0.0.0:${PORT}`);
  console.log(`[snacklab] driver=${DRIVER} ns=${NS} TTL=${TTL_MINUTES}m warm=${WARM_POOL_MIN}~${WARM_POOL_MAX} idle=${IDLE_MINUTES}+${IDLE_GRACE_MINUTES}m perUser=${MAX_SESSIONS_PER_USER}`);
});
