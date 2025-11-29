#!/usr/bin/env python3
"""
SIAB Application Deployer API
Smart deployment of applications from various sources:
- Raw Kubernetes manifests
- Helm charts
- Dockerfiles
- docker-compose files
- Git repositories

Automatically integrates with:
- Longhorn for persistent storage
- Keycloak for authentication
- Istio for service mesh
- MinIO for object storage
"""

from flask import Flask, request, jsonify, send_from_directory
from flask_cors import CORS
import yaml
import json
import subprocess
import tempfile
import os
import re
from pathlib import Path
import logging
import hashlib
from datetime import datetime
import urllib.request
import urllib.error
import base64
import secrets
import string

app = Flask(__name__, static_folder='/app/frontend', static_url_path='')
CORS(app)


def generate_password(length=24):
    """Generate a secure random password"""
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*"
    return ''.join(secrets.choice(alphabet) for _ in range(length))

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration
APPS_DIR = os.getenv('APPS_DIR', '/tmp/apps')
DEPLOYMENTS_DIR = os.getenv('DEPLOYMENTS_DIR', '/tmp/deployments')
SIAB_DOMAIN = os.getenv('SIAB_DOMAIN', 'siab.local')
KEYCLOAK_ENABLED = os.getenv('KEYCLOAK_ENABLED', 'true').lower() == 'true'
ISTIO_ENABLED = os.getenv('ISTIO_ENABLED', 'true').lower() == 'true'
MINIO_ENDPOINT = os.getenv('MINIO_ENDPOINT', 'minio.minio.svc.cluster.local:9000')

# Ensure directories exist
os.makedirs(APPS_DIR, exist_ok=True)
os.makedirs(DEPLOYMENTS_DIR, exist_ok=True)


def run_command(cmd, input_data=None):
    """Run shell command and return output"""
    try:
        result = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            input=input_data,
            timeout=300
        )
        return {
            'success': result.returncode == 0,
            'stdout': result.stdout,
            'stderr': result.stderr,
            'returncode': result.returncode
        }
    except Exception as e:
        logger.error(f"Command failed: {cmd}, Error: {str(e)}")
        return {
            'success': False,
            'stdout': '',
            'stderr': str(e),
            'returncode': -1
        }


def generate_deployment_id(name):
    """Generate unique deployment ID"""
    timestamp = datetime.now().strftime('%Y%m%d%H%M%S')
    return f"{name}-{timestamp}"


def ensure_namespace(namespace):
    """Create namespace if it doesn't exist, with Istio injection enabled"""
    manifest = f"""
apiVersion: v1
kind: Namespace
metadata:
  name: {namespace}
  labels:
    istio-injection: enabled
"""
    result = run_command('kubectl apply -f -', input_data=manifest)
    return result['success']


def create_ingress_route(namespace, service_name, service_port, hostname=None):
    """Create Istio VirtualService for the application"""
    if not ISTIO_ENABLED:
        return True

    if not hostname:
        hostname = f"{service_name}.{SIAB_DOMAIN}"

    virtualservice = f"""
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: {service_name}
  namespace: istio-system
spec:
  hosts:
    - "{hostname}"
  gateways:
    - siab-gateway
  http:
    - route:
        - destination:
            host: {service_name}.{namespace}.svc.cluster.local
            port:
              number: {service_port}
"""

    result = run_command('kubectl apply -f -', input_data=virtualservice)
    return result['success']


def create_pvc(name, namespace, size='10Gi', mount_path='/data', storage_class='longhorn'):
    """Create PersistentVolumeClaim with Longhorn"""
    pvc = f"""
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {name}-data
  namespace: {namespace}
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: {storage_class}
  resources:
    requests:
      storage: {size}
"""
    result = run_command('kubectl apply -f -', input_data=pvc)
    return result['success']


def store_app_credentials(name, namespace, username, password, extra_info=None):
    """Store application credentials in a protected Kubernetes Secret

    Credentials are stored in siab-system namespace for admin access only.
    """
    # Create the credentials secret in siab-system namespace (protected)
    secret_data = {
        'app-name': name,
        'app-namespace': namespace,
        'username': username,
        'password': password,
        'created': datetime.now().isoformat()
    }

    if extra_info:
        for key, value in extra_info.items():
            secret_data[key] = str(value)

    # Convert to base64 for Kubernetes secret
    encoded_data = {k: base64.b64encode(v.encode()).decode() for k, v in secret_data.items()}

    secret = f"""
apiVersion: v1
kind: Secret
metadata:
  name: app-creds-{name}
  namespace: siab-system
  labels:
    siab.local/credential-type: app-credentials
    siab.local/app-name: {name}
    siab.local/app-namespace: {namespace}
type: Opaque
data:
"""
    for key, value in encoded_data.items():
        secret += f"  {key}: {value}\n"

    result = run_command('kubectl apply -f -', input_data=secret)
    if result['success']:
        logger.info(f"Stored credentials for {name} in siab-system/app-creds-{name}")
    else:
        logger.error(f"Failed to store credentials for {name}: {result['stderr']}")

    return result['success']


def get_app_credentials(name):
    """Retrieve application credentials from the protected secret"""
    cmd = f"kubectl get secret app-creds-{name} -n siab-system -o json"
    result = run_command(cmd)

    if not result['success']:
        return None

    try:
        secret = json.loads(result['stdout'])
        data = secret.get('data', {})
        decoded = {k: base64.b64decode(v).decode() for k, v in data.items()}
        return decoded
    except Exception as e:
        logger.error(f"Failed to decode credentials for {name}: {e}")
        return None


def create_keycloak_client_for_app(name, hostname):
    """Create a Keycloak client for an application that supports OIDC

    Returns client_id and client_secret for the app to use.
    """
    client_id = f"siab-app-{name}"
    client_secret = secrets.token_urlsafe(32)

    # Get admin token from Keycloak
    token_result = run_command("""
        curl -sk -X POST 'https://keycloak.siab.local/realms/master/protocol/openid-connect/token' \
        -H 'Content-Type: application/x-www-form-urlencoded' \
        -d 'username=admin' \
        -d 'password=admin' \
        -d 'grant_type=password' \
        -d 'client_id=admin-cli' | jq -r '.access_token'
    """)

    if not token_result['success'] or not token_result['stdout'].strip():
        logger.warning("Could not get Keycloak admin token - skipping client creation")
        return None, None

    admin_token = token_result['stdout'].strip()

    # Create the client in Keycloak
    client_config = {
        "clientId": client_id,
        "name": f"SIAB App: {name}",
        "enabled": True,
        "clientAuthenticatorType": "client-secret",
        "secret": client_secret,
        "redirectUris": [
            f"https://{hostname}/*",
            f"https://{hostname}/apps/oidc/*"
        ],
        "webOrigins": [f"https://{hostname}"],
        "protocol": "openid-connect",
        "publicClient": False,
        "standardFlowEnabled": True,
        "directAccessGrantsEnabled": False,
        "attributes": {
            "post.logout.redirect.uris": f"https://{hostname}/*"
        }
    }

    create_result = run_command(f"""
        curl -sk -X POST 'https://keycloak.siab.local/admin/realms/siab/clients' \
        -H 'Authorization: Bearer {admin_token}' \
        -H 'Content-Type: application/json' \
        -d '{json.dumps(client_config)}'
    """)

    if create_result['returncode'] == 0:
        logger.info(f"Created Keycloak client {client_id} for {name}")
        return client_id, client_secret
    else:
        logger.warning(f"Failed to create Keycloak client for {name}")
        return None, None


def create_minio_bucket_secret(name, namespace, bucket_name=None):
    """Create secret with MinIO credentials for the application"""
    if not bucket_name:
        bucket_name = name.replace('-', '')

    # Get MinIO credentials from the minio namespace
    creds_result = run_command(
        "kubectl get secret minio -n minio -o jsonpath='{.data.rootUser}'"
    )
    user = base64.b64decode(creds_result['stdout']).decode() if creds_result['success'] else 'admin'

    creds_result = run_command(
        "kubectl get secret minio -n minio -o jsonpath='{.data.rootPassword}'"
    )
    password = base64.b64decode(creds_result['stdout']).decode() if creds_result['success'] else ''

    secret = f"""
apiVersion: v1
kind: Secret
metadata:
  name: {name}-minio
  namespace: {namespace}
type: Opaque
stringData:
  MINIO_ENDPOINT: "{MINIO_ENDPOINT}"
  MINIO_ACCESS_KEY: "{user}"
  MINIO_SECRET_KEY: "{password}"
  MINIO_BUCKET: "{bucket_name}"
  AWS_ACCESS_KEY_ID: "{user}"
  AWS_SECRET_ACCESS_KEY: "{password}"
  AWS_ENDPOINT_URL: "http://{MINIO_ENDPOINT}"
"""
    result = run_command('kubectl apply -f -', input_data=secret)
    return result['success']


def detect_content_type(content, filename=''):
    """Detect the type of deployment content"""
    lower = content.lower()
    fname = filename.lower()

    # Check for Kubernetes manifest
    if 'apiversion:' in lower and 'kind:' in lower:
        kinds = re.findall(r'kind:\s*(\w+)', content, re.IGNORECASE)
        return {
            'type': 'manifest',
            'kinds': list(set(kinds)),
            'description': f"Kubernetes manifest with {', '.join(set(kinds))}"
        }

    # Check for Docker Compose
    if ('services:' in lower and ('image:' in lower or 'build:' in lower)) or \
       'docker-compose' in fname or 'compose.y' in fname:
        services = re.findall(r'^\s{2}(\w+):', content, re.MULTILINE)
        services = [s for s in services if s not in ['version', 'services', 'volumes', 'networks']]
        return {
            'type': 'compose',
            'services': services,
            'description': f"Docker Compose with {len(services)} services"
        }

    # Check for Dockerfile
    if ('from ' in lower) and ('run ' in lower or 'cmd ' in lower or 'copy ' in lower):
        from_match = re.search(r'FROM\s+([^\s\n]+)', content, re.IGNORECASE)
        return {
            'type': 'dockerfile',
            'base_image': from_match.group(1) if from_match else 'unknown',
            'description': f"Dockerfile based on {from_match.group(1) if from_match else 'unknown'}"
        }

    # Check for Helm Chart.yaml
    if 'apiversion:' in lower and 'appversion:' in lower and 'name:' in lower:
        name_match = re.search(r'^name:\s*(.+)$', content, re.MULTILINE)
        return {
            'type': 'helm',
            'chart_name': name_match.group(1).strip() if name_match else 'unknown',
            'description': f"Helm Chart"
        }

    # Try JSON (Kubernetes manifest)
    try:
        json_content = json.loads(content)
        if 'apiVersion' in json_content and 'kind' in json_content:
            return {
                'type': 'manifest',
                'kinds': [json_content['kind']],
                'description': f"Kubernetes {json_content['kind']} (JSON)"
            }
    except json.JSONDecodeError:
        pass

    return {
        'type': 'unknown',
        'description': 'Unknown format'
    }


def parse_docker_compose(compose_content):
    """Convert docker-compose.yml to Kubernetes manifests"""
    try:
        compose = yaml.safe_load(compose_content)
        services = compose.get('services', {})
        manifests = []

        for service_name, service_config in services.items():
            # Create deployment
            image = service_config.get('image', 'nginx:latest')
            ports = service_config.get('ports', [])
            environment = service_config.get('environment', [])
            volumes = service_config.get('volumes', [])

            # Parse ports
            container_ports = []
            service_ports = []
            for port in ports:
                if isinstance(port, str):
                    parts = port.split(':')
                    if len(parts) >= 2:
                        host_port = int(parts[0])
                        container_port = int(parts[1].split('/')[0])
                    else:
                        host_port = container_port = int(parts[0].split('/')[0])
                else:
                    host_port = container_port = int(port)

                container_ports.append({
                    'containerPort': container_port,
                    'name': f'port-{container_port}'
                })
                service_ports.append({
                    'port': host_port,
                    'targetPort': container_port,
                    'name': f'port-{container_port}'
                })

            # Parse environment variables
            env_vars = []
            if isinstance(environment, list):
                for env in environment:
                    if '=' in str(env):
                        key, value = str(env).split('=', 1)
                        env_vars.append({'name': key, 'value': value})
            elif isinstance(environment, dict):
                for key, value in environment.items():
                    env_vars.append({'name': key, 'value': str(value) if value else ''})

            # Create deployment manifest
            deployment = {
                'apiVersion': 'apps/v1',
                'kind': 'Deployment',
                'metadata': {
                    'name': service_name,
                    'labels': {
                        'app': service_name,
                        'deployed-by': 'siab-deployer'
                    }
                },
                'spec': {
                    'replicas': 1,
                    'selector': {
                        'matchLabels': {
                            'app': service_name
                        }
                    },
                    'template': {
                        'metadata': {
                            'labels': {
                                'app': service_name
                            }
                        },
                        'spec': {
                            'containers': [{
                                'name': service_name,
                                'image': image,
                                'ports': container_ports if container_ports else [{'containerPort': 80, 'name': 'http'}],
                                'env': env_vars
                            }]
                        }
                    }
                }
            }

            manifests.append(deployment)

            # Create service if ports are defined
            if service_ports or not ports:
                service = {
                    'apiVersion': 'v1',
                    'kind': 'Service',
                    'metadata': {
                        'name': service_name,
                        'labels': {
                            'app': service_name
                        }
                    },
                    'spec': {
                        'selector': {
                            'app': service_name
                        },
                        'ports': service_ports if service_ports else [{'port': 80, 'targetPort': 80, 'name': 'http'}]
                    }
                }
                manifests.append(service)

        return manifests
    except Exception as e:
        logger.error(f"Failed to parse docker-compose: {str(e)}")
        raise


def check_prebuilt_image(dockerfile_content, repo_info=None):
    """Check if a pre-built image exists for this Dockerfile source"""
    # Check for linuxserver images
    if repo_info and 'linuxserver' in repo_info.get('org', '').lower():
        repo_name = repo_info.get('repo', '').replace('docker-', '')
        if repo_name:
            image = f"lscr.io/linuxserver/{repo_name}:latest"
            # Different linuxserver images use different ports
            # Most web UIs use 3000, but server apps use 80/443
            port_map = {
                'nextcloud': 80,
                'nginx': 80,
                'swag': 443,
                'heimdall': 80,
                'mariadb': 3306,
                'postgres': 5432,
                'plex': 32400,
                'jellyfin': 8096,
                'emby': 8096,
                'sonarr': 8989,
                'radarr': 7878,
                'lidarr': 8686,
                'prowlarr': 9696,
                'qbittorrent': 8080,
                'transmission': 9091,
                'code-server': 8443,
                'webtop': 3000,
                'firefox': 3000,
                'chromium': 3000,
            }
            port = port_map.get(repo_name, 3000)  # Default to 3000 for web UI apps
            return image, port

    # Check for ghcr.io reference in Dockerfile
    ghcr_match = re.search(r'ghcr\.io/([^/\s]+)/([^:\s]+)', dockerfile_content)
    if ghcr_match:
        return f"ghcr.io/{ghcr_match.group(1)}/{ghcr_match.group(2)}:latest", 8080

    # Check FROM line for usable base image
    from_match = re.search(r'FROM\s+([^\s\n]+)', dockerfile_content, re.IGNORECASE)
    if from_match:
        base_image = from_match.group(1)
        # If FROM uses a specific app image (not a base like alpine/ubuntu), suggest it
        base_lower = base_image.lower()
        if not any(base in base_lower for base in ['alpine', 'ubuntu', 'debian', 'python', 'node', 'golang', 'rust']):
            return base_image, 8080

    return None, None


def create_deployment_from_image(name, image, namespace, port=8080, env_vars=None):
    """Create deployment from a pre-built image"""
    deployment = {
        'apiVersion': 'apps/v1',
        'kind': 'Deployment',
        'metadata': {
            'name': name,
            'namespace': namespace,
            'labels': {
                'app': name,
                'deployed-by': 'siab-deployer'
            }
        },
        'spec': {
            'replicas': 1,
            'selector': {
                'matchLabels': {
                    'app': name
                }
            },
            'template': {
                'metadata': {
                    'labels': {
                        'app': name
                    }
                },
                'spec': {
                    'containers': [{
                        'name': name,
                        'image': image,
                        'imagePullPolicy': 'Always',
                        'ports': [{
                            'containerPort': port,
                            'name': 'http'
                        }],
                        'env': env_vars or []
                    }],
                    'securityContext': {
                        'fsGroup': 1000
                    }
                }
            }
        }
    }

    service = {
        'apiVersion': 'v1',
        'kind': 'Service',
        'metadata': {
            'name': name,
            'namespace': namespace
        },
        'spec': {
            'selector': {
                'app': name
            },
            'ports': [{
                'port': 80,
                'targetPort': port,
                'name': 'http'
            }]
        }
    }

    return [deployment, service], None


def create_deployment_from_dockerfile(name, dockerfile_content, namespace, port=8080, repo_info=None):
    """Create deployment from Dockerfile - uses pre-built image if available"""
    try:
        # First, check if a pre-built image exists
        prebuilt_image, suggested_port = check_prebuilt_image(dockerfile_content, repo_info)

        if prebuilt_image:
            logger.info(f"Using pre-built image: {prebuilt_image}")
            # Use linuxserver-specific env vars if applicable
            env_vars = []
            if 'linuxserver' in prebuilt_image:
                env_vars = [
                    {'name': 'PUID', 'value': '1000'},
                    {'name': 'PGID', 'value': '1000'},
                    {'name': 'TZ', 'value': 'UTC'}
                ]
            return create_deployment_from_image(
                name,
                prebuilt_image,
                namespace,
                port=suggested_port or port,
                env_vars=env_vars
            )

        # No pre-built image found - check if we can build
        # Check for buildah or docker
        buildah_check = run_command('which buildah')
        docker_check = run_command('which docker')

        if not buildah_check['success'] and not docker_check['success']:
            return None, (
                "Cannot build Dockerfile: No container build tools available. "
                "Please either:\n"
                "1. Use a pre-built image from Docker Hub or GHCR\n"
                "2. Provide a Kubernetes manifest or docker-compose file\n"
                "3. Use the Quick Deploy with an existing image"
            )

        # Create temporary directory for build context
        with tempfile.TemporaryDirectory() as tmpdir:
            dockerfile_path = os.path.join(tmpdir, 'Dockerfile')
            with open(dockerfile_path, 'w') as f:
                f.write(dockerfile_content)

            # Build image using buildah or docker
            image_name = f"localhost/{name}:latest"
            if buildah_check['success']:
                build_cmd = f"buildah bud -t {image_name} {tmpdir}"
            else:
                build_cmd = f"docker build -t {image_name} {tmpdir}"

            result = run_command(build_cmd)

            if not result['success']:
                return None, f"Build failed: {result['stderr']}"

            return create_deployment_from_image(name, image_name, namespace, port)

    except Exception as e:
        return None, str(e)


# =============================================================================
# API Routes
# =============================================================================

@app.route('/')
def serve_frontend():
    """Serve the frontend"""
    return send_from_directory('/app/frontend', 'index.html')


@app.route('/apps')
def serve_apps_page():
    """Serve deployed apps page"""
    return send_from_directory('/app/frontend', 'apps.html')


@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({'status': 'healthy', 'timestamp': datetime.now().isoformat()})


@app.route('/api/fetch-git', methods=['POST'])
def fetch_git():
    """Fetch content from a Git repository URL"""
    try:
        data = request.get_json()
        url = data.get('url', '').strip()

        if not url:
            return jsonify({'success': False, 'error': 'No URL provided'}), 400

        # Handle GitHub/GitLab raw file URLs
        content = None
        filename = 'manifest.yaml'
        repo_info = None  # Track repo org/name for pre-built image detection

        # Convert GitHub blob URLs to raw URLs
        if 'github.com' in url and '/blob/' in url:
            url = url.replace('github.com', 'raw.githubusercontent.com').replace('/blob/', '/')

        # Convert GitLab URLs
        if 'gitlab.com' in url and '/-/blob/' in url:
            url = url.replace('/-/blob/', '/-/raw/')

        # If it's a repo URL, look for common files
        if 'github.com' in url and '/blob/' not in url and '/raw/' not in url:
            # Try to fetch common deployment files
            repo_parts = url.rstrip('/').split('/')
            if len(repo_parts) >= 5:
                # Extract repo info for pre-built image detection
                repo_info = {
                    'org': repo_parts[3],
                    'repo': repo_parts[4]
                }

                base_raw = f"https://raw.githubusercontent.com/{repo_parts[3]}/{repo_parts[4]}/main"
                files_to_try = [
                    'kubernetes.yaml', 'k8s.yaml', 'deployment.yaml', 'deploy.yaml',
                    'docker-compose.yml', 'docker-compose.yaml', 'compose.yaml',
                    'Dockerfile', 'Chart.yaml'
                ]

                for f in files_to_try:
                    try:
                        test_url = f"{base_raw}/{f}"
                        req = urllib.request.Request(test_url, headers={'User-Agent': 'SIAB-Deployer'})
                        response = urllib.request.urlopen(req, timeout=10)
                        content = response.read().decode('utf-8')
                        filename = f
                        break
                    except urllib.error.HTTPError:
                        continue

                if not content:
                    # Try master branch
                    base_raw = f"https://raw.githubusercontent.com/{repo_parts[3]}/{repo_parts[4]}/master"
                    for f in files_to_try:
                        try:
                            test_url = f"{base_raw}/{f}"
                            req = urllib.request.Request(test_url, headers={'User-Agent': 'SIAB-Deployer'})
                            response = urllib.request.urlopen(req, timeout=10)
                            content = response.read().decode('utf-8')
                            filename = f
                            break
                        except urllib.error.HTTPError:
                            continue

        # Direct URL fetch (only for raw file URLs, not repo pages)
        if not content:
            # Don't try to fetch GitHub repo pages directly - they return HTML
            if 'github.com' in url and '/raw/' not in url and 'raw.githubusercontent.com' not in url:
                # This is a repo URL where we couldn't find any deployment files
                return jsonify({
                    'success': False,
                    'error': 'No deployment files found in repository. Looking for: Dockerfile, docker-compose.yml, kubernetes.yaml, Chart.yaml'
                }), 404

            try:
                req = urllib.request.Request(url, headers={'User-Agent': 'SIAB-Deployer'})
                response = urllib.request.urlopen(req, timeout=30)
                content = response.read().decode('utf-8')
                filename = url.split('/')[-1] or 'manifest.yaml'

                # Safety check: if we got HTML instead of expected content, fail
                if content.strip().startswith('<!DOCTYPE') or content.strip().startswith('<html'):
                    return jsonify({
                        'success': False,
                        'error': 'URL returned HTML instead of deployment content. Please provide a raw file URL.'
                    }), 400
            except Exception as e:
                return jsonify({'success': False, 'error': f'Failed to fetch URL: {str(e)}'}), 400

        if content:
            detected = detect_content_type(content, filename)
            # Add repo_info for pre-built image detection
            if repo_info:
                detected['repo_info'] = repo_info

            return jsonify({
                'success': True,
                'content': content,
                'filename': filename,
                'detected_type': detected,
                'repo_info': repo_info
            })
        else:
            return jsonify({'success': False, 'error': 'No deployable content found in repository'}), 404

    except Exception as e:
        logger.error(f"Fetch git error: {str(e)}")
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/deploy/smart', methods=['POST'])
def smart_deploy():
    """Smart deployment endpoint that handles all types with integrations"""
    try:
        data = request.get_json()
        name = data.get('name')
        namespace = data.get('namespace', 'default')
        content = data.get('content')
        content_type = data.get('type', 'unknown')
        integrations = data.get('integrations', {})
        port = data.get('port', 80)
        helm_values = data.get('helmValues', '')
        repo_info = data.get('repo_info')  # For pre-built image detection

        if not name or not content:
            return jsonify({'success': False, 'error': 'Name and content are required'}), 400

        # Validate name format
        if not re.match(r'^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$', name):
            return jsonify({'success': False, 'error': 'Invalid name format. Use lowercase letters, numbers, and hyphens.'}), 400

        # Ensure namespace exists with Istio injection
        ensure_namespace(namespace)

        # Process based on content type
        manifests = []
        service_name = name
        service_port = 80

        if content_type == 'manifest':
            # Direct manifest deployment
            result = run_command('kubectl apply -f -', input_data=content)
            if not result['success']:
                return jsonify({'success': False, 'error': result['stderr']}), 500

        elif content_type == 'compose':
            # Convert docker-compose to Kubernetes
            manifests = parse_docker_compose(content)
            for manifest in manifests:
                manifest['metadata']['namespace'] = namespace
                if 'labels' not in manifest['metadata']:
                    manifest['metadata']['labels'] = {}
                manifest['metadata']['labels']['deployed-by'] = 'siab-deployer'

                yaml_content = yaml.dump(manifest)
                result = run_command('kubectl apply -f -', input_data=yaml_content)
                if not result['success']:
                    logger.error(f"Failed to apply manifest: {result['stderr']}")

            # Use first service as main
            if manifests:
                service_name = manifests[0]['metadata']['name']

        elif content_type == 'dockerfile':
            # Build and deploy from Dockerfile (uses pre-built image if available)
            built_manifests, error = create_deployment_from_dockerfile(
                name, content, namespace, port, repo_info=repo_info
            )
            if error:
                return jsonify({'success': False, 'error': error}), 500

            for manifest in built_manifests:
                yaml_content = yaml.dump(manifest)
                result = run_command('kubectl apply -f -', input_data=yaml_content)
                if not result['success']:
                    return jsonify({'success': False, 'error': result['stderr']}), 500

            # Get port from the generated manifests
            service_port = 80
            for m in built_manifests:
                if m.get('kind') == 'Service':
                    ports = m.get('spec', {}).get('ports', [])
                    if ports:
                        service_port = ports[0].get('port', 80)

        elif content_type == 'helm':
            # Helm chart deployment
            with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
                if helm_values:
                    f.write(helm_values)
                f.flush()
                values_file = f.name

            try:
                cmd = f"helm install {name} - --namespace {namespace} --values {values_file}"
                result = run_command(cmd, input_data=content)
                if not result['success']:
                    return jsonify({'success': False, 'error': result['stderr']}), 500
            finally:
                os.unlink(values_file)

        else:
            # Try as raw manifest
            result = run_command('kubectl apply -f -', input_data=content)
            if not result['success']:
                return jsonify({'success': False, 'error': result['stderr']}), 500

        # Apply integrations
        access_url = None

        # Storage integration
        if integrations.get('storage'):
            storage_config = integrations['storage']
            create_pvc(
                name,
                namespace,
                size=storage_config.get('size', '10Gi'),
                mount_path=storage_config.get('mountPath', '/data')
            )

            # Patch deployment to add volume mount
            patch = {
                'spec': {
                    'template': {
                        'spec': {
                            'containers': [{
                                'name': name,
                                'volumeMounts': [{
                                    'name': 'data',
                                    'mountPath': storage_config.get('mountPath', '/data')
                                }]
                            }],
                            'volumes': [{
                                'name': 'data',
                                'persistentVolumeClaim': {
                                    'claimName': f'{name}-data'
                                }
                            }]
                        }
                    }
                }
            }
            patch_json = json.dumps(patch)
            run_command(f"kubectl patch deployment {name} -n {namespace} --type=strategic -p '{patch_json}'")

        # MinIO integration
        if integrations.get('minio'):
            create_minio_bucket_secret(name, namespace)

            # Patch deployment to add MinIO env vars
            patch = {
                'spec': {
                    'template': {
                        'spec': {
                            'containers': [{
                                'name': name,
                                'envFrom': [{
                                    'secretRef': {
                                        'name': f'{name}-minio'
                                    }
                                }]
                            }]
                        }
                    }
                }
            }
            patch_json = json.dumps(patch)
            run_command(f"kubectl patch deployment {name} -n {namespace} --type=strategic -p '{patch_json}'")

        # Ingress/Istio integration
        if integrations.get('ingress'):
            hostname = integrations.get('hostname') or f"{name}.{SIAB_DOMAIN}"
            create_ingress_route(namespace, service_name, service_port, hostname)
            access_url = f"https://{hostname}"

        # Keycloak integration (creates AuthorizationPolicy)
        if integrations.get('keycloak'):
            auth_policy = f"""
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: {name}-auth
  namespace: {namespace}
spec:
  selector:
    matchLabels:
      app: {name}
  action: CUSTOM
  provider:
    name: keycloak-auth
  rules:
    - to:
        - operation:
            paths: ["/*"]
"""
            run_command('kubectl apply -f -', input_data=auth_policy)

        # Generate and store credentials for apps that need them
        credentials_info = None
        apps_needing_credentials = [
            'nextcloud', 'wordpress', 'gitea', 'gitlab', 'jenkins',
            'grafana', 'minio', 'portainer', 'rancher', 'harbor',
            'keycloak', 'vault', 'consul', 'mysql', 'postgres',
            'mariadb', 'mongodb', 'redis', 'rabbitmq', 'elasticsearch'
        ]

        # Check if this app needs credentials
        app_lower = name.lower()
        needs_creds = any(app in app_lower for app in apps_needing_credentials)

        if needs_creds or integrations.get('generate_credentials'):
            admin_username = 'admin'
            admin_password = generate_password()

            # Store credentials in protected secret
            hostname = integrations.get('hostname') or f"{name}.{SIAB_DOMAIN}"
            extra_info = {
                'url': f"https://{hostname}",
                'notes': 'Set these credentials during first-time setup of the application'
            }

            # For apps that support OIDC, create Keycloak client
            oidc_apps = ['nextcloud', 'gitea', 'gitlab', 'grafana', 'portainer']
            if any(app in app_lower for app in oidc_apps):
                client_id, client_secret = create_keycloak_client_for_app(name, hostname)
                if client_id:
                    extra_info['oidc_client_id'] = client_id
                    extra_info['oidc_client_secret'] = client_secret
                    extra_info['oidc_issuer'] = 'https://keycloak.siab.local/realms/siab'
                    extra_info['oidc_notes'] = 'Configure OIDC in app settings to enable SSO with Keycloak'

            store_app_credentials(name, namespace, admin_username, admin_password, extra_info)

            credentials_info = {
                'username': admin_username,
                'password': admin_password,
                'stored_in': f'siab-system/app-creds-{name}',
                'notes': 'Use these credentials for initial setup. Credentials are stored securely in Kubernetes.'
            }
            if 'oidc_client_id' in extra_info:
                credentials_info['oidc'] = {
                    'client_id': extra_info['oidc_client_id'],
                    'issuer': extra_info['oidc_issuer'],
                    'notes': extra_info['oidc_notes']
                }

        return jsonify({
            'success': True,
            'message': f'Application {name} deployed successfully',
            'namespace': namespace,
            'access_url': access_url,
            'credentials': credentials_info,
            'integrations': {
                'istio': integrations.get('istio', True),
                'ingress': integrations.get('ingress', False),
                'keycloak': integrations.get('keycloak', False),
                'storage': bool(integrations.get('storage')),
                'minio': integrations.get('minio', False)
            }
        })

    except Exception as e:
        logger.error(f"Smart deploy error: {str(e)}")
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/deploy/manifest', methods=['POST'])
def deploy_manifest():
    """Deploy from raw Kubernetes manifest"""
    try:
        data = request.get_json()
        manifest_content = data.get('manifest')
        namespace = data.get('namespace', 'default')

        if not manifest_content:
            return jsonify({'error': 'No manifest provided'}), 400

        # Ensure namespace exists
        ensure_namespace(namespace)

        # Apply manifest
        result = run_command('kubectl apply -f -', input_data=manifest_content)

        if result['success']:
            return jsonify({
                'success': True,
                'message': 'Manifest deployed successfully',
                'output': result['stdout']
            })
        else:
            return jsonify({
                'success': False,
                'error': result['stderr']
            }), 500
    except Exception as e:
        logger.error(f"Deploy manifest error: {str(e)}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/deploy/helm', methods=['POST'])
def deploy_helm():
    """Deploy from Helm chart"""
    try:
        data = request.get_json()
        chart = data.get('chart')  # Can be chart name or URL
        release_name = data.get('name')
        namespace = data.get('namespace', 'default')
        values = data.get('values', {})

        if not chart or not release_name:
            return jsonify({'error': 'Chart and release name required'}), 400

        # Ensure namespace exists
        ensure_namespace(namespace)

        # Create values file
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            yaml.dump(values, f)
            values_file = f.name

        try:
            # Install helm chart
            cmd = f"helm install {release_name} {chart} --namespace {namespace} --values {values_file} --create-namespace"
            result = run_command(cmd)

            if result['success']:
                return jsonify({
                    'success': True,
                    'message': f'Helm chart {chart} deployed as {release_name}',
                    'output': result['stdout']
                })
            else:
                return jsonify({
                    'success': False,
                    'error': result['stderr']
                }), 500
        finally:
            os.unlink(values_file)
    except Exception as e:
        logger.error(f"Deploy helm error: {str(e)}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/deploy/compose', methods=['POST'])
def deploy_compose():
    """Deploy from docker-compose file"""
    try:
        data = request.get_json()
        compose_content = data.get('compose')
        namespace = data.get('namespace', 'default')

        if not compose_content:
            return jsonify({'error': 'No compose file provided'}), 400

        # Parse docker-compose
        manifests = parse_docker_compose(compose_content)

        # Ensure namespace exists
        ensure_namespace(namespace)

        # Apply each manifest
        results = []
        for manifest in manifests:
            # Add namespace to metadata
            if 'metadata' not in manifest:
                manifest['metadata'] = {}
            manifest['metadata']['namespace'] = namespace

            yaml_content = yaml.dump(manifest)
            result = run_command('kubectl apply -f -', input_data=yaml_content)
            results.append({
                'kind': manifest['kind'],
                'name': manifest['metadata']['name'],
                'success': result['success'],
                'output': result['stdout'] if result['success'] else result['stderr']
            })

        all_success = all(r['success'] for r in results)

        return jsonify({
            'success': all_success,
            'message': f"Deployed {len(manifests)} resources from docker-compose",
            'results': results
        }), 200 if all_success else 500
    except Exception as e:
        logger.error(f"Deploy compose error: {str(e)}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/deploy/dockerfile', methods=['POST'])
def deploy_dockerfile():
    """Deploy from Dockerfile"""
    try:
        data = request.get_json()
        dockerfile_content = data.get('dockerfile')
        name = data.get('name')
        namespace = data.get('namespace', 'default')
        port = data.get('port', 8080)

        if not dockerfile_content or not name:
            return jsonify({'error': 'Dockerfile and name required'}), 400

        # Ensure namespace exists
        ensure_namespace(namespace)

        # Create deployment from dockerfile
        manifests, error = create_deployment_from_dockerfile(
            name, dockerfile_content, namespace, port
        )

        if error:
            return jsonify({'success': False, 'error': error}), 500

        # Apply manifests
        results = []
        for manifest in manifests:
            yaml_content = yaml.dump(manifest)
            result = run_command('kubectl apply -f -', input_data=yaml_content)
            results.append({
                'kind': manifest['kind'],
                'name': manifest['metadata']['name'],
                'success': result['success']
            })

        all_success = all(r['success'] for r in results)

        return jsonify({
            'success': all_success,
            'message': f"Built and deployed {name} from Dockerfile",
            'results': results
        })
    except Exception as e:
        logger.error(f"Deploy dockerfile error: {str(e)}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/deploy/quick', methods=['POST'])
def deploy_quick():
    """Quick deploy with simple parameters"""
    try:
        data = request.get_json()
        name = data.get('name')
        image = data.get('image')
        namespace = data.get('namespace', 'default')
        port = data.get('port', 80)
        replicas = data.get('replicas', 1)
        env_vars = data.get('env', {})
        storage_size = data.get('storage_size')
        expose = data.get('expose', False)
        hostname = data.get('hostname')

        if not name or not image:
            return jsonify({'error': 'Name and image required'}), 400

        # Ensure namespace exists
        ensure_namespace(namespace)

        # Create deployment
        env_list = [{'name': k, 'value': str(v)} for k, v in env_vars.items()]

        deployment = {
            'apiVersion': 'apps/v1',
            'kind': 'Deployment',
            'metadata': {
                'name': name,
                'namespace': namespace,
                'labels': {
                    'app': name,
                    'deployed-by': 'siab-deployer'
                }
            },
            'spec': {
                'replicas': replicas,
                'selector': {
                    'matchLabels': {
                        'app': name
                    }
                },
                'template': {
                    'metadata': {
                        'labels': {
                            'app': name
                        }
                    },
                    'spec': {
                        'containers': [{
                            'name': name,
                            'image': image,
                            'ports': [{
                                'containerPort': port,
                                'name': 'http'
                            }],
                            'env': env_list
                        }]
                    }
                }
            }
        }

        # Add volume if storage requested
        if storage_size:
            pvc_name = f"{name}-data"
            create_pvc(name, namespace, storage_size)

            deployment['spec']['template']['spec']['containers'][0]['volumeMounts'] = [{
                'name': 'data',
                'mountPath': '/data'
            }]
            deployment['spec']['template']['spec']['volumes'] = [{
                'name': 'data',
                'persistentVolumeClaim': {
                    'claimName': pvc_name
                }
            }]

        # Apply deployment
        yaml_content = yaml.dump(deployment)
        result = run_command('kubectl apply -f -', input_data=yaml_content)

        if not result['success']:
            return jsonify({'success': False, 'error': result['stderr']}), 500

        # Create service
        service = {
            'apiVersion': 'v1',
            'kind': 'Service',
            'metadata': {
                'name': name,
                'namespace': namespace
            },
            'spec': {
                'selector': {
                    'app': name
                },
                'ports': [{
                    'port': 80,
                    'targetPort': port,
                    'name': 'http'
                }]
            }
        }

        yaml_content = yaml.dump(service)
        result = run_command('kubectl apply -f -', input_data=yaml_content)

        # Create ingress if requested
        if expose:
            create_ingress_route(namespace, name, 80, hostname)

        return jsonify({
            'success': True,
            'message': f"Application {name} deployed successfully",
            'access_url': f"https://{hostname or name + '.' + SIAB_DOMAIN}" if expose else None
        })
    except Exception as e:
        logger.error(f"Quick deploy error: {str(e)}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/applications', methods=['GET'])
def list_applications():
    """List all deployed applications"""
    try:
        namespace = request.args.get('namespace', 'default')

        if namespace == 'all':
            cmd = "kubectl get deployments -A -l deployed-by=siab-deployer -o json"
        else:
            cmd = f"kubectl get deployments -n {namespace} -l deployed-by=siab-deployer -o json"

        result = run_command(cmd)

        if not result['success']:
            # Try without label filter for backward compatibility
            if namespace == 'all':
                cmd = "kubectl get deployments -A -o json"
            else:
                cmd = f"kubectl get deployments -n {namespace} -o json"
            result = run_command(cmd)

        if not result['success']:
            return jsonify({'error': result['stderr']}), 500

        deployments = json.loads(result['stdout'])
        apps = []

        for item in deployments.get('items', []):
            metadata = item.get('metadata', {})
            spec = item.get('spec', {})
            status = item.get('status', {})

            # Skip system deployments
            ns = metadata.get('namespace', '')
            if ns in ['kube-system', 'istio-system', 'cert-manager', 'longhorn-system', 'gatekeeper-system']:
                continue

            apps.append({
                'name': metadata.get('name'),
                'namespace': metadata.get('namespace'),
                'replicas': spec.get('replicas'),
                'ready_replicas': status.get('readyReplicas', 0),
                'created': metadata.get('creationTimestamp'),
                'labels': metadata.get('labels', {})
            })

        return jsonify({'applications': apps})
    except Exception as e:
        logger.error(f"List applications error: {str(e)}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/applications/<name>', methods=['DELETE'])
def delete_application(name):
    """Delete deployed application"""
    try:
        namespace = request.args.get('namespace', 'default')

        # Delete deployment
        cmd = f"kubectl delete deployment {name} -n {namespace}"
        result = run_command(cmd)

        # Delete service
        run_command(f"kubectl delete service {name} -n {namespace}")

        # Delete virtualservice
        run_command(f"kubectl delete virtualservice {name} -n istio-system")

        # Delete PVC if exists
        run_command(f"kubectl delete pvc {name}-data -n {namespace}")

        # Delete MinIO secret if exists
        run_command(f"kubectl delete secret {name}-minio -n {namespace}")

        return jsonify({
            'success': result['success'],
            'message': f"Application {name} deleted"
        })
    except Exception as e:
        logger.error(f"Delete application error: {str(e)}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/applications/<name>/logs', methods=['GET'])
def get_application_logs(name):
    """Get application logs"""
    try:
        namespace = request.args.get('namespace', 'default')
        tail = request.args.get('tail', '100')

        cmd = f"kubectl logs -n {namespace} -l app={name} --tail={tail}"
        result = run_command(cmd)

        return jsonify({
            'success': result['success'],
            'logs': result['stdout'] if result['success'] else result['stderr']
        })
    except Exception as e:
        logger.error(f"Get logs error: {str(e)}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/applications/<name>', methods=['PATCH'])
def update_application(name):
    """Update application metadata (annotations for dashboard)"""
    try:
        data = request.get_json()
        namespace = request.args.get('namespace', 'default')

        # Build annotation patch
        annotations = {}
        if 'description' in data:
            annotations['siab.local/description'] = data['description']
        if 'icon' in data:
            annotations['siab.local/icon'] = data['icon']
        if 'category' in data:
            annotations['siab.local/category'] = data['category']
        if 'roles' in data:
            annotations['siab.local/roles'] = ','.join(data['roles']) if isinstance(data['roles'], list) else data['roles']
        if 'groups' in data:
            annotations['siab.local/groups'] = ','.join(data['groups']) if isinstance(data['groups'], list) else data['groups']

        if not annotations:
            return jsonify({'success': True, 'message': 'No updates provided'})

        # Patch the deployment
        patch = {'metadata': {'annotations': annotations}}
        patch_json = json.dumps(patch)

        cmd = f"kubectl patch deployment {name} -n {namespace} --type=merge -p '{patch_json}'"
        result = run_command(cmd)

        if result['success']:
            return jsonify({
                'success': True,
                'message': f'Application {name} updated'
            })
        else:
            return jsonify({
                'success': False,
                'error': result['stderr']
            }), 500

    except Exception as e:
        logger.error(f"Update application error: {str(e)}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/applications/<name>', methods=['GET'])
def get_application(name):
    """Get detailed application info"""
    try:
        namespace = request.args.get('namespace', 'default')

        cmd = f"kubectl get deployment {name} -n {namespace} -o json"
        result = run_command(cmd)

        if not result['success']:
            return jsonify({'error': 'Application not found'}), 404

        deployment = json.loads(result['stdout'])
        metadata = deployment.get('metadata', {})
        annotations = metadata.get('annotations', {})
        spec = deployment.get('spec', {})
        status = deployment.get('status', {})

        # Get pod status
        pod_cmd = f"kubectl get pods -n {namespace} -l app={name} -o json"
        pod_result = run_command(pod_cmd)
        pods = []
        if pod_result['success']:
            pod_data = json.loads(pod_result['stdout'])
            for pod in pod_data.get('items', []):
                pod_status = pod.get('status', {})
                pods.append({
                    'name': pod['metadata']['name'],
                    'phase': pod_status.get('phase'),
                    'ready': all(c.get('ready', False) for c in pod_status.get('containerStatuses', []))
                })

        return jsonify({
            'success': True,
            'application': {
                'name': name,
                'namespace': namespace,
                'description': annotations.get('siab.local/description', ''),
                'icon': annotations.get('siab.local/icon', ''),
                'category': annotations.get('siab.local/category', 'app'),
                'roles': annotations.get('siab.local/roles', '').split(',') if annotations.get('siab.local/roles') else [],
                'groups': annotations.get('siab.local/groups', '').split(',') if annotations.get('siab.local/groups') else [],
                'replicas': spec.get('replicas', 0),
                'ready_replicas': status.get('readyReplicas', 0),
                'image': spec.get('template', {}).get('spec', {}).get('containers', [{}])[0].get('image', ''),
                'created': metadata.get('creationTimestamp'),
                'pods': pods,
                'url': f"https://{name}.{SIAB_DOMAIN}/"
            }
        })

    except Exception as e:
        logger.error(f"Get application error: {str(e)}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/credentials/<name>', methods=['GET'])
def get_credentials(name):
    """Get stored credentials for an application (admin only)

    Credentials are stored in siab-system namespace which requires admin access.
    """
    try:
        creds = get_app_credentials(name)
        if creds:
            return jsonify({
                'success': True,
                'credentials': creds
            })
        else:
            return jsonify({
                'success': False,
                'error': f'No credentials found for {name}'
            }), 404
    except Exception as e:
        logger.error(f"Get credentials error: {str(e)}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/credentials', methods=['GET'])
def list_all_credentials():
    """List all stored application credentials (admin only)"""
    try:
        cmd = "kubectl get secrets -n siab-system -l siab.local/credential-type=app-credentials -o json"
        result = run_command(cmd)

        if not result['success']:
            return jsonify({'credentials': []})

        secrets_data = json.loads(result['stdout'])
        creds_list = []

        for secret in secrets_data.get('items', []):
            metadata = secret.get('metadata', {})
            labels = metadata.get('labels', {})
            data = secret.get('data', {})

            # Decode only non-sensitive fields for the list view
            creds_list.append({
                'name': labels.get('siab.local/app-name', metadata.get('name', '').replace('app-creds-', '')),
                'namespace': labels.get('siab.local/app-namespace', 'unknown'),
                'secret_name': metadata.get('name'),
                'created': metadata.get('creationTimestamp'),
                'has_oidc': 'oidc_client_id' in {base64.b64decode(k).decode() if k else '' for k in data.keys()}
            })

        return jsonify({'credentials': creds_list})
    except Exception as e:
        logger.error(f"List credentials error: {str(e)}")
        return jsonify({'credentials': []})


@app.route('/api/namespaces', methods=['GET'])
def list_namespaces():
    """List available namespaces"""
    try:
        result = run_command("kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'")
        if result['success']:
            namespaces = result['stdout'].strip().split()
            # Filter out system namespaces
            user_namespaces = [ns for ns in namespaces if ns not in [
                'kube-system', 'kube-public', 'kube-node-lease',
                'istio-system', 'cert-manager', 'longhorn-system',
                'gatekeeper-system', 'trivy-system', 'metallb-system'
            ]]
            return jsonify({'namespaces': ['default'] + sorted(user_namespaces)})
        return jsonify({'namespaces': ['default']})
    except Exception as e:
        logger.error(f"List namespaces error: {str(e)}")
        return jsonify({'namespaces': ['default']})


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
