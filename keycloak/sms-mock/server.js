// Mock SMS 게이트웨이 — 실제 발송 대신 받은 문자를 메모리에 보관하고 화면/API로 보여준다 (MailHog 의 문자 버전)
//   POST   /send          {"to":"010...","text":"..."}
//   GET    /api/messages  최신순 JSON
//   DELETE /api/messages  전체 삭제
//   GET    /              수신함 화면 (3초마다 새로고침)
const http = require('http');

const PORT = process.env.PORT || 8090;
const messages = [];

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
}

function json(res, status, body) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(body));
}

function inboxPage() {
  const rows = messages
    .map((m) => `<tr><td>${escapeHtml(m.receivedAt)}</td><td>${escapeHtml(m.to)}</td><td>${escapeHtml(m.text)}</td></tr>`)
    .join('');
  return `<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta http-equiv="refresh" content="3">
<title>Mock SMS Inbox</title>
<style>body{font-family:sans-serif;margin:24px}table{border-collapse:collapse;width:100%}
td,th{border:1px solid #ccc;padding:6px 10px;text-align:left}th{background:#f4f4f4}</style></head>
<body><h2>Mock SMS 수신함 (${messages.length}건)</h2>
<p>Keycloak SMS OTP SPI 가 보낸 문자. 실제 휴대폰으로는 발송되지 않습니다.</p>
<table><tr><th>수신 시각</th><th>수신 번호</th><th>내용</th></tr>${rows || '<tr><td colspan="3">없음</td></tr>'}</table>
</body></html>`;
}

http
  .createServer((req, res) => {
    if (req.method === 'POST' && req.url === '/send') {
      let body = '';
      req.on('data', (chunk) => (body += chunk));
      req.on('end', () => {
        try {
          const { to, text } = JSON.parse(body);
          if (!to || !text) return json(res, 400, { error: 'to and text are required' });
          const message = { id: messages.length + 1, to, text, receivedAt: new Date().toISOString() };
          messages.unshift(message);
          console.log(`[sms] to=${to} text=${text}`);
          json(res, 200, { status: 'sent', id: message.id });
        } catch {
          json(res, 400, { error: 'invalid json' });
        }
      });
      return;
    }
    if (req.url === '/api/messages') {
      if (req.method === 'GET') return json(res, 200, messages);
      if (req.method === 'DELETE') {
        messages.length = 0;
        return json(res, 200, { status: 'cleared' });
      }
    }
    if (req.method === 'GET' && req.url === '/') {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      return res.end(inboxPage());
    }
    json(res, 404, { error: 'not found' });
  })
  .listen(PORT, () => console.log(`mock sms gateway listening on ${PORT}`));
