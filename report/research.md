# 1. 인증/인가 방식

### 자체 로그인

- **로그인 상태 유지:** 세션 또는 토큰 방식으로 직접 설계 가능
- **세션 방식:** 서버에 로그인 상태를 저장하고 브라우저는 세션 ID를 쿠키로 전달
- **토큰 방식:** 로그인 성공 시 자체 `Access Token`을 발급하고 클라이언트가 API 요청마다 전달
- **Access Token:** JWT 등을 직접 생성하여 사용 가능
- **JWT 검증:** 각 서비스에서 서명, 만료시간 등을 검증하도록 구성 가능
- **Refresh Token:** 필요 시 직접 구현. 저장·만료·재발급·Rotation·폐기 정책 등을 직접 설계
- **저장 방식:** Access/Refresh Token의 클라이언트 보관 및 Redis/DB 등 서버 측 저장 여부를 직접 설계

**토큰 방식 사용 시**

```
브라우저 / 앱
   │ ID/PW 로그인
   ▼
자체 인증 서버
   │
   ├─ Access Token
   └─ Refresh Token
           │
           ▼
      브라우저 / 앱
           │
           │ Access Token
           ▼
        Gateway
           │
           │ Access Token
           ▼
     Resource Server
```

---

#### 로그인 이후 API 요청

```
브라우저
   │
   │ Cookie: Gateway Session ID
   ▼
Gateway
   │
   ├─ HttpSession 조회
   │
   └─ OAuth2AuthorizedClient
          └─ Access Token
                  │
                  │ Authorization:
                  │ Bearer <Access Token>
                  ▼
           Resource Server
```

### Spring Authorization Server

- **인증서버 로그인 상태:** Spring Security의 세션을 이용해 사용자 로그인 상태 유지
- **인증서버 쿠키:** 브라우저는 인증서버의 세션 ID를 쿠키로 전달하고, 인증서버는 이를 통해 기존 로그인 상태 확인
- **Authorization Code:** 인증 완료 후 브라우저를 Gateway의 `redirect_uri`로 `302 Redirect`하면서 일회성 Code 전달
- **Access Token 발급:** Gateway가 Code를 Authorization Server의 Token Endpoint로 전달하여 Access Token으로 교환
- **Gateway 로그인 상태:** BFF 구조에서는 Gateway도 별도의 `HttpSession`을 생성하고 브라우저에는 Gateway 세션 ID만 쿠키로 전달
- **토큰 보관:** Gateway가 발급받은 Access/Refresh Token을 `OAuth2AuthorizedClient`로 관리하고 `HttpSession`에 연결하여 보관 가능
- **세션 저장:** Gateway의 `HttpSession`은 Spring Session + Redis를 적용하여 여러 Gateway 인스턴스가 공유하도록 구성 가능
- **API 인가:** Gateway가 Access Token을 `Authorization: Bearer` 헤더로 Resource Server에 전달
- **Access Token:** JWT 또는 Opaque Token 사용 가능
- **JWT 검증:** Resource Server가 JWK 공개키로 서명·만료시간 등을 검증할 수 있어 매 요청마다 Authorization Server 조회가 필요하지 않음
- **Refresh Token:** 선택적으로 발급하며 Access Token 만료 시 새로운 Access Token 발급에 사용

#### 최초 로그인 및 토큰 발급

```
브라우저
   │
   ▼
Gateway
   │ Authorization 요청
   ▼
Spring Authorization Server
   │
   │ 사용자 인증
   ├─ 인증서버 로그인 세션 생성
   └─ 인증서버 세션 ID를 Cookie로 전달
   │
   └─ 302 Redirect + Authorization Code
              │
              ▼
           브라우저
              │ Code 전달
              ▼
           Gateway
              │
              │ POST /oauth2/token
              │ code=xxx
              ▼
Spring Authorization Server
              │
              ├─ Access Token
              └─ Refresh Token
                      │
                      ▼
                   Gateway
                      │
                      └─ HttpSession
                           └─ OAuth2AuthorizedClient
                                ├─ Access Token
                                └─ Refresh Token
                      │
                      └─ Gateway 세션 ID를
                         브라우저 Cookie로 전달
```

#### 로그인 이후 API 요청

```
브라우저
   │
   │ Cookie: Gateway Session ID
   ▼
Gateway
   │
   ├─ HttpSession 조회
   │
   └─ OAuth2AuthorizedClient
          └─ Access Token
                  │
                  │ Authorization:
                  │ Bearer <Access Token>
                  ▼
           Resource Server
                  │
                  ├─ JWT 서명 검증
                  ├─ exp 등 Claim 검증
                  └─ scope/authority 기반 인가
```

Gateway가 여러 대라면 세션을 다음과 같이 공유할 수도 있음.

```
Gateway Pod 1 ─┐
               │
Gateway Pod 2 ─┼─→ Spring Session → Redis
               │                       │
Gateway Pod 3 ─┘                       └─ HttpSession 데이터
                                           └─ OAuth2AuthorizedClient
                                                ├─ Access Token
                                                └─ Refresh Token
```

---

### Keycloak

- **인증서버 로그인 상태:** Keycloak 자체 사용자 세션으로 로그인 상태 유지
- **인증서버 쿠키:** 브라우저는 Keycloak의 세션 쿠키를 전달하고, Keycloak은 이를 통해 기존 로그인 상태 확인
- **Authorization Code:** 인증 완료 후 브라우저를 Gateway의 `redirect_uri`로 `302 Redirect`하면서 일회성 Code 전달
- **Access Token 발급:** Gateway가 Code를 Keycloak Token Endpoint로 전달하여 Access Token으로 교환
- **Gateway 로그인 상태:** BFF 구조에서는 Gateway도 별도의 `HttpSession`을 생성하고 브라우저에는 Gateway 세션 ID만 쿠키로 전달
- **토큰 보관:** Spring Security OAuth2 Client를 사용하는 Gateway라면 Access/Refresh Token을 `OAuth2AuthorizedClient`로 관리하고 `HttpSession`에 연결하여 보관 가능
- **세션 저장:** Gateway의 `HttpSession`은 Spring Session + Redis를 적용하여 여러 Gateway 인스턴스가 공유하도록 구성 가능
- **API 인가:** Gateway가 Access Token을 `Authorization: Bearer` 헤더로 Resource Server에 전달
- **Access Token:** 일반적으로 JWT 형태의 Access Token 사용
- **JWT 검증:** Resource Server가 Keycloak 공개키로 JWT의 서명·만료시간 등을 검증
- **Refresh Token:** Access Token 만료 시 새로운 Access Token 발급에 사용

#### 최초 로그인 및 토큰 발급

```
브라우저
   │
   ▼
Gateway
   │ Authorization 요청
   ▼
Keycloak
   │
   │ 사용자 인증
   ├─ Keycloak 로그인 세션 생성
   └─ Keycloak 세션 Cookie 전달
   │
   └─ 302 Redirect + Authorization Code
              │
              ▼
           브라우저
              │ Code 전달
              ▼
           Gateway
              │
              │ Token Endpoint
              │ code=xxx
              ▼
           Keycloak
              │
              ├─ Access Token
              └─ Refresh Token
                      │
                      ▼
                   Gateway
                      │
                      └─ HttpSession
                           └─ OAuth2AuthorizedClient
                                ├─ Access Token
                                └─ Refresh Token
                      │
                      └─ Gateway 세션 ID를
                         브라우저 Cookie로 전달
```

#### 로그인 이후 API 요청

```
브라우저
   │
   │ Cookie: Gateway Session ID
   ▼
Gateway
   │
   ├─ HttpSession 조회
   │
   └─ OAuth2AuthorizedClient
          └─ Access Token
                  │
                  │ Authorization:
                  │ Bearer <Access Token>
                  ▼
           Resource Server
                  │
                  ├─ JWT 서명 검증
                  ├─ exp 등 Claim 검증
                  └─ scope/authority 기반 인가
```

### Spring Authorization Server / Keycloak 공통 구조

```
          SAS / Keycloak
                │
          Authorization Code
                ↓
             Gateway
                │
        Access / Refresh Token
                │
                ▼
          OAuth2AuthorizedClient
                │
           HttpSession
                │
        ┌───────┴────────┐
        │                │
   브라우저            Redis
 Session Cookie    (선택적 세션 저장소)

브라우저
   │ Session Cookie
   ▼
Gateway
   │ Access Token
   ▼
Resource Server
```

# 2. 회원 정보 보관 위치 — 우리 MySQL에 둘 수 있는지, 인증서버 전용 DB를 따로 요구하는지

**자체 JWT — 우리 MySQL 사용 가능**

- 기존 회원 테이블을 그대로 인증 정보 저장소로 사용 가능
- DB 구조와 인증정보 관리 방식을 직접 설계

**Spring Authorization Server — 우리 MySQL 사용 가능 테스트 완료**

- 기존 회원 테이블을 Spring Security 인증과 연결 가능
- OAuth2 Client, Authorization, Consent 등 Authorization Server 데이터도 JDBC 기반으로 저장 가능
- 별도의 인증서버 전용 DB가 반드시 필요한 것은 아님

**Keycloak — Keycloak 전용 DB 사용이 기본**

- Keycloak이 관리하는 사용자·인증 정보는 Keycloak DB에 저장
- 서비스 회원정보는 기존 서비스 MySQL과 분리하여 관리 가능
- 기존 MySQL의 회원정보를 그대로 인증에 사용하려면 `User Storage SPI` 등을 통한 외부 사용자 저장소 연동 필요
- 이 경우 Keycloak 확장 코드 개발·운영 비용 발생

# 3. 인증 절차 커스텀

### 자체 로그인

- 인증 절차를 전부 직접 구성 가능
- ID/PW 인증 후 SMS, Email, OTP 등의 2차 인증 추가 가능
- 특정 조건에서만 2FA를 요구하는 정책도 직접 구현 가능
- 인증 성공 여부와 다음 인증 단계 등을 직접 관리해야 함

```
ID / PW
   ↓
1차 인증 성공
   ↓
SMS / Email 인증번호 발송
   ↓
인증번호 검증
   ↓
최종 로그인 성공
   ↓
Access / Refresh Token 발급
```

### Spring Authorization Server - 테스트 완료

- **2FA가 완성된 기능으로 제공되는 것은 아님**
- 실제 사용자 인증은 Spring Security가 담당하므로 인증 흐름을 커스텀하여 2FA 구현 가능
- SMS, Email, OTP 등 원하는 인증 수단을 직접 연동 가능
- 1차 인증과 2차 인증 사이의 상태 관리와 인증 성공 처리 등을 직접 구현해야 함
- 2FA까지 완료된 이후 OAuth2 Authorization Code 발급 절차를 진행하도록 구성 가능

```
Authorization 요청
      ↓
ID / PW
      ↓
Spring Security 1차 인증
      ↓
SMS / Email / OTP
      ↓
2차 인증 성공
      ↓
최종 Authentication 완료
      ↓
Authorization Code
      ↓
Access Token
```

### Keycloak

- **Authentication Flow** 기능을 통해 로그인 인증 절차를 구성
- 관리자 화면에서 여러 인증 단계를 조합하여 **2FA/MFA 적용 가능**
- **TOTP(Authenticator 앱), WebAuthn/Passkey 등은 기본 제공**
- 사용자나 조건에 따라 2차 인증을 추가하는 **조건부 인증 Flow 구성 가능**
- **SMS OTP는 기본 제공하지 않으므로** Custom Authenticator(SPI) 구현 및 SMS 발송 서비스 연동 필요
- **Email OTP 등 기본 Flow에 없는 인증 방식**도 별도 Provider 확장이 필요할 수 있음

```
Authorization 요청
        ↓
Keycloak Authentication Flow
        ↓
Username / Password
        ↓
2차 인증
        │
        ├─ TOTP / WebAuthn 등
        │      → 기본 기능으로 구성
        │
        └─ SMS OTP 등
               → Custom Authenticator 구현
               → SMS 발송 서비스 연동
        ↓
최종 인증 완료
        ↓
Authorization Code
        ↓
Access Token
```

# 4. 로그아웃 및 세션/토큰 만료 처리

### 자체 로그인

- **로그아웃:** 직접 구현
- **세션 방식:** 서버의 세션을 삭제하면 즉시 로그인 상태 종료
- **Access Token 만료:** JWT의 `exp` 만료 시 API 요청 거부
- **Access Token 즉시 폐기:** JWT를 Stateless하게 검증한다면 이미 발급된 토큰은 만료 전까지 유효하므로 별도 Blacklist 등의 구현 필요
- **Refresh Token:** DB/Redis 등에 저장했다면 로그아웃 시 삭제하여 추가 Access Token 발급 차단
- **만료 후 처리:** Access Token 만료 → Refresh Token으로 재발급 → Refresh Token까지 만료되면 재로그인하도록 직접 구현

```
[로그아웃]

Client
  ↓
자체 인증 서버
  ├─ Session 삭제 (세션 방식)
  └─ Refresh Token 삭제/폐기 (토큰 방식)

Access Token
  └─ JWT라면 별도 폐기 정책이 없을 경우 exp까지 유효
```

### Spring Authorization Server

- **인증서버 로그아웃:** Spring Security의 로그아웃 기능을 통해 로그인 세션(`HttpSession`) 무효화 가능
- **세션 종료:** 기본 로그아웃 처리 시 Spring Security가 세션 및 `SecurityContext` 정리
    - accessToken 만료 만료 시키는 로직은 아니다
- **Access Token 만료:** 설정된 만료시간 이후 Resource Server에서 거부
- **Refresh Token 만료:** 만료되면 더 이상 Access Token 재발급 불가

```
로그아웃
   ↓
Client / Gateway
   ↓
Spring Authorization Server
   │
   ├─ 인증서버 Session 종료
   │
   └─ Refresh Token 등 폐기
            ↓
       재발급 불가

Access Token 만료
   ↓
Resource Server → 401
   ↓
Refresh Token 존재
   ↓
새 Access Token 발급

Refresh Token도 만료
   ↓
다시 로그인
```

### Keycloak

Keycloak도 기본 원리는 비슷하지만 **세션과 토큰을 관리하는 기능을 제품에서 제공한다**는 차이가 있어.

- **로그인 세션:** Keycloak이 사용자 세션 관리
- **로그아웃:** Keycloak Logout Endpoint를 통해 Keycloak 로그인 세션 종료 가능
- **Access Token 만료:** 만료된 Access Token은 Resource Server에서 거부
- **Refresh Token:** Keycloak 세션 및 Refresh Token 상태에 따라 Access Token 재발급
- **세션 종료:** Keycloak에서 사용자 세션을 종료하여 추가적인 토큰 갱신을 막을 수 있음
- **OIDC Logout:** RP-Initiated Logout 및 관련 로그아웃 메커니즘 지원
- **관리자 강제 로그아웃:** 특정 사용자의 세션을 관리자가 종료하는 기능 제공

```
로그아웃
   ↓
Client / Gateway
   ↓
Keycloak
   │
   ├─ Keycloak 로그인 세션 종료
   └─ Refresh를 통한 추가 토큰 발급 차단
            ↓
        재로그인 필요

Access Token 만료
   ↓
Resource Server → 401
   ↓
Refresh 가능
   ↓
새 Access Token

Refresh 불가 / 세션 만료
   ↓
Keycloak 로그인
```

# 5. 악의적 사용자 강제 종료

### Spring Authorization Server

- **사용자 강제 로그아웃:** 가능. Gateway/BFF의 사용자 세션을 무효화하면 해당 브라우저의 서비스 접근을 즉시 차단 가능
- **인증서버 세션 강제 종료:** 가능. Authorization Server의 로그인 세션을 종료하면 이후 인증 시 재로그인 필요
- **Refresh Token 강제 폐기:** 가능. Token Revocation을 통해 추가 Access Token 발급 차단 가능
- **기존 JWT Access Token 즉시 폐기:** **기본적인 Stateless JWT 검증 구조에서는 불가**
- **이유:** Resource Server는 Authorization Server의 세션/인가 상태를 조회하지 않고 JWT의 서명과 만료시간 등을 로컬에서 검증
- **BFF 구조:** 브라우저가 토큰을 직접 보유하지 않으므로 Gateway 세션 강제 종료만으로 일반적인 사용자 강제 로그아웃은 가능. 단, 이미 탈취된 JWT까지 무효화되는 것은 아님

### Keycloak

- **로그인 세션 관리:** Keycloak이 자체적으로 User Session / Client Session을 관리
- **사용자 강제 로그아웃:** Admin Console이나 Admin REST API를 통해 특정 사용자의 세션을 종료할 수 있음. Keycloak은 실제로 사용자별 활성 세션을 조회하고 삭제하는 관리 API도 제공함.
- **전체 세션 강제 종료:** Realm 단위로 활성 세션을 종료하거나 revocation 정책을 설정하는 관리 기능도 제공
- **Refresh Token:** 세션 종료나 토큰 폐기 정책에 따라 이후 Access Token 재발급을 차단할 수 있으며, Refresh Token rotation도 설정 가능
- **Token Revocation:** OAuth2 Revocation Endpoint를 제공하며 Access Token과 Refresh Token 모두 대상으로 받을 수 있음
- **JWT Access Token:** Resource Server가 Keycloak의 공개키로 JWT를 로컬 검증하는 구조에서는, Keycloak의 세션을 종료했다고 해서 Resource Server가 그 사실을 자동으로 아는 것은 아님. Keycloak 문서도 `Sign out all active sessions`가 이미 발급된 outstanding Access Token을 자동으로 폐기하지 않으며 자연 만료가 필요하다고 설명
- **Access Token 만료:** `Access Token Lifespan`으로 수명을 설정 가능
- **Introspection:** Resource Server가 Keycloak에 Token Introspection을 요청해 현재 토큰 상태를 확인하는 방식도 지원

| 강제 종료 대상 | SAS | Keycloak |
| --- | --- | --- |
| 인증서버 사용자 세션 종료 | O | O |
| Refresh Token 추가 사용 차단 | O | O |
| JWT Access Token 자연 만료 | O | O |
| 로컬 검증 중인 기존 JWT를 세션 종료만으로 즉시 차단 | X | X |
| Introspection 방식 | O | O |
| 사용자 세션 관리 UI | 직접 구현 필요 | **Admin Console 제공** |

# 6. **로그인 UI 커스텀 / 외부 배치**

### Spring Authorization Server

- **로그인 UI 커스텀:** 가능
- **인증서버 내부 UI:** Spring Security의 `formLogin().loginPage(...)`를 이용해 자체 로그인 화면으로 교체 가능
- **인증서버 외부 UI:** 별도로 배포한 React 등의 로그인 화면으로 이동하도록 구성 가능
    - **인증 처리:** UI를 외부에 두더라도 실제 사용자 인증은 Authorization Server의 Spring Security가 수행하도록 구성 가능
    - **OAuth2 흐름:** 로그인 UI 위치와 관계없이 인증 완료 후 기존 `Authorization Code → Token` 흐름으로 복귀
    - **제약사항:** 외부 UI에서 로그인 요청을 처리하는 방식에 따라 CSRF, CORS, Cookie/SameSite 등의 추가 고려 필요
    - 테스트 확인 과정
        - csrf.ignoringRequestMatchers("/login") 예외 처리

            ```java
            브라우저
               │ /oauth2/authorize
               ▼
            Spring Authorization Server
               │
               │ 미인증 사용자
               │ 302 Redirect
               ▼
            외부 React 로그인 UI
            (:5180)
               │
               │  <form method="POST"
               │ action="http://localhost:9000/login">
               │ ID / PW
               │ POST /login
               ▼
            Spring Authorization Server
            (:9000)
               │
               │ Spring Security 인증
               │ 인증 세션 생성
               ▼
            기존 /oauth2/authorize 요청으로 복귀
               │
               │ Authorization Code
               ▼
            Gateway
               │
               │ Code → Token 교환
               ▼
            Access Token
            ```


### Keycloak

- **로그인 UI 커스텀:** 가능
- **인증서버 내부 UI:** Keycloak Theme을 이용해 로그인 화면의 HTML/CSS, 로고, 문구 등을 커스텀 가능
- **인증 처리:** 기본 구조에서는 Keycloak이 로그인 화면과 실제 사용자 인증을 모두 담당
- **OAuth2 흐름:** Keycloak 로그인 완료 후 기존 `Authorization Code → Token` 흐름으로 진행
- **외부 UI 제약:** 외부 React에서 ID/PW를 직접 받아 Keycloak에 인증시키는 구조는 기본 Theme 방식이 아니며, 별도 인증 연동 방식이나 Keycloak 확장 구현을 검토해야 함 - 테스트 필요

```java
브라우저
   │ /authorize
   ▼
Keycloak
   │
   │ 미인증 사용자
   ▼
Keycloak 로그인 UI
   │
   │ ID / PW
   ▼
Keycloak
   │
   │ 사용자 인증
   │ Keycloak 세션 생성
   ▼
Authorization Code 발급
   │
   │ 302 Redirect
   ▼
Gateway
   │
   │ Code → Token 교환
   ▼
Access Token
(+ Refresh Token)
```