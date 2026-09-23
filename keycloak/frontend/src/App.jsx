import { useState } from 'react';

const KC = 'http://localhost:8180/realms/demo';

// T6-2/T6-3 수동 확인용: Keycloak 과 별도 출처(:5181)에 배포된 로그인 UI 에서 할 수 있는 것/없는 것
export default function App() {
  const [result, setResult] = useState('');

  async function directGrant(e) {
    e.preventDefault();
    const form = new FormData(e.target);
    const body = new URLSearchParams({
      grant_type: 'password',
      client_id: 'demo-client',
      client_secret: 'secret', // 브라우저에 secret 이 노출되는 구조 자체가 문제 (confidential client 부적합)
      username: form.get('username'),
      password: form.get('password'),
    });
    try {
      const res = await fetch(`${KC}/protocol/openid-connect/token`, { method: 'POST', body });
      setResult(`HTTP ${res.status}\n${await res.text()}`);
    } catch (err) {
      setResult(`fetch 실패 (CORS 차단 예상): ${err}`);
    }
  }

  return (
    <div style={{ maxWidth: 420, margin: '60px auto', fontFamily: 'sans-serif' }}>
      <h2>외부 로그인 UI (React, :5181) → Keycloak</h2>

      <h3>A. native form POST (SAS 방식 재현)</h3>
      <p style={{ fontSize: 14, color: '#555' }}>
        Keycloak 로그인 처리 URL 은 authorize 시 발급되는 session_code·execution·tab_id 와 인증 세션 쿠키가
        필요해 외부 페이지가 알 수 없습니다. 제출하면 오류 페이지가 표시됩니다.
      </p>
      <form method="POST" action={`${KC}/login-actions/authenticate?client_id=demo-client`}>
        <input name="username" defaultValue="kcuser" />
        <input name="password" type="password" defaultValue="password" />
        <button type="submit">Sign in (form POST)</button>
      </form>

      <h3>B. Direct Access Grant (ROPC, fetch)</h3>
      <p style={{ fontSize: 14, color: '#555' }}>
        토큰은 받을 수 있지만 SSO 세션 쿠키가 생기지 않고, 2FA·required action 을 직접 처리해야 하며,
        OAuth 2.1 에서 제거된 grant 입니다.
      </p>
      <form onSubmit={directGrant}>
        <input name="username" defaultValue="kcuser" />
        <input name="password" type="password" defaultValue="password" />
        <button type="submit">Sign in (ROPC)</button>
      </form>
      <pre style={{ whiteSpace: 'pre-wrap', background: '#f4f4f4', padding: 8 }}>{result}</pre>
    </div>
  );
}
