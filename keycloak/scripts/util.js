// 테스트 스크립트 보조 도구 (jq/python 대체)
//   node util.js json <field.path>        stdin JSON에서 필드 추출
//   node util.js jwt <field>              stdin JWT payload 필드 추출
//   node util.js pkce                     "verifier challenge" 출력
//   node util.js totp <rawSecret>         현재 TOTP 6자리 (SHA1, 30초). Keycloak 등록 폼의 hidden totpSecret 값(raw)을 키로 사용
//   node util.js formaction               stdin HTML의 첫 form action (HTML 엔티티 해제)
//   node util.js totpsecret               stdin HTML(OTP 등록 화면)에서 secret 추출
//   node util.js mailcode                 stdin MailHog 메시지 JSON에서 최근 메일의 6자리 코드
//   node util.js smscode                  stdin Mock SMS 메시지 JSON에서 최근 문자의 6자리 코드
const crypto = require('crypto');

const [, , cmd, arg] = process.argv;

function readStdin() {
  return require('fs').readFileSync(0, 'utf8');
}

function pick(obj, path) {
  return path.split('.').reduce((o, k) => (o == null ? undefined : o[k]), obj);
}

function print(v) {
  if (v === undefined || v === null) return;
  process.stdout.write(typeof v === 'object' ? JSON.stringify(v) : String(v));
}

function totp(secret) {
  const counter = Buffer.alloc(8);
  counter.writeBigUInt64BE(BigInt(Math.floor(Date.now() / 1000 / 30)));
  const h = crypto.createHmac('sha1', Buffer.from(secret, 'utf8')).update(counter).digest();
  const o = h[h.length - 1] & 0xf;
  const code = ((h.readUInt32BE(o) & 0x7fffffff) % 1_000_000).toString().padStart(6, '0');
  return code;
}

function decodeEntities(s) {
  return s.replace(/&amp;/g, '&').replace(/&#x2F;/g, '/').replace(/&#47;/g, '/').replace(/&quot;/g, '"');
}

switch (cmd) {
  case 'json': {
    const text = readStdin();
    try {
      print(pick(JSON.parse(text), arg));
    } catch {
      // not JSON
    }
    break;
  }
  case 'jwt': {
    const payload = readStdin().trim().split('.')[1];
    print(pick(JSON.parse(Buffer.from(payload, 'base64url').toString()), arg));
    break;
  }
  case 'pkce': {
    const verifier = crypto.randomBytes(32).toString('base64url');
    const challenge = crypto.createHash('sha256').update(verifier).digest('base64url');
    print(`${verifier} ${challenge}`);
    break;
  }
  case 'totp':
    print(totp(arg));
    break;
  case 'formaction': {
    const m = readStdin().match(/<form[^>]*action="([^"]+)"/);
    if (m) print(decodeEntities(m[1]));
    break;
  }
  case 'totpsecret': {
    const m = readStdin().match(/name="totpSecret" value="([^"]+)"/);
    if (m) print(m[1].trim());
    break;
  }
  case 'mailcode': {
    // stdin: MailHog /api/v2/messages JSON → 가장 최근 메일 본문에서 6자리 코드
    const items = JSON.parse(readStdin()).items || [];
    if (!items.length) break;
    const msg = items[0];
    const parts = (msg.MIME && msg.MIME.Parts && msg.MIME.Parts.length) ? msg.MIME.Parts : [msg.Content];
    for (const p of parts) {
      const enc = ((p.Headers && p.Headers['Content-Transfer-Encoding']) || [''])[0].toLowerCase();
      let body = p.Body || '';
      if (enc === 'base64') body = Buffer.from(body.replace(/\s/g, ''), 'base64').toString('utf8');
      if (enc === 'quoted-printable') body = body.replace(/=\r?\n/g, '').replace(/=([0-9A-F]{2})/gi, (_, h) => String.fromCharCode(parseInt(h, 16)));
      const m = body.match(/\b(\d{6})\b/);
      if (m) { print(m[1]); break; }
    }
    break;
  }
  case 'smscode': {
    // stdin: Mock SMS /api/messages JSON(최신순) → 가장 최근 문자의 6자리 코드
    const [latest] = JSON.parse(readStdin());
    const m = latest && latest.text.match(/\b(\d{6})\b/);
    if (m) print(m[1]);
    break;
  }
  default:
    console.error(`unknown command: ${cmd}`);
    process.exit(1);
}
