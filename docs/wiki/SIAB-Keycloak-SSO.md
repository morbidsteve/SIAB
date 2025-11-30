# Keycloak Single Sign-On (SSO) Authentication

## Overview

Keycloak provides centralized identity and access management for the entire SIAB platform. Every user accessing any application must first authenticate through Keycloak, ensuring consistent security policies across all services.

---

## Authentication Flow

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         KEYCLOAK SSO AUTHENTICATION FLOW                         │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│   ┌──────────┐                                                                   │
│   │   User   │                                                                   │
│   └────┬─────┘                                                                   │
│        │                                                                         │
│        │ 1. Access Application                                                   │
│        │    https://dashboard.siab.local                                         │
│        ▼                                                                         │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                        ISTIO INGRESS GATEWAY                            │   │
│   │                                                                          │   │
│   │   ┌────────────────────────────────────────────────────────────────┐    │   │
│   │   │                    OAuth2 Proxy (ext_authz)                    │    │   │
│   │   │                                                                 │    │   │
│   │   │   2. Check for valid session cookie (_siab_oauth2)             │    │   │
│   │   │                                                                 │    │   │
│   │   │      ┌─────────────────────────────────────────────┐           │    │   │
│   │   │      │  Cookie Present?                             │           │    │   │
│   │   │      │                                              │           │    │   │
│   │   │      │   YES ─────► Validate with Keycloak          │           │    │   │
│   │   │      │              │                               │           │    │   │
│   │   │      │              ├─► Valid ──► Allow Request     │           │    │   │
│   │   │      │              │                               │           │    │   │
│   │   │      │              └─► Invalid ─► Redirect to      │           │    │   │
│   │   │      │                             Keycloak Login   │           │    │   │
│   │   │      │                                              │           │    │   │
│   │   │      │   NO ──────► Redirect to Keycloak Login      │           │    │   │
│   │   │      │                                              │           │    │   │
│   │   │      └─────────────────────────────────────────────┘           │    │   │
│   │   │                                                                 │    │   │
│   │   └────────────────────────────────────────────────────────────────┘    │   │
│   │                                                                          │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│        │                                                                         │
│        │ 3. Redirect to Keycloak (if not authenticated)                          │
│        │    https://keycloak.siab.local/realms/siab/protocol/openid-connect/auth │
│        ▼                                                                         │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                            KEYCLOAK                                      │   │
│   │                                                                          │   │
│   │   ┌──────────────────────────────────────────────────────────────────┐  │   │
│   │   │                      LOGIN PAGE                                   │  │   │
│   │   │                                                                   │  │   │
│   │   │   ┌─────────────────────────────────────────────────────────┐    │  │   │
│   │   │   │                                                          │    │  │   │
│   │   │   │              SIAB Login                                  │    │  │   │
│   │   │   │                                                          │    │  │   │
│   │   │   │    Username: [_______________________]                   │    │  │   │
│   │   │   │                                                          │    │  │   │
│   │   │   │    Password: [_______________________]                   │    │  │   │
│   │   │   │                                                          │    │  │   │
│   │   │   │    [ ] Remember me                                       │    │  │   │
│   │   │   │                                                          │    │  │   │
│   │   │   │              [    Sign In    ]                           │    │  │   │
│   │   │   │                                                          │    │  │   │
│   │   │   │    ─────────────────────────────────                     │    │  │   │
│   │   │   │    Or sign in with:                                      │    │  │   │
│   │   │   │    [ LDAP ] [ SAML ] [ Social ]                          │    │  │   │
│   │   │   │                                                          │    │  │   │
│   │   │   └─────────────────────────────────────────────────────────┘    │  │   │
│   │   │                                                                   │  │   │
│   │   └──────────────────────────────────────────────────────────────────┘  │   │
│   │                                                                          │   │
│   │   4. User enters credentials                                             │   │
│   │                                                                          │   │
│   │   ┌──────────────────────────────────────────────────────────────────┐  │   │
│   │   │                   AUTHENTICATION                                  │  │   │
│   │   │                                                                   │  │   │
│   │   │   • Validate username/password against user store                │  │   │
│   │   │   • Check for MFA requirement                                    │  │   │
│   │   │   • Verify account status (enabled, not locked)                  │  │   │
│   │   │   • Check password expiry                                        │  │   │
│   │   │   • Log authentication event                                     │  │   │
│   │   │                                                                   │  │   │
│   │   └──────────────────────────────────────────────────────────────────┘  │   │
│   │                                                                          │   │
│   │   5. Generate tokens on successful authentication                        │   │
│   │                                                                          │   │
│   │   ┌──────────────────────────────────────────────────────────────────┐  │   │
│   │   │                     TOKEN GENERATION                              │  │   │
│   │   │                                                                   │  │   │
│   │   │   Access Token (JWT):                                            │  │   │
│   │   │   ┌───────────────────────────────────────────────────────┐     │  │   │
│   │   │   │ {                                                      │     │  │   │
│   │   │   │   "sub": "user-uuid",                                  │     │  │   │
│   │   │   │   "preferred_username": "siab-admin",                  │     │  │   │
│   │   │   │   "email": "admin@siab.local",                         │     │  │   │
│   │   │   │   "roles": ["siab-admin"],                             │     │  │   │
│   │   │   │   "groups": ["administrators"],                        │     │  │   │
│   │   │   │   "exp": 1234567890,                                   │     │  │   │
│   │   │   │   "iss": "https://keycloak.siab.local/realms/siab"     │     │  │   │
│   │   │   │ }                                                      │     │  │   │
│   │   │   └───────────────────────────────────────────────────────┘     │  │   │
│   │   │                                                                   │  │   │
│   │   │   Refresh Token: For obtaining new access tokens                 │  │   │
│   │   │   ID Token: User identity claims                                 │  │   │
│   │   │                                                                   │  │   │
│   │   └──────────────────────────────────────────────────────────────────┘  │   │
│   │                                                                          │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│        │                                                                         │
│        │ 6. Redirect back to application with authorization code                 │
│        │    https://auth.siab.local/oauth2/callback?code=xxx                     │
│        ▼                                                                         │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                          OAuth2 Proxy                                    │   │
│   │                                                                          │   │
│   │   7. Exchange code for tokens                                            │   │
│   │   8. Set session cookie (_siab_oauth2)                                   │   │
│   │   9. Redirect to original application                                    │   │
│   │                                                                          │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│        │                                                                         │
│        │ 10. Access granted with user context                                    │
│        ▼                                                                         │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                          APPLICATION                                     │   │
│   │                                                                          │   │
│   │   Request headers added by OAuth2 Proxy:                                 │   │
│   │   ┌───────────────────────────────────────────────────────────────┐     │   │
│   │   │ X-Auth-Request-User: siab-admin                                │     │   │
│   │   │ X-Auth-Request-Email: admin@siab.local                         │     │   │
│   │   │ X-Auth-Request-Groups: administrators                          │     │   │
│   │   │ Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI...          │     │   │
│   │   └───────────────────────────────────────────────────────────────┘     │   │
│   │                                                                          │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## SIAB Realm Configuration

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                          SIAB KEYCLOAK REALM                                     │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│   Realm: siab                                                                    │
│   URL: https://keycloak.siab.local/realms/siab                                  │
│                                                                                  │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                            ROLES                                         │   │
│   │                                                                          │   │
│   │   ┌───────────────────────────────────────────────────────────────┐     │   │
│   │   │                                                                │     │   │
│   │   │   ROLE NAME        DESCRIPTION                                 │     │   │
│   │   │   ──────────────────────────────────────────────────────────   │     │   │
│   │   │                                                                │     │   │
│   │   │   siab-admin       Full administrative access to SIAB          │     │   │
│   │   │                    • Manage all users and security             │     │   │
│   │   │                    • Access all administrative consoles        │     │   │
│   │   │                    • Deploy and manage all applications        │     │   │
│   │   │                    • View all metrics and audit logs           │     │   │
│   │   │                                                                │     │   │
│   │   │   siab-operator    Application deployment and management       │     │   │
│   │   │                    • Deploy new applications                   │     │   │
│   │   │                    • Manage application configurations         │     │   │
│   │   │                    • View application metrics                  │     │   │
│   │   │                    • Cannot manage users or security           │     │   │
│   │   │                                                                │     │   │
│   │   │   siab-user        Standard user access                        │     │   │
│   │   │                    • Access deployed applications              │     │   │
│   │   │                    • View personal dashboard                   │     │   │
│   │   │                    • Cannot deploy or manage apps              │     │   │
│   │   │                                                                │     │   │
│   │   └───────────────────────────────────────────────────────────────┘     │   │
│   │                                                                          │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                            GROUPS                                        │   │
│   │                                                                          │   │
│   │   ┌───────────────────────────────────────────────────────────────┐     │   │
│   │   │                                                                │     │   │
│   │   │   GROUP              DEFAULT ROLE          MEMBERS             │     │   │
│   │   │   ────────────────────────────────────────────────────────────│     │   │
│   │   │                                                                │     │   │
│   │   │   administrators     siab-admin            Platform admins     │     │   │
│   │   │                                                                │     │   │
│   │   │   operators          siab-operator         DevOps team         │     │   │
│   │   │                                                                │     │   │
│   │   │   users              siab-user             End users           │     │   │
│   │   │                                                                │     │   │
│   │   └───────────────────────────────────────────────────────────────┘     │   │
│   │                                                                          │   │
│   │   Users added to a group automatically inherit the group's role         │   │
│   │                                                                          │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                         OIDC CLIENTS                                     │   │
│   │                                                                          │   │
│   │   ┌───────────────────────────────────────────────────────────────┐     │   │
│   │   │                                                                │     │   │
│   │   │   CLIENT ID            TYPE           PURPOSE                  │     │   │
│   │   │   ─────────────────────────────────────────────────────────────│     │   │
│   │   │                                                                │     │   │
│   │   │   siab-dashboard       Public         Browser-based login      │     │   │
│   │   │                                       for Dashboard, Deployer  │     │   │
│   │   │                                                                │     │   │
│   │   │   siab-oauth2-proxy    Confidential   SSO enforcement via      │     │   │
│   │   │                                       OAuth2 Proxy             │     │   │
│   │   │                                                                │     │   │
│   │   │   siab-admin-services  Confidential   Admin tool integration   │     │   │
│   │   │                                       (Grafana, K8s Dashboard) │     │   │
│   │   │                                                                │     │   │
│   │   └───────────────────────────────────────────────────────────────┘     │   │
│   │                                                                          │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Role-Based Access Control (RBAC)

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              RBAC ACCESS MATRIX                                  │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                                                                          │   │
│   │  SERVICE                      siab-admin   siab-operator   siab-user    │   │
│   │  ────────────────────────────────────────────────────────────────────   │   │
│   │                                                                          │   │
│   │  SIAB Dashboard                   ✓            ✓              ✓         │   │
│   │  (dashboard.siab.local)                                                  │   │
│   │                                                                          │   │
│   │  App Deployer                     ✓            ✓              ✗         │   │
│   │  (deployer.siab.local)                                                   │   │
│   │                                                                          │   │
│   │  App Catalog                      ✓            ✓              ✓         │   │
│   │  (catalog.siab.local)                                                    │   │
│   │                                                                          │   │
│   │  User Applications                ✓            ✓              ✓         │   │
│   │  (*.apps.siab.local)                                                     │   │
│   │                                                                          │   │
│   │  ──────────────────────────────────────────────────────────────────────│   │
│   │  ADMIN SERVICES                                                          │   │
│   │  ──────────────────────────────────────────────────────────────────────│   │
│   │                                                                          │   │
│   │  Keycloak Admin                   ✓            ✗              ✗         │   │
│   │  (keycloak.siab.local/admin)                                             │   │
│   │                                                                          │   │
│   │  Grafana                          ✓         Read-Only          ✗         │   │
│   │  (grafana.siab.local)                                                    │   │
│   │                                                                          │   │
│   │  Kubernetes Dashboard             ✓         Namespace           ✗         │   │
│   │  (k8s-dashboard.siab.local)                  Only                        │   │
│   │                                                                          │   │
│   │  MinIO Console                    ✓            ✗              ✗         │   │
│   │  (minio.siab.local)                                                      │   │
│   │                                                                          │   │
│   │  Longhorn UI                      ✓            ✗              ✗         │   │
│   │  (longhorn.siab.local)                                                   │   │
│   │                                                                          │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│   Legend:  ✓ = Full Access    Read-Only = Limited Access    ✗ = No Access       │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Multi-Factor Authentication (MFA)

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         MFA AUTHENTICATION FLOW                                  │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│   ┌────────────────┐                                                             │
│   │ Primary Auth   │                                                             │
│   │ (Password)     │                                                             │
│   └───────┬────────┘                                                             │
│           │                                                                      │
│           ▼                                                                      │
│   ┌───────────────────────────────────────────────────────────────────────┐     │
│   │                     MFA REQUIREMENT CHECK                              │     │
│   │                                                                        │     │
│   │   User has MFA configured?                                             │     │
│   │                                                                        │     │
│   │      YES ────────────────────────────────────────────────────┐        │     │
│   │                                                               │        │     │
│   │      NO ─────► Check if MFA required for role                │        │     │
│   │                │                                              │        │     │
│   │                ├─► Required ──► Prompt MFA Setup             │        │     │
│   │                │                                              │        │     │
│   │                └─► Optional ──► Allow Access ────────────────┼───┐    │     │
│   │                                                               │   │    │     │
│   └───────────────────────────────────────────────────────────────┼───┼────┘     │
│                                                                   │   │          │
│                                                                   ▼   │          │
│   ┌───────────────────────────────────────────────────────────────────┼────┐    │
│   │                     MFA CHALLENGE                              │   │    │    │
│   │                                                                │   │    │    │
│   │   ┌─────────────────────────────────────────────────────┐     │   │    │    │
│   │   │                                                      │     │   │    │    │
│   │   │           Two-Factor Authentication                  │     │   │    │    │
│   │   │                                                      │     │   │    │    │
│   │   │   Enter the code from your authenticator app:        │     │   │    │    │
│   │   │                                                      │     │   │    │    │
│   │   │   ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐              │     │   │    │    │
│   │   │   │   │ │   │ │   │ │   │ │   │ │   │              │     │   │    │    │
│   │   │   └───┘ └───┘ └───┘ └───┘ └───┘ └───┘              │     │   │    │    │
│   │   │                                                      │     │   │    │    │
│   │   │                [  Verify  ]                          │     │   │    │    │
│   │   │                                                      │     │   │    │    │
│   │   └─────────────────────────────────────────────────────┘     │   │    │    │
│   │                                                                │   │    │    │
│   │   Supported MFA Methods:                                       │   │    │    │
│   │   • TOTP (Google Authenticator, Authy, etc.)                  │   │    │    │
│   │   • WebAuthn/FIDO2 (Hardware keys, biometrics)                │   │    │    │
│   │   • SMS (if configured)                                        │   │    │    │
│   │   • Email OTP (if configured)                                  │   │    │    │
│   │                                                                │   │    │    │
│   └────────────────────────────────────────────────────────────────┼───┼────┘    │
│                                                                    │   │         │
│                        Valid Code?                                 │   │         │
│                                                                    │   │         │
│               YES ──────────────────────────────────────────────────   │         │
│                                                                        │         │
│               NO ────► Retry or Block after max attempts              │         │
│                                                                        │         │
│                                                                        ▼         │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                        ACCESS GRANTED                                    │   │
│   │                                                                          │   │
│   │   • Session created                                                      │   │
│   │   • Tokens issued                                                        │   │
│   │   • Audit event logged                                                   │   │
│   │                                                                          │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Security Features

### Brute Force Protection

| Setting | Value | Description |
|---------|-------|-------------|
| Max Login Failures | 5 | Account locked after 5 failed attempts |
| Wait Increment | 60 seconds | Time added per failed attempt |
| Max Wait | 15 minutes | Maximum lockout duration |
| Quick Login Check | 1 second | Minimum time between login attempts |
| Failure Reset Time | 12 hours | Time to reset failure count |

### Session Security

| Setting | Value | Description |
|---------|-------|-------------|
| SSO Session Idle | 30 minutes | Idle timeout for SSO sessions |
| SSO Session Max | 10 hours | Maximum SSO session lifetime |
| Access Token Lifespan | 1 hour | JWT access token validity |
| Refresh Token Lifespan | 30 days | Refresh token validity |

### Password Policy

| Requirement | Value |
|-------------|-------|
| Minimum Length | 12 characters |
| Uppercase Required | Yes |
| Lowercase Required | Yes |
| Digit Required | Yes |
| Special Character | Yes |
| Password History | 10 passwords |
| Expiry | 90 days (configurable) |

---

## Federation Options

Keycloak supports integration with external identity providers:

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         IDENTITY FEDERATION                                      │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                      EXTERNAL IDENTITY PROVIDERS                         │   │
│   │                                                                          │   │
│   │   ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                 │   │
│   │   │    LDAP     │    │    SAML     │    │   Social    │                 │   │
│   │   │             │    │             │    │   Login     │                 │   │
│   │   │ • Active    │    │ • Okta      │    │             │                 │   │
│   │   │   Directory │    │ • Azure AD  │    │ • Google    │                 │   │
│   │   │ • OpenLDAP  │    │ • OneLogin  │    │ • GitHub    │                 │   │
│   │   │ • FreeIPA   │    │ • PingFed   │    │ • Microsoft │                 │   │
│   │   │             │    │             │    │             │                 │   │
│   │   └──────┬──────┘    └──────┬──────┘    └──────┬──────┘                 │   │
│   │          │                  │                  │                         │   │
│   │          └──────────────────┼──────────────────┘                         │   │
│   │                             │                                            │   │
│   │                             ▼                                            │   │
│   │   ┌─────────────────────────────────────────────────────────────────┐   │   │
│   │   │                        KEYCLOAK                                  │   │   │
│   │   │                                                                  │   │   │
│   │   │   • User federation with attribute mapping                       │   │   │
│   │   │   • Just-in-time user provisioning                              │   │   │
│   │   │   • Group synchronization                                        │   │   │
│   │   │   • Role mapping from external claims                            │   │   │
│   │   │                                                                  │   │   │
│   │   └─────────────────────────────────────────────────────────────────┘   │   │
│   │                             │                                            │   │
│   │                             ▼                                            │   │
│   │   ┌─────────────────────────────────────────────────────────────────┐   │   │
│   │   │                    SIAB APPLICATIONS                             │   │   │
│   │   │                                                                  │   │   │
│   │   │   Users from any federated source can access SIAB with          │   │   │
│   │   │   their existing corporate credentials                           │   │   │
│   │   │                                                                  │   │   │
│   │   └─────────────────────────────────────────────────────────────────┘   │   │
│   │                                                                          │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Audit Logging

All authentication events are logged for security monitoring:

| Event Type | Details Captured |
|------------|------------------|
| LOGIN | User, IP, time, client, success/failure |
| LOGOUT | User, session duration |
| LOGIN_ERROR | User, IP, error reason, attempt count |
| REGISTER | New user details |
| UPDATE_PASSWORD | User, admin/self-service |
| UPDATE_PROFILE | Changed attributes |
| GRANT_CONSENT | Client, scopes granted |
| REVOKE_GRANT | Client, scopes revoked |
| CODE_TO_TOKEN | OAuth code exchange |
| REFRESH_TOKEN | Token refresh events |

---

## Related Documentation

- [Security Architecture Deep Dive](./SIAB-Security-Architecture.md)
- [Network Security & Istio](./SIAB-Network-Security.md)
