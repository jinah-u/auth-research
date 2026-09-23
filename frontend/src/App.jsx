export default function App() {
  return (
    <div style={{ maxWidth: 360, margin: '80px auto', fontFamily: 'sans-serif' }}>
      <h2>외부 로그인 UI (React, :5180)</h2>
      <p style={{ fontSize: 14, color: '#555' }}>
        이 화면은 auth-server(:9000)와 별도로 배포된 프론트엔드입니다. 폼 제출(native form POST)로
        auth-server의 <code>/login</code>에 직접 요청을 보냅니다.
      </p>
      <form method="POST" action="http://localhost:9000/login">
        <div style={{ marginBottom: 12 }}>
          <label>
            Username
            <br />
            <input name="username" defaultValue="user" style={{ width: '100%' }} />
          </label>
        </div>
        <div style={{ marginBottom: 12 }}>
          <label>
            Password
            <br />
            <input name="password" type="password" defaultValue="password" style={{ width: '100%' }} />
          </label>
        </div>
        <button type="submit">Sign in</button>
      </form>
    </div>
  );
}
