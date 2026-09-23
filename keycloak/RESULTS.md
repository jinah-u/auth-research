# Keycloak 실측 결과

`report/report_md.md` 의 6개 비교 항목을 Keycloak 으로 실제 기동해 검증한 결과. SAS 데모와 같은 조건(클라이언트 `demo-client`, Access Token 20초, 기존 MySQL `sas_poc.users`)으로 맞췄다.

- 실행일: 2026-09-23 / Keycloak **26.7.4** (`start-dev`, 전용 PostgreSQL) / Spring Boot 4.1.1 Resource Server
- 전체 결과: **89개 검증 항목 전부 PASS** — 원문은 [`results/`](results/) (T1~T7 각 txt)

| 테스트 | 결과 | 원문 |
|---|---|---|
| T1 인증/인가 + 기존 MySQL 연동 | 12/12 | [T1-auth.txt](results/T1-auth.txt) |
| T2 2FA (TOTP / Email OTP / WebAuthn) | 19/19 | [T2-2fa.txt](results/T2-2fa.txt) |
| T3 refreshToken | 11/11 | [T3-refresh.txt](results/T3-refresh.txt) |
| T4 로그아웃 / 토큰 만료 | 11/11 | [T4-logout.txt](results/T4-logout.txt) |
| T5 세션 강제 종료 + Introspection | 14/14 | [T5-force-logout.txt](results/T5-force-logout.txt) |
| T6 로그인 UI 커스텀 / 외부 배치 | 10/10 | [T6-login-ui.txt](results/T6-login-ui.txt) |
| T7 2FA — SMS(문자) OTP | 12/12 | [T7-sms-otp.txt](results/T7-sms-otp.txt) |

## 구성

```
keycloak/
  docker-compose.yml     keycloak(:8180) + 전용 postgres(:5433) + mailhog(:8025) + sms-mock(:8090)
  realm/demo-realm.json  realm·클라이언트·사용자·SMTP·User Storage 컴포넌트 (자동 import)
  spi/                   User Storage SPI(기존 MySQL) + Email OTP / SMS OTP Authenticator SPI (독립 Gradle 빌드)
  sms-mock/              Mock SMS 게이트웨이 (받은 문자를 화면·API로 보여줌, 실제 발송 없음)
  resource-server/       /api/** = JWT 로컬 검증, /intro/** = Introspection (:18082)
  theme/demo-login/      로그인 테마 커스텀 (keycloak.v2 상속, 문구·CSS)
  frontend/              외부 React 로그인 UI 수동 확인용 (:5181)
  scripts/               T1~T6 테스트 스크립트, run-all.sh, reset.sh
```

### 실행 방법

```bash
docker compose -p sas-poc up -d            # 루트: 기존 MySQL(:3308) — 한글 폴더명이라 -p 필수
cd keycloak/spi && ./gradlew providers     # SPI JAR → spi/build/providers
cd .. && docker compose up -d              # Keycloak
cd resource-server && ./gradlew bootRun    # JDK 21
bash scripts/run-all.sh                    # realm 초기화 + T1~T7, 결과는 results/
```

SMS OTP 브라우저 수동 테스트: `bash scripts/T7-sms-otp.sh --keep` → http://localhost:8180/realms/demo/account 에 `kcuser`/`password` 로그인 → http://localhost:8090 수신함에서 인증번호 확인 후 입력 → 끝나면 `bash scripts/reset.sh`.

## 항목별 결과

### 1. 인증/인가 (T1-1 ~ T1-3)
- Authorization Code + PKCE(S256)로 access/refresh/id token 발급. access token 은 RS256 JWT, `expires_in=20`, `refresh_expires_in=1800`.
- 로그인 후 브라우저 쿠키 (`/realms/demo/` 경로):

  | 쿠키 | HttpOnly | 용도 |
  |---|---|---|
  | `KEYCLOAK_IDENTITY` | Y | SSO 세션 식별(서명된 토큰) |
  | `KEYCLOAK_SESSION` | N | 세션 상태 확인용 (Max-Age 36000) |
  | `AUTH_SESSION_ID` | Y | 로그인 진행 중 인증 세션 |
  | `KC_AUTH_SESSION_HASH` | N | 인증 세션 해시 |
- Resource Server 는 JWKS 로 **로컬 검증** — `/api/hello` 5회 호출 동안 Keycloak 액세스 로그 0건. JWKS 는 처음, 또는 새 `kid` 가 나올 때만 조회한다.

### 1-부속. 기존 MySQL 회원 사용 (T1-4, T1-5) — User Storage SPI 직접 구현
- `sas_poc.users` 의 `user/password`(`{bcrypt}` 해시)로 Keycloak 로그인 성공, 틀린 비밀번호는 거부.
- Keycloak DB `user_entity`·`credential` 에 해당 사용자 행 **0건** — import 없이 매번 MySQL 을 조회한다. Admin Console 에는 `federationLink` 사용자로 조회된다.
- 개발 분량: `user-storage-mysql` Java 5개 파일, 약 280라인. 배포는 SPI JAR 와 `mysql-connector-j`, `jbcrypt` 를 `/opt/keycloak/providers` 에 넣고 재기동.
- **구현 중 겪은 함정** (문서만으로는 예상하기 어려운 부분):
  1. 기존 테이블에 email/firstName/lastName 이 없으면 Keycloak 26 User Profile 이 로그인 직후 `VERIFY_PROFILE`(프로필 입력) 화면을 띄운다. 어댑터에서 값을 채워 넣어야 한다.
  2. 읽기 전용 어댑터(`AbstractUserAdapter`)는 required action 을 추가하거나 제거할 때 `ReadOnlyException` 을 던져 로그인이 실패한다. no-op 으로 재정의해야 한다.
  3. 1과 2 때문에 legacy 사용자는 TOTP 처럼 Keycloak 에 저장해야 하는 자격증명을 쓸 수 없다. 쓰려면 `AbstractUserAdapterFederatedStorage` 로 바꿔 Keycloak DB 에 일부 데이터를 저장하거나, import 방식으로 전환해야 한다.

### 2. 2FA (T2)
- **TOTP**: 코드 없이 Admin 설정만으로 동작한다. `CONFIGURE_TOTP` required action 지정 → 로그인 시 등록 화면 → 이후 로그인마다 OTP 입력. 틀린 코드는 거부. 기본 browser flow 의 `Conditional 2FA` 가 OTP 를 등록한 사용자에게만 적용된다.
- TOTP 를 등록한 사용자는 Direct Grant(ROPC)도 OTP 없이는 `invalid_grant`.
- **Email OTP**: Keycloak 기본 제공 authenticator 가 없다(기본 제공은 `idp-email-verification`, `reset-credential-email` 뿐). Custom Authenticator SPI 로 구현했다(`email-otp`, 5개 파일 약 160라인, FTL 폼 포함).
  - browser flow 를 복사해 Email OTP 단계를 추가하고 `demo-client` 에만 flow override 로 적용 → 기존 MySQL 회원 `user` 로 ID/PW → 메일 수신(MailHog) → 코드 입력 → 토큰 발급. 틀린 코드는 거부.
  - 기동 로그 경고: `email-otp ... is implementing the internal SPI authenticator. This SPI is internal and may change without notice` → Authenticator SPI 는 공식 지원 대상이 아니라 버전을 올릴 때마다 호환성을 확인해야 한다.
- **SMS(문자) OTP (T7)**: 기본 제공이 없어 Custom Authenticator SPI(`sms-otp`)로 구현했다(7개 파일, 약 230라인). 발송은 Mock SMS 게이트웨이(`sms-mock`, :8090)로 한다.
  - 발송 부분은 `SmsSender` 인터페이스로 분리했다. 실제 업체(NHN Cloud, Naver SENS, Twilio 등)를 쓰려면 이 구현체만 바꾸면 된다.
  - 전화번호는 사용자 속성 `phoneNumber` 를 쓴다. Keycloak 26 은 **User Profile 에 선언하지 않은 속성을 저장하지 않으므로** `phoneNumber` 속성을 먼저 선언해야 한다(Admin API `PUT /users/profile`).
  - kcuser 로 ID/PW 를 입력하면 마스킹된 번호(`010-****-5678`)와 함께 입력 화면이 뜨고, Mock 수신함에 문자가 도착한다. 틀린 번호는 거부되고, 올바른 번호를 넣으면 토큰이 발급된다.
  - 번호가 없는 사용자(legacy `user`)는 400 "Cannot login, credential setup required." 로 로그인이 막힌다. 번호를 등록하는 required action(입력 + 인증)은 Keycloak 에 없어 따로 구현해야 한다.
  - 기동 시 Email OTP 와 똑같은 internal SPI 경고가 뜬다.
  - 실제 운영에 필요한 추가 작업: 업체 계약과 발신번호 사전 등록, 건당 비용, 재전송 버튼, 발송 횟수 제한(비용 공격 방지), 번호 등록·변경 required action, 국제번호 형식 처리.
- **WebAuthn / Passkey**: `webauthn-authenticator`, `webauthn-authenticator-passwordless`, `webauthn-register` 모두 기본 제공(존재만 확인, 실제 등록은 브라우저가 필요해 미실시).

### 3. refreshToken (T3)

| 동작 | SAS (기존 실측) | Keycloak (실측) |
|---|---|---|
| `grant_type=refresh_token` 재발급 | 성공 | 성공 |
| 재발급 응답의 refresh_token | 요청과 **동일**(rotate 안 됨) | **매번 새 값** |
| 이전 refresh_token 재사용(기본값) | 가능 | **가능** (`revokeRefreshToken=false` 기본값, 3회 재사용 성공) |
| rotation 강제 | `reuseRefreshTokens=false` | `revokeRefreshToken=true` + `refreshTokenMaxReuse=0` → 이전 토큰 `invalid_grant` ("Maximum allowed refresh token reuse exceeded") |
| 재사용 감지 시 | – | 정상 토큰(RT1)도 거부 ("Session doesn't have required client") — 해당 클라이언트 세션을 끊는다. SSO 세션은 유지 |
| Access Token 만료 후 | 401 → refresh 로 복구 | 401 → refresh 로 복구 (Spring 기본 clock skew 60초 포함 82초 후 401) |

### 4. 로그아웃 / 토큰 만료 (T4)
- RP-Initiated Logout(`/protocol/openid-connect/logout?id_token_hint=...`) → 같은 쿠키로 authorize 하면 로그인 폼이 뜬다(세션 즉시 무효).
- 로그아웃 후 refresh_token → `invalid_grant` ("Session not active").
- 로그아웃 후 기존 access token: **JWT 로컬 검증 `/api` = 200 (계속 통과)**, Introspection `/intro` = 401.
- `/revoke`:
  - **refresh_token 을 revoke 하면 SSO 세션까지 종료된다**(authorize 시 로그인 폼). SAS 는 authorization 레코드만 삭제했다.
  - access_token 을 revoke 하면 Introspection 에서만 거부되고(`/intro` 401), JWT 로컬 검증은 계속 200. 같은 세션의 refresh_token 은 그대로 재발급된다.

### 5. 악의적 세션 강제 종료 (T5)
- Admin REST API:
  - `GET /users/{id}/sessions` 로 세션 목록(IP·클라이언트)을 조회한다.
  - `DELETE /sessions/{sid}` 로 세션 하나를 즉시 종료 → 다음 authorize 는 로그인 폼, refresh 는 `invalid_grant`.
  - `POST /users/{id}/logout` 은 해당 사용자의 모든 세션만 종료한다(다른 사용자 세션은 유지).
  - `POST /logout-all` 은 Realm 전체를 종료하고 `notBefore` 를 갱신한다.
- 강제 종료 후에도 **JWT 로컬 검증 경로는 기존 access token 을 계속 200 으로 통과시킨다**(`logout-all` 의 `notBefore` 도 Spring Resource Server 는 확인하지 않음).
- **Introspection 경로는 강제 종료 직후 401** (`active:false`). SAS 에서는 결론만 확인했던 즉시 차단을 실측했다.
  - 주의: Keycloak 26 은 **introspect 를 호출하는 클라이언트가 토큰 `aud` 에 포함돼야** 한다. 없으면 정상 토큰도 `active:false` 가 된다("Client ... is not in the token audience"). `demo-client` 에 Audience mapper(`resource-server`)를 추가해 해결했다.
- 위 기능은 Admin Console 의 Sessions 화면에서도 제공된다(화면은 수동 확인 대상).

### 6. 로그인 UI 커스텀 / 외부 배치 (T6)
- **Theme 커스텀**: `keycloak.v2` 를 상속해 문구(messages)와 CSS 만 덮어써 반영했다. 로그인 흐름은 동일하다.
- **외부 UI 에서 form POST (SAS 방식)**: **불가**.
  - Keycloak 에는 SAS `loginPage(외부 URL)` 처럼 미인증 사용자를 외부 로그인 페이지로 보내는 설정이 없다.
  - 로그인 처리 URL(`login-actions/authenticate`)을 쓰려면 authorize 때 발급되는 `session_code`·`execution`·`tab_id` 와 `AUTH_SESSION_ID` 쿠키가 필요하다. 둘이 없으면 400("We are sorry...", 로그인 재시작)이 반환된다.
  - 외부 출처는 로그인 페이지를 CORS 로 읽을 수 없어 이 값을 얻을 방법도 없다.
- **대안 — Direct Access Grant(ROPC)**: 토큰 발급은 가능하다. 다만 다음 제약이 있다.
  - 브라우저에 SSO 쿠키가 생기지 않아 SSO 가 되지 않는다.
  - 2FA·required action 을 외부 UI 가 직접 처리해야 한다. OTP 를 등록한 사용자는 OTP 없이 거부된다.
  - 외부 출처에서 호출하려면 `webOrigins` 등록이 필요하고, confidential client 의 secret 이 브라우저에 노출된다.
  - OAuth 2.1 에서 제거된 grant 이다.
- **React 로 로그인 화면 제작**: Keycloakify 등으로 React 화면을 "테마"로 빌드해 Keycloak 이 서빙하게 하는 방식은 가능하다(문서 기준, 미실시). 이 경우에도 인증은 Keycloak 이 수행한다.

## 보고서 반영 요약 (Keycloak 열)
| 항목 | 이전(문서 기준) | 실측 결과 |
|---|---|---|
| 1-부속 기존 MySQL | SPI 개발 필요 | ✅ SPI 로 가능 · 테스트 완료 (약 280라인 + User Profile/ReadOnly 함정, legacy 사용자는 TOTP 불가) |
| 2. 2FA | TOTP/WebAuthn 기본, SMS/Email 은 SPI | ✅ TOTP 설정만으로 동작 · Email OTP / SMS OTP(Mock 발송) SPI 구현 완료 (internal SPI 경고) |
| 3. refresh | 설정에 따라 rotation | ✅ 기본은 새 토큰 발급 + 이전 토큰 재사용 가능, rotation 설정 시 재사용 감지 |
| 4. 로그아웃 | 문서 기준 | ✅ 세션·refresh 즉시 무효, JWT access token 은 계속 통과 |
| 5. 강제 종료 | 문서 기준 | ✅ Admin API 로 세션/사용자/Realm 단위 종료 · Introspection 즉시 차단 실측 |
| 6. 외부 로그인 UI | 테스트 필요 | ⚠️ form POST 방식 불가 · ROPC 만 가능(비권장) · Theme 커스텀은 가능 |
