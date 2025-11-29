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

app = Flask(__name__, static_folder='/app/frontend', static_url_path='')
CORS(app)

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration
APPS_DIR = os.getenv('APPS_DIR', '/app/apps')
DEPLOYMENTS_DIR = os.getenv('DEPLOYMENTS_DIR', '/app/deployments')
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


def create_deployment_from_dockerfile(name, dockerfile_content, namespace, port=8080):
    """Create deployment from Dockerfile by building and deploying"""
    try:
        # Create temporary directory for build context
        with tempfile.TemporaryDirectory() as tmpdir:
            dockerfile_path = os.path.join(tmpdir, 'Dockerfile')
            with open(dockerfile_path, 'w') as f:
                f.write(dockerfile_content)

            # Build image using buildah (available in SIAB)
            image_name = f"localhost/{name}:latest"
            build_cmd = f"buildah bud -t {image_name} {tmpdir} 2>&1 || docker build -t {image_name} {tmpdir}"
            result = run_command(build_cmd)

            if not result['success']:
                return None, f"Build failed: {result['stderr']}"

            # Create deployment manifest
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
                                'image': image_name,
                                'imagePullPolicy': 'IfNotPresent',
                                'ports': [{
                                    'containerPort': port,
                                    'name': 'http'
                                }]
                            }]
                        }
                    }
                }
            }

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

            return [deployment, service], None
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

        # Direct URL fetch
        if not content:
            try:
                req = urllib.request.Request(url, headers={'User-Agent': 'SIAB-Deployer'})
                response = urllib.request.urlopen(req, timeout=30)
                content = response.read().decode('utf-8')
                filename = url.split('/')[-1] or 'manifest.yaml'
            except Exception as e:
                return jsonify({'success': False, 'error': f'Failed to fetch URL: {str(e)}'}), 400

        if content:
            return jsonify({
                'success': True,
                'content': content,
                'filename': filename,
                'detected_type': detect_content_type(content, filename)
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
            # Build and deploy from Dockerfile
            built_manifests, error = create_deployment_from_dockerfile(name, content, namespace, port)
            if error:
                return jsonify({'success': False, 'error': error}), 500

            for manifest in built_manifests:
                yaml_content = yaml.dump(manifest)
                result = run_command('kubectl apply -f -', input_data=yaml_content)
                if not result['success']:
                    return jsonify({'success': False, 'error': result['stderr']}), 500

            service_port = 80

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

        return jsonify({
            'success': True,
            'message': f'Application {name} deployed successfully',
            'namespace': namespace,
            'access_url': access_url,
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
