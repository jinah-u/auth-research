****

- **1안 — 자체 JWT**: 인증서버를 직접 구현 (JWT 발급/검증, Refresh Token 등 전부 직접 설계)
- **2안 — Spring Authorization Server (SAS)**: Boot 4.1 + Gateway + Resource Server 데모 환경에서 아래 6개 항목 전부 실제로 기동/테스트 완료
- **3안 — Keycloak**: Keycloak 26.7.4 데모 환경(`keycloak/`)에서 같은 6개 항목 실측 완료 — 자동화 스크립트 77개 검증 항목 전부 통과 (상세: `keycloak/RESULTS.md`)

---

## 0. 개요 및 요약

| 구분 | 자체 JWT | Spring Authorization Server | Keycloak |
| --- | --- | --- | --- |
| 성격 | 인증서버를 처음부터 직접 개발 | Spring Security에 내장된 OAuth2/OIDC 인증서버 프레임워크 | 별도 제품(오픈소스 IAM 솔루션) |
| 구현 부담 | 인증/세션/토큰 정책 전부 직접 설계·구현 | 중간 — 프레임워크가 프로토콜을 제공, 세부 정책은 커스텀 필요 | 대부분 기능이 관리 콘솔/설정으로 제공 |
| 관리 UI(사용자·세션 관리 등) | 직접 구현 필요 | 직접 구현 필요 | Admin Console 기본 제공 |
| 검증 상태 | 이벤트유 코드 및 조사 | 데모 환경에서 테스트 완료 | 데모 환경에서 테스트 완료 (SPI 2종 직접 구현 포함) |

> 🟢 **가능** / 🟡 **조건부 또는 추가 구현 필요** / 🔴 **불가**

| 항목 | 1안 자체 JWT | 2안 Spring Authorization Server | 3안 Keycloak |
| --- | --- | --- | --- |
| **1. 인증/인가 방식** | JWT를 클라이언트가 보관하고 Bearer로 전달 | OAuth2 Code + BFF 세션 쿠키 `✓ 테스트 완료` | OAuth2 Code + BFF 세션 쿠키 `✓ 테스트 완료` |
| **-회원 정보 MySQL** | 🟢 기존 테이블 그대로 사용 | 🟢 기존 테이블 연동 `✓ 테스트 완료` | 🟡 User Storage SPI 직접 구현으로 연동 (약 280라인) `✓ 테스트 완료` |
| **2. 2FA 커스텀** | 🟢 전부 직접 구현 | 🟢 MFA 프레임워크 내장 `✓ 테스트 완료` | 🟢 TOTP는 설정만으로 동작, Email OTP는 SPI 구현 `✓ 테스트 완료` |
| **3. refreshToken** | 🟢 정책 직접 설계 | 🟢 기본 재사용, 설정으로 Rotation `✓ 테스트 완료` | 🟢 기본은 새 RT 발급 + 이전 RT 재사용 가능, 설정으로 Rotation `✓ 테스트 완료` |
| **4. 로그아웃/만료** | 🟢 직접 구현 (JWT는 exp까지 유효) | 🟢 세션·RT 폐기 (JWT는 exp까지 유효) `✓ 테스트 완료` | 🟢 Logout·Revoke로 세션·RT 폐기 (JWT는 exp까지 유효) `✓ 테스트 완료` |
| **5. 강제 세션 종료** | 🟡 RT 삭제·블랙리스트 직접 구현 | 🟡 세션·RT 즉시 차단, 발급된 JWT는 차단 불가 `✓ 테스트 완료` | 🟡 Admin API/Console로 세션 종료, JWT 한계 동일 (Introspection 시 즉시 차단) `✓ 테스트 완료` |
| **6. 로그인 UI 외부 배치** | 🟢 자유롭게 구성 | 🟢 외부 React 로그인 화면 `✓ 테스트 완료` | 🟡 Theme 커스텀만 가능, 외부 form POST 불가 (ROPC만 가능·비권장) `✓ 테스트 완료` |

---

## 1. 인증/인가 방식 (토큰 / 세션 / 쿠키)

### 1-1. 비교 요약

| 구분 | 자체 JWT | Spring Authorization Server | Keycloak |
| --- | --- | --- | --- |
| 로그인 상태 유지 | 세션 또는 토큰 중 직접 선택·설계 | 인증서버는 Spring Security 세션, Gateway(BFF)는 별도 `HttpSession` | Keycloak 자체 사용자 세션, Gateway(BFF)는 별도 `HttpSession` |
| 브라우저 → 인증서버 쿠키 | 직접 설계 | 인증서버 로그인 세션 쿠키 | Keycloak 세션 쿠키 — ✅ **테스트 완료** (`KEYCLOAK_IDENTITY`·`AUTH_SESSION_ID`는 HttpOnly, `KEYCLOAK_SESSION`·`KC_AUTH_SESSION_HASH`는 non-HttpOnly) |
| 브라우저 → Gateway 쿠키 | 직접 설계(세션 ID or 없음) | Gateway 세션 ID (BFF 구조) | Gateway 세션 ID (BFF 구조) |
| Access Token 종류 | JWT 직접 생성 | JWT 또는 Opaque Token 선택 가능 | 일반적으로 JWT |
| Access Token 검증 | 각 서비스가 서명/만료 직접 검증하도록 구성 | Resource Server가 JWK 공개키로 
로컬 검증(매 요청마다 인증서버 조회 불필요) | Resource Server가 Keycloak 공개키로 로컬 검증 — ✅ **테스트 완료** (API 5회 호출 중 Keycloak 조회 0건) |
| Refresh Token | 필요 시 직접 구현(저장/만료/재발급/폐기 정책 전부 설계) | 선택적 발급, Authorization Server 내부 저장소로 관리 | 기본 발급, Keycloak이 세션과 연동해 관리 |

### 1-2. 최초 로그인 및 토큰 발급 흐름

**자체 JWT (토큰 방식)**

```mermaid
sequenceDiagram
    participant B as 브라우저/앱
    participant A as 자체 인증 서버
    participant G as Gateway
    participant R as Resource Server

    B->>A: ID/PW 로그인
    A-->>B: Access Token + Refresh Token 발급
    B->>G: API 요청 (Authorization: Bearer Access Token)
    G->>R: Access Token 전달
    R-->>R: 서명/만료시간 직접 검증
    R-->>G: 응답
    G-->>B: 응답
```

**Spring Authorization Server** — ✅ 테스트 완료 (Authorization Code + PKCE 흐름으로 실제 토큰 발급까지 확인) / **Keycloak** 도 동일 — ✅ 테스트 완료 (`/protocol/openid-connect/auth`·`/token`, PKCE S256)

```mermaid
sequenceDiagram
    participant B as 브라우저
    participant G as Gateway (BFF)
    participant AS as Spring Authorization Server
    participant R as Resource Server

    B->>G: 서비스 접근
    G->>AS: Authorization 요청 (/oauth2/authorize)
    AS-->>B: 미인증 시 로그인 폼
    B->>AS: ID/PW 제출
    AS-->>AS: 인증서버 로그인 세션 생성
    AS-->>B: 302 Redirect + Authorization Code
    B->>G: Authorization Code 전달
    G->>AS: POST /oauth2/token (code)
    AS-->>G: Access Token + Refresh Token
    G-->>G: HttpSession에 OAuth2AuthorizedClient로 보관
    AS-->>B: Gateway 세션 ID 쿠키 발급
    Note over B,R: 이후 API 요청
    B->>G: Cookie: Gateway Session ID
    G->>R: Authorization: Bearer Access Token
    R-->>R: JWK로 서명/exp 로컬 검증(인증서버 재조회 없음)
    R-->>G: 응답
    G-->>B: 응답
```

### 1-3. 회원 정보 보관 위치 (기존 MySQL 사용 가능 여부)

| 구분 | 자체 JWT | Spring Authorization Server | Keycloak |
| --- | --- | --- | --- |
| 기존 MySQL 회원 테이블 사용 | 가능 | 가능 — ✅ **테스트 완료** | 가능 (SPI 직접 구현 시) — ✅ **테스트 완료** (`sas_poc.users`의 bcrypt 비밀번호로 로그인, Keycloak DB에는 사용자·비밀번호 미저장) |
| 인증서버 전용 DB 필요 여부 | 불필요(직접 설계) | 불필요 (OAuth2 Client/Authorization/Consent 데이터도 
JDBC로 저장 가능) | 필요 (Keycloak이 관리하는 사용자·인증 정보는 
Keycloak DB에 저장) |
| 기존 MySQL 연동 방법 | 해당 없음(자체 설계) | 기존 회원 테이블을 Spring Security 인증과 그대로 연결 | `User Storage SPI` 직접 구현 (Java 5개 파일 약 280라인 + JDBC 드라이버·bcrypt JAR 배포)
— 함정: 기존 테이블에 email/이름이 없으면 User Profile 검증 화면이 뜨고, 읽기 전용 어댑터는 required action 처리에서 로그인 실패 → 어댑터에서 보완 필요. legacy 사용자는 TOTP 등록 불가(저장 공간 없음) |

---

## 2. 인증 절차 커스텀 (2FA)

| 구분 | 자체 JWT | Spring Authorization Server | Keycloak |
| --- | --- | --- | --- |
| 2FA 가능 여부 | 가능 (전부 직접 구현) | 가능 — ✅ **테스트 완료** (완성된 기능은 아니지만 
Spring Security 7.1 공식 MFA 프레임워크로 구현) | 가능 — ✅ **테스트 완료** (Authentication Flow 설정 + 클라이언트별 flow override) |
| TOTP / WebAuthn·Passkey | 직접 구현 | 직접 연동 구현 필요 | 기본 제공 — ✅ **테스트 완료** (TOTP: 코드 없이 required action만 지정해 등록·로그인·오입력 거부 확인, ROPC도 OTP 없으면 거부 / WebAuthn·Passkey: provider 존재만 확인) |
| SMS OTP / Email OTP | 직접 구현 | 직접 연동 구현
(발송 채널 커스텀 핸들러) | 기본 미제공 — ✅ **테스트 완료** (Email OTP를 Custom Authenticator SPI로 구현, 5개 파일 약 160라인. 기존 MySQL 회원으로 메일 코드 로그인 성공.
단, Authenticator SPI는 Keycloak이 “internal SPI, 예고 없이 변경될 수 있음” 경고를 출력 → 버전 업그레이드 시 재검증 필요) |

---

## 3. refreshToken 동작 방식

| 구분 | 자체 JWT | Spring Authorization Server | Keycloak |
| --- | --- | --- | --- |
| 저장 위치 | 직접 설계(DB/Redis 등) | Authorization Server 내부 저장소(JDBC 등으로 구성 가능) | Keycloak 세션 및 내부 저장소 |
| 재발급 방식 | 직접 설계 | `grant_type=refresh_token`으로 
Access Token만 새로 발급 — ✅ **테스트 완료** | `grant_type=refresh_token`으로 재발급 — ✅ **테스트 완료** (응답에 **새 refresh_token**도 함께 발급) |
| Rotation 기본값 | 직접 설계(정책 자유) | 기본값 `reuseRefreshTokens=true` 
→ **rotate 되지 않고 재사용됨** — ✅ **테스트 완료**
(같은 refresh_token으로 반복 갱신해도 계속 성공) | 기본값 `revokeRefreshToken=false` → 새 값이 오지만 **이전 refresh_token도 계속 재사용 가능** — ✅ **테스트 완료**
`revokeRefreshToken=true`로 바꾸면 이전 토큰 재사용 시 `invalid_grant`, 재사용이 감지되면 정상 토큰까지 해당 클라이언트 세션이 끊김 — ✅ **테스트 완료** |
| 만료 시 동작 | 직접 설계 | Refresh Token까지 만료되면 재발급 불가 → 재로그인 필요 | Refresh Token/세션 상태에 따라 재발급 불가 → 재로그인 필요 |
| 기본 TTL | 직접 설계 | 문서 기준 60분  | Realm 설정 (SSO Session Idle 기본 30분 → 실측 `refresh_expires_in=1800`) |

```mermaid
sequenceDiagram
    participant C as Client / Gateway
    participant AS as 인증서버(자체 JWT / SAS / Keycloak)
    participant R as Resource Server

    C->>R: API 요청 (Access Token)
    R-->>C: 401 (Access Token 만료)
    C->>AS: POST /token (grant_type=refresh_token)
    AS-->>C: 새 Access Token 발급
    Note over AS,C: SAS 실측: 기본값에서는 응답의 refresh_token이<br/>요청과 동일(rotate 안 됨) — 같은 값으로 재사용 가능<br/>Keycloak 실측: 매번 새 refresh_token 발급, 기본값에선 이전 값도 재사용 가능
    C->>R: API 요청 (새 Access Token)
    R-->>C: 200 OK
    Note over C,AS: Refresh Token까지 만료 시 재로그인 필요
```

---

## 4. 로그아웃 / 토큰 만료

| 구분 | 자체 JWT | Spring Authorization Server | Keycloak |
| --- | --- | --- | --- |
| 로그아웃 처리 주체 | 직접 구현 | Spring Security 로그아웃 기능(세션/`SecurityContext` 정리) | Keycloak Logout Endpoint (RP-Initiated Logout 등 OIDC 표준 메커니즘 지원) |
| 세션 즉시 무효화 | 가능 (세션 방식 채택 시) | 가능 — ✅ **테스트 완료** (로그아웃 후 동일 쿠키 요청 시 
즉시 재로그인 페이지로 이동 확인) | 가능 — ✅ **테스트 완료** (RP-Initiated Logout 후 동일 쿠키로 authorize 시 즉시 로그인 폼, refresh는 `Session not active`) |
| 이미 발급된 
JWT Access Token 즉시 폐기 | **불가** — Stateless 검증 구조라면 별도 Blacklist 구현 필요 | **불가** — ✅ **테스트 완료** (`/oauth2/revoke` 호출 후에도 
동일 Access Token이 Resource Server를 계속 통과함) | **불가** — ✅ **테스트 완료** (로그아웃·access_token revoke 후에도 JWT 로컬 검증 경로는 계속 200.
Introspection 경로에서만 즉시 401) |
| Refresh Token 폐기 | 가능 (저장소에서 직접 삭제 시) | 가능 — ✅ **테스트 완료** (revoke 직후 해당 refresh_token으로 
재발급 시도 시 즉시 `invalid_grant`) | 가능 — ✅ **테스트 완료** (`/revoke` 직후 `invalid_grant`. SAS와 달리 **refresh_token revoke 시 SSO 세션까지 종료**) |
| Access Token 자연 만료 | 직접 설계한 `exp`/정책에 따름 | `exp` 클레임 기준 자연 만료 (기본 60초 clock-skew 존재) | `Access Token Lifespan` 설정으로 수명 관리 — ✅ **테스트 완료** (20초 설정, Spring clock-skew 60초 포함 후 401 → refresh로 복구) |

```mermaid
flowchart TD
    Logout[로그아웃 요청] --> Type{인증 방식}
    Type -->|세션 방식| S1[서버 세션 즉시 삭제]
    S1 --> S2[다음 요청부터 즉시 차단]
    Type -->|JWT/토큰 방식| T1[Refresh Token 폐기]
    T1 --> T2[추가 Access Token 발급 차단]
    Type -->|JWT/토큰 방식| T3["이미 발급된 Access Token"]
    T3 --> T4["exp까지 계속 유효 (즉시 차단 불가, 3안 공통)"]
```

**핵심 공통 결론**:
3안 모두 JWT를 로컬(Stateless)로 검증하는 한, 로그아웃/Revoke만으로는 이미 클라이언트에 나가 있는 Access Token 자체를 즉시 무효화할 수 없다.
즉시 차단이 꼭 필요하면 Access Token TTL을 짧게 유지하거나, Opaque Token + Introspection 구조로 전환해야 한다.

- Introspection 구조 - Resource Server가 인증서버에 상태를 조회하는 방식. Spring Authorization Server, Keycloak 모두 Endpoint 제공

---

## 5. 악의적 세션 강제 종료

| 강제 종료 대상 | 자체 JWT | Spring Authorization Server | Keycloak |
| --- | --- | --- | --- |
| 인증서버/Gateway 사용자 세션 종료 | 가능 (직접 구현) | 가능 — ✅ **테스트 완료** (Redis에서 세션 키 삭제 
→ 다음 요청부터 즉시 로그인 페이지로 이동) | 가능 — ✅ **테스트 완료** (Admin REST API로 세션 목록(IP·클라이언트) 조회 →
`DELETE /sessions/{id}` 직후 로그인 폼) |
| Refresh Token 추가 사용 차단 | 가능 (직접 구현) | 가능 — ✅ **테스트 완료** (DB 레코드 삭제 직후 
refresh 시도 시 즉시 `invalid_grant`) | 가능 — ✅ **테스트 완료** (세션 강제 종료 직후 refresh 시 `invalid_grant`) |
| 이미 발급된 JWT Access Token 즉시 차단 | **불가** (Blacklist 등 별도 구현 없이는 불가) | **불가** — ✅ **테스트 완료** (세션/인가 레코드를 지워도, 
기존 Access Token은 계속 200 통과.
Resource Server가 로컬 서명 검증만 수행하고
인증서버 상태를 조회하지 않기 때문) | **불가** — ✅ **테스트 완료** (세션 강제 종료·`logout-all` 후에도 기존 Access Token은 JWT 경로에서 계속 200. `logout-all`이 갱신하는 `notBefore`도 Spring Resource Server는 확인하지 않음) |
| Introspection 방식 전환 시 즉시 차단 | 가능 (직접 구현 시) | 가능 — Resource Server를 Opaque Token
+ Introspection 구조로 전환 시 revoke 직후 즉시 차단(미구현, 결론만 확인) | 가능 — ✅ **테스트 완료** (같은 토큰을 Introspection 경로로 검증하면 강제 종료 직후 401, `active:false`.
단 Keycloak 26은 introspect 호출 클라이언트가 토큰 `aud`에 있어야 함 → Audience mapper 설정 필요) |
  | 사용자 세션 관리 UI | 직접 구현 필요 | 직접 구현 필요 | **Admin Console 기본 제공** |
  | Realm/전체 단위 강제 종료 | 직접 구현 필요 | 직접 구현 필요 | 기본 제공 — ✅ **테스트 완료** (`POST /users/{id}/logout`: 해당 사용자 전 세션만 종료, `POST /logout-all`: Realm 전체 종료) |

**핵심 공통 결론**:  Keycloak은 이 강제 종료 작업을 위한 **관리 UI(Admin Console)를 기본 제공**한다는 점이 자체 JWT·SAS(둘 다 직접 구현 필요) 대비 뚜렷한 차별점

---

## 6. 로그인 UI 커스텀 / 외부 배치

| 구분 | 자체 JWT | Spring Authorization Server | Keycloak |
| --- | --- | --- | --- |
| 인증서버 내부 UI 커스텀 | 자유 (직접 개발) | 가능 — ✅ **테스트 완료** 
(`formLogin().loginPage(...)`로 자체 로그인 화면 교체) | 가능 — ✅ **테스트 완료** (`keycloak.v2` 테마 상속, 문구·CSS 덮어쓰기 반영. React 화면도 Keycloakify로 테마 빌드 시 가능 — 문서 기준) |
| 외부(React 등) UI 배치 | 자유 (직접 개발, 제약 없음) | 가능 — ✅ **테스트 완료** 
(`loginPage(외부 URL)`은 공식 지원 확장 ) | **SAS 방식(외부 form POST)은 불가** — ✅ **테스트 완료**
(외부 로그인 URL로 redirect하는 설정이 없고, 로그인 처리 URL은 `session_code`·`tab_id`와 `AUTH_SESSION_ID` 쿠키가 없으면 400. 외부 출처는 CORS로 이 값을 읽을 수 없음)
대안인 ROPC(`grant_type=password`)는 토큰 발급은 되지만 SSO 쿠키 없음·2FA 직접 처리·client secret 노출·OAuth 2.1 제외로 비권장 |
| 실제 인증 처리 주체 | 자체 인증 서버 | 로그인 UI 위치와 무관하게 
Authorization Server의 Spring Security가 인증 수행 | 기본 구조에서는 Keycloak이 로그인 화면과 인증을 모두 담당 |
| OAuth2 흐름 | 해당 없음(자체 프로토콜) | 로그인 UI 위치와 무관하게 
기존 `Authorization Code → Token` 흐름 유지 | Keycloak 로그인 완료 후 기존 `Authorization Code → Token` 흐름 유지 |
| 비고 |  | `<form method="POST">`로 인증서버 `/login`에 직접 제출하는 방식은 
전체 페이지 이동이라 **CORS 설정이 불필요**하나,
`POST /login`에 대한 CSRF 예외 처리는 필요 | 외부 UI에서 ID/PW를 직접 받아 Keycloak에 인증시키는 구조는
기본 Theme 방식이 아니며,
별도 인증 연동 방식이나 Keycloak 확장 구현 검토가 필요 |

### Spring Authorization Server 테스트

```mermaid
sequenceDiagram
    participant B as 브라우저
    participant AS as Spring Authorization Server
    participant EX as 외부 로그인 UI (예: React)
    participant G as Gateway

    B->>AS: GET /oauth2/authorize (미인증)
    AS-->>B: 302 Redirect → 외부 로그인 UI
    B->>EX: 로그인 페이지 진입
    EX->>AS: POST /login (ID/PW, 네이티브 form 전송)
    Note over EX,AS: 전체 페이지 이동(top-level navigation)이라<br/>CORS 설정 불필요 / CSRF는 별도 예외처리 필요
    AS-->>AS: Spring Security 인증, 인증 세션 생성
    AS-->>B: 302 Redirect → 원래 /oauth2/authorize 요청으로 복귀
    B->>G: Authorization Code 전달
    G->>AS: Code → Token 교환
    AS-->>G: Access Token (+ Refresh Token)
```

---

## 7. 종합 비교 요약 및 결론

| 항목 | 자체 JWT | Spring Authorization Server | Keycloak |
| --- | --- | --- | --- |
| 1. 인증/인가 방식 (토큰/세션/쿠키) | ✅ 가능 (설계 수준) | ✅ 가능 · 테스트 완료 | ✅ 가능 · 테스트 완료 |
| 1-부속. 기존 MySQL 회원정보 사용 | ✅ 가능 | ✅ 가능 · 테스트 완료 | ⚠️ SPI 직접 구현으로 가능 · 테스트 완료 (legacy 사용자는 TOTP 불가) |
| 2. 2FA 커스텀 | ✅ 가능 (전부 직접 구현) | ✅ 가능 · 테스트 완료 | ✅ 가능 · 테스트 완료 (TOTP 설정만으로, Email OTP는 SPI 구현) |
| 3. refreshToken 동작 | ✅ 가능 (설계 수준) | ✅ 가능 · 테스트 완료 | ✅ 가능 · 테스트 완료 |
| 4. 로그아웃/토큰 만료 | ✅ 가능하나 
JWT 즉시폐기는 ❌ 구조적 불가 | ✅ 가능 · 테스트 완료 
(JWT 즉시폐기는 ❌ 구조적 불가) | ✅ 가능 · 테스트 완료 
(JWT 즉시폐기는 ❌ 구조적 불가) |
| 5. 악의적 세션 강제 종료 | ⚠️ 전부 직접 구현(관리 UI 없음) | ⚠️ 가능하나 관리 UI 직접 구현 필요 · 테스트 완료 | ✅ Admin Console/API 기본 제공 · 테스트 완료 (Introspection 즉시 차단 실측) |
| 6. 로그인 UI 외부 배치 | ✅ 자유 (직접 개발) | ✅ 가능 · 테스트 완료 | ⚠️ Theme 커스텀만 가능, 외부 form POST 불가 · 테스트 완료 |

**트레이드오프 정리**

- **자체 JWT**: 설계 자유도가 가장 높지만, 인증/세션/토큰 정책·강제 종료·관리 UI 등 모든 것을 직접 구현해야 하는 부담이 가장 크다.
- **Spring Authorization Server**: Spring 생태계와 자연스럽게 통합되며, 이번 조사의 6개 항목 전부를 실제 데모로 직접 검증했다는 점이 가장 큰 강점이다. 다만 사용자 세션 관리 UI, 강제 종료 등 운영 편의 기능은 여전히 직접 구현해야 한다.
- **Keycloak**: 관리 콘솔, 세션 관리, 2FA(TOTP/WebAuthn), Introspection 등 운영에 필요한 기능을 제품 차원에서 폭넓게 제공한다. 다만 전용 DB·별도 인프라가 필요하다. 실측 결과 기존 MySQL 연동과 Email OTP는 SPI 직접 구현(합계 약 440라인)으로 가능했지만 User Profile·읽기 전용 제약 같은 함정이 있었고, Authenticator SPI는 internal SPI라 버전마다 재검증이 필요하다. 외부 로그인 UI(SAS 방식의 외부 form POST)는 구조적으로 불가하며, Theme 커스텀(또는 Keycloakify로 React 테마 빌드)으로 대체해야 한다.