#!/usr/bin/env python3
"""
SIAB Keycloak Setup Script

Initializes Keycloak with:
- SIAB realm with proper settings
- Default roles (admin, operator, user, viewer)
- Default groups (administrators, operators, users)
- OAuth2/OIDC clients for dashboard and apps
- Default admin user

Usage: python3 setup-keycloak.py [--admin-email email] [--password password]
"""

import argparse
import json
import os
import secrets
import subprocess
import sys
import urllib.request
import urllib.error
import ssl

# Disable SSL verification for self-signed certs
ssl_context = ssl._create_unverified_context()

KEYCLOAK_URL = os.getenv("KEYCLOAK_URL", "https://keycloak.siab.local")
SIAB_DOMAIN = os.getenv("SIAB_DOMAIN", "siab.local")
REALM_NAME = "siab"


def get_k8s_secret(namespace, secret_name, key):
    """Get a value from a Kubernetes secret"""
    try:
        result = subprocess.run(
            ["kubectl", "get", "secret", "-n", namespace, secret_name,
             "-o", f"jsonpath={{.data.{key}}}"],
            capture_output=True, text=True, check=True
        )
        import base64
        return base64.b64decode(result.stdout).decode()
    except Exception as e:
        print(f"Error getting secret: {e}")
        return None


def api_request(method, url, data=None, token=None):
    """Make an API request to Keycloak"""
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"

    if data:
        data = json.dumps(data).encode("utf-8")

    req = urllib.request.Request(url, data=data, headers=headers, method=method)

    try:
        with urllib.request.urlopen(req, context=ssl_context, timeout=30) as response:
            if response.status in (200, 201, 204):
                try:
                    return json.loads(response.read().decode())
                except:
                    return {"status": "ok"}
            return None
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        if e.code == 409:  # Conflict - already exists
            return {"status": "exists"}
        if e.code == 404:
            return None
        print(f"HTTP Error {e.code}: {body[:200]}")
        return None
    except Exception as e:
        print(f"Request error: {e}")
        return None


def get_admin_token(admin_user, admin_pass):
    """Get admin access token"""
    url = f"{KEYCLOAK_URL}/realms/master/protocol/openid-connect/token"
    data = (
        f"username={admin_user}&password={admin_pass}"
        f"&grant_type=password&client_id=admin-cli"
    ).encode()

    req = urllib.request.Request(
        url, data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST"
    )

    try:
        with urllib.request.urlopen(req, context=ssl_context, timeout=30) as response:
            result = json.loads(response.read().decode())
            return result.get("access_token")
    except Exception as e:
        print(f"Error getting token: {e}")
        return None


def main():
    parser = argparse.ArgumentParser(description="Setup Keycloak for SIAB")
    parser.add_argument("--admin-email", default=f"admin@{SIAB_DOMAIN}",
                        help="Email for the SIAB admin user")
    parser.add_argument("--password", default=None,
                        help="Password for SIAB admin user (generated if not provided)")
    args = parser.parse_args()

    print("=" * 50)
    print("  SIAB Keycloak Setup")
    print("=" * 50)
    print()

    # Get Keycloak admin credentials
    print("[1/7] Getting Keycloak admin credentials...")
    kc_admin_user = get_k8s_secret("keycloak", "keycloak-credentials", "admin-user")
    kc_admin_pass = get_k8s_secret("keycloak", "keycloak-credentials", "admin-password")

    if not kc_admin_user or not kc_admin_pass:
        print("ERROR: Could not get Keycloak admin credentials")
        sys.exit(1)

    print(f"  Got credentials for user: {kc_admin_user}")

    # Get admin token
    token = get_admin_token(kc_admin_user, kc_admin_pass)
    if not token:
        print("ERROR: Could not get admin token")
        sys.exit(1)
    print("  Got admin access token")

    # Step 2: Create/update realm
    print()
    print("[2/7] Creating SIAB realm...")

    realm_config = {
        "realm": REALM_NAME,
        "enabled": True,
        "displayName": "SIAB - Secure Infrastructure Application Box",
        "loginWithEmailAllowed": True,
        "duplicateEmailsAllowed": False,
        "resetPasswordAllowed": True,
        "bruteForceProtected": True,
        "sslRequired": "external",
        "registrationAllowed": False,
        "rememberMe": True,
        "verifyEmail": False,
        "accessTokenLifespan": 300,
        "ssoSessionIdleTimeout": 1800,
        "ssoSessionMaxLifespan": 36000,
    }

    # Check if realm exists
    existing = api_request("GET", f"{KEYCLOAK_URL}/admin/realms/{REALM_NAME}", token=token)
    if existing and existing.get("realm") == REALM_NAME:
        print(f"  Realm '{REALM_NAME}' already exists, updating...")
        api_request("PUT", f"{KEYCLOAK_URL}/admin/realms/{REALM_NAME}", realm_config, token)
    else:
        print(f"  Creating realm '{REALM_NAME}'...")
        api_request("POST", f"{KEYCLOAK_URL}/admin/realms", realm_config, token)

    print(f"  Realm '{REALM_NAME}' configured")

    # Step 3: Create roles
    print()
    print("[3/7] Creating realm roles...")

    roles = {
        "siab-admin": "Full administrative access to SIAB platform",
        "siab-operator": "Can deploy and manage applications",
        "siab-user": "Can access deployed applications",
        "siab-viewer": "Read-only access to dashboard",
    }

    for role_name, description in roles.items():
        role_data = {
            "name": role_name,
            "description": description,
            "composite": False,
            "clientRole": False,
        }
        result = api_request(
            "POST",
            f"{KEYCLOAK_URL}/admin/realms/{REALM_NAME}/roles",
            role_data, token
        )
        if result and result.get("status") == "exists":
            print(f"  Role '{role_name}' already exists")
        else:
            print(f"  Created role '{role_name}'")

    # Step 4: Create groups
    print()
    print("[4/7] Creating groups...")

    groups = {
        "administrators": "siab-admin",
        "operators": "siab-operator",
        "users": "siab-user",
        "viewers": "siab-viewer",
    }

    for group_name, role_name in groups.items():
        # Create group
        result = api_request(
            "POST",
            f"{KEYCLOAK_URL}/admin/realms/{REALM_NAME}/groups",
            {"name": group_name}, token
        )
        if result and result.get("status") == "exists":
            print(f"  Group '{group_name}' already exists")
        else:
            print(f"  Created group '{group_name}'")

        # Get group ID
        groups_list = api_request(
            "GET",
            f"{KEYCLOAK_URL}/admin/realms/{REALM_NAME}/groups?search={group_name}",
            token=token
        )
        if groups_list and len(groups_list) > 0:
            group_id = groups_list[0].get("id")

            # Get role
            role = api_request(
                "GET",
                f"{KEYCLOAK_URL}/admin/realms/{REALM_NAME}/roles/{role_name}",
                token=token
            )

            if role and group_id:
                # Assign role to group
                api_request(
                    "POST",
                    f"{KEYCLOAK_URL}/admin/realms/{REALM_NAME}/groups/{group_id}/role-mappings/realm",
                    [role], token
                )
                print(f"    -> Assigned role '{role_name}' to group")

    # Step 5: Create OAuth clients
    print()
    print("[5/7] Creating OAuth2/OIDC clients...")

    dashboard_secret = secrets.token_hex(32)
    istio_secret = secrets.token_hex(32)

    dashboard_client = {
        "clientId": "siab-dashboard",
        "name": "SIAB Dashboard",
        "description": "Central dashboard for SIAB platform",
        "enabled": True,
        "clientAuthenticatorType": "client-secret",
        "secret": dashboard_secret,
        "redirectUris": [
            f"https://dashboard.{SIAB_DOMAIN}/*",
            f"https://*.{SIAB_DOMAIN}/*",
        ],
        "webOrigins": [
            f"https://dashboard.{SIAB_DOMAIN}",
            f"https://*.{SIAB_DOMAIN}",
        ],
        "protocol": "openid-connect",
        "publicClient": False,
        "bearerOnly": False,
        "standardFlowEnabled": True,
        "directAccessGrantsEnabled": True,
        "fullScopeAllowed": True,
        "defaultClientScopes": ["openid", "profile", "email", "roles"],
        "protocolMappers": [
            {
                "name": "groups",
                "protocol": "openid-connect",
                "protocolMapper": "oidc-group-membership-mapper",
                "config": {
                    "full.path": "false",
                    "id.token.claim": "true",
                    "access.token.claim": "true",
                    "claim.name": "groups",
                    "userinfo.token.claim": "true",
                },
            },
            {
                "name": "realm-roles",
                "protocol": "openid-connect",
                "protocolMapper": "oidc-usermodel-realm-role-mapper",
                "config": {
                    "multivalued": "true",
                    "id.token.claim": "true",
                    "access.token.claim": "true",
                    "claim.name": "roles",
                    "userinfo.token.claim": "true",
                },
            },
        ],
    }

    result = api_request(
        "POST",
        f"{KEYCLOAK_URL}/admin/realms/{REALM_NAME}/clients",
        dashboard_client, token
    )
    if result and result.get("status") == "exists":
        print("  Client 'siab-dashboard' already exists")
        # Get existing secret
        clients = api_request(
            "GET",
            f"{KEYCLOAK_URL}/admin/realms/{REALM_NAME}/clients?clientId=siab-dashboard",
            token=token
        )
        if clients and len(clients) > 0:
            client_id = clients[0].get("id")
            secret_data = api_request(
                "GET",
                f"{KEYCLOAK_URL}/admin/realms/{REALM_NAME}/clients/{client_id}/client-secret",
                token=token
            )
            if secret_data:
                dashboard_secret = secret_data.get("value", dashboard_secret)
    else:
        print("  Created client 'siab-dashboard'")

    # Istio client
    istio_client = {
        "clientId": "siab-istio",
        "name": "SIAB Istio",
        "description": "Client for Istio JWT validation",
        "enabled": True,
        "clientAuthenticatorType": "client-secret",
        "secret": istio_secret,
        "protocol": "openid-connect",
        "publicClient": False,
        "bearerOnly": True,
        "standardFlowEnabled": False,
        "fullScopeAllowed": True,
    }

    result = api_request(
        "POST",
        f"{KEYCLOAK_URL}/admin/realms/{REALM_NAME}/clients",
        istio_client, token
    )
    if result and result.get("status") == "exists":
        print("  Client 'siab-istio' already exists")
    else:
        print("  Created client 'siab-istio'")

    # Step 6: Create default admin user
    print()
    print("[6/7] Creating default admin user...")

    user_password = args.password or secrets.token_urlsafe(12)

    admin_user = {
        "username": "siab-admin",
        "email": args.admin_email,
        "emailVerified": True,
        "enabled": True,
        "firstName": "SIAB",
        "lastName": "Administrator",
        "credentials": [{
            "type": "password",
            "value": user_password,
            "temporary": True,
        }],
        "groups": ["administrators"],
    }

    result = api_request(
        "POST",
        f"{KEYCLOAK_URL}/admin/realms/{REALM_NAME}/users",
        admin_user, token
    )
    if result and result.get("status") == "exists":
        print("  User 'siab-admin' already exists")
    else:
        print("  Created user 'siab-admin'")

    # Add user to administrators group
    users = api_request(
        "GET",
        f"{KEYCLOAK_URL}/admin/realms/{REALM_NAME}/users?username=siab-admin",
        token=token
    )
    if users and len(users) > 0:
        user_id = users[0].get("id")
        groups_list = api_request(
            "GET",
            f"{KEYCLOAK_URL}/admin/realms/{REALM_NAME}/groups?search=administrators",
            token=token
        )
        if groups_list and len(groups_list) > 0:
            group_id = groups_list[0].get("id")
            api_request(
                "PUT",
                f"{KEYCLOAK_URL}/admin/realms/{REALM_NAME}/users/{user_id}/groups/{group_id}",
                {}, token
            )
            print("    -> Added to 'administrators' group")

    # Step 7: Store secrets in Kubernetes
    print()
    print("[7/7] Storing client secrets in Kubernetes...")

    secret_yaml = f"""apiVersion: v1
kind: Secret
metadata:
  name: siab-oidc-secrets
  namespace: istio-system
type: Opaque
stringData:
  dashboard-client-id: siab-dashboard
  dashboard-client-secret: "{dashboard_secret}"
  istio-client-id: siab-istio
  istio-client-secret: "{istio_secret}"
  issuer-url: "{KEYCLOAK_URL}/realms/{REALM_NAME}"
"""

    result = subprocess.run(
        ["kubectl", "apply", "-f", "-"],
        input=secret_yaml, text=True, capture_output=True
    )
    if result.returncode == 0:
        print("  Secrets stored in istio-system/siab-oidc-secrets")
    else:
        print(f"  Warning: {result.stderr}")

    # Print summary
    print()
    print("=" * 50)
    print("  Keycloak Setup Complete!")
    print("=" * 50)
    print()
    print(f"Keycloak Admin Console: {KEYCLOAK_URL}/admin/")
    print(f"  Username: {kc_admin_user}")
    print(f"  Password: {kc_admin_pass}")
    print()
    print(f"SIAB Realm: {REALM_NAME}")
    print()
    print("Default SIAB Admin User:")
    print("  Username: siab-admin")
    print(f"  Password: {user_password}")
    print("  (Password change required on first login)")
    print()
    print("Roles created:")
    print("  - siab-admin    : Full administrative access")
    print("  - siab-operator : Can deploy and manage apps")
    print("  - siab-user     : Can access deployed apps")
    print("  - siab-viewer   : Read-only dashboard access")
    print()
    print("Groups created:")
    print("  - administrators -> siab-admin role")
    print("  - operators      -> siab-operator role")
    print("  - users          -> siab-user role")
    print("  - viewers        -> siab-viewer role")
    print()

    # Save credentials
    creds_file = os.path.expanduser("~/.siab-credentials.env")
    with open(creds_file, "w") as f:
        f.write(f"""# SIAB Credentials - Generated
# Keep this file secure!

KEYCLOAK_ADMIN_USER={kc_admin_user}
KEYCLOAK_ADMIN_PASSWORD={kc_admin_pass}
KEYCLOAK_URL={KEYCLOAK_URL}

SIAB_ADMIN_USER=siab-admin
SIAB_ADMIN_PASSWORD={user_password}
SIAB_REALM={REALM_NAME}

DASHBOARD_CLIENT_ID=siab-dashboard
DASHBOARD_CLIENT_SECRET={dashboard_secret}
""")
    os.chmod(creds_file, 0o600)
    print(f"Credentials saved to: {creds_file}")


if __name__ == "__main__":
    main()
