#!/usr/bin/env node
/*
 * 내장 로그인(local 모드) 계정 관리 — users.json (mode 600)
 *
 *   node userctl.js add <user> [--name "표시 이름"] [--admin]   # 비밀번호는 프롬프트 또는 stdin 파이프
 *   node userctl.js del <user>
 *   node userctl.js list
 *
 * 해시: scrypt(salt 16B, key 32B) → "scrypt:<salt b64>:<hash b64>"
 * USERS_FILE 환경변수로 파일 경로 변경 가능 (server.js와 동일 기본값)
 */
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const USERS_FILE = process.env.USERS_FILE || path.join(__dirname, 'users.json');
const [cmd, user] = process.argv.slice(2);
const args = process.argv.slice(3);

function load() {
  try { return JSON.parse(fs.readFileSync(USERS_FILE, 'utf8')); } catch { return []; }
}
function save(users) {
  fs.writeFileSync(USERS_FILE, JSON.stringify(users, null, 2) + '\n', { mode: 0o600 });
}

// 비밀번호 입력: TTY면 에코 없이 프롬프트, 파이프면 첫 줄
function readPassword(cb) {
  if (!process.stdin.isTTY) {
    let buf = '';
    process.stdin.on('data', d => buf += d);
    process.stdin.on('end', () => cb(buf.split('\n')[0]));
    return;
  }
  process.stderr.write('password: ');
  process.stdin.setRawMode(true);
  process.stdin.resume();
  let pw = '';
  process.stdin.on('data', ch => {
    const c = ch.toString();
    if (c === '\r' || c === '\n') {
      process.stdin.setRawMode(false);
      process.stdin.pause();
      process.stderr.write('\n');
      cb(pw);
    } else if (c === '\x03') { process.exit(130); }
    else if (c === '\x7f') { pw = pw.slice(0, -1); }
    else pw += c;
  });
}

if (cmd === 'add' && user) {
  readPassword(pw => {
    if (!pw) { console.error('빈 비밀번호는 사용할 수 없습니다'); process.exit(1); }
    const salt = crypto.randomBytes(16);
    const hash = crypto.scryptSync(pw, salt, 32);
    const nameIdx = args.indexOf('--name');
    const entry = {
      user,
      name: nameIdx >= 0 ? args[nameIdx + 1] : user,
      ...(args.includes('--admin') ? { admin: true } : {}),
      hash: `scrypt:${salt.toString('base64')}:${hash.toString('base64')}`,
    };
    const users = load().filter(u => u.user !== user);
    users.push(entry);
    save(users);
    console.log(`${entry.admin ? '[admin] ' : ''}${user} 저장됨 → ${USERS_FILE} (총 ${users.length}명)`);
  });
} else if (cmd === 'del' && user) {
  const users = load();
  const next = users.filter(u => u.user !== user);
  if (next.length === users.length) { console.error(`${user}: 없음`); process.exit(1); }
  save(next);
  console.log(`${user} 삭제됨 (총 ${next.length}명)`);
} else if (cmd === 'list') {
  for (const u of load()) console.log(`${u.user}\t${u.name || ''}\t${u.admin ? 'admin' : ''}`);
} else {
  console.error('usage: node userctl.js add <user> [--name "..."] [--admin] | del <user> | list');
  process.exit(2);
}
