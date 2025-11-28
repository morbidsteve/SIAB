#!/usr/bin/env python3
"""
SIAB Application Deployer API
Handles deployment of applications from various sources:
- Raw Kubernetes manifests
- Helm charts
- Dockerfiles
- docker-compose files

Automatically integrates with:
- Longhorn for persistent storage
- Keycloak for authentication
- Istio for service mesh
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

app = Flask(__name__)
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


def create_pvc(name, namespace, size='10Gi', storage_class='longhorn'):
    """Create PersistentVolumeClaim with Longhorn"""
    pvc = f"""
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {name}
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
                        container_port = int(parts[1])
                    else:
                        host_port = container_port = int(parts[0])
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
                    if '=' in env:
                        key, value = env.split('=', 1)
                        env_vars.append({'name': key, 'value': value})
            elif isinstance(environment, dict):
                for key, value in environment.items():
                    env_vars.append({'name': key, 'value': str(value)})

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
                                'ports': container_ports,
                                'env': env_vars
                            }]
                        }
                    }
                }
            }

            manifests.append(deployment)

            # Create service if ports are defined
            if service_ports:
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
                        'ports': service_ports
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

            # Build image (requires docker or buildah)
            image_name = f"{name}:latest"
            build_cmd = f"docker build -t {image_name} {tmpdir}"
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


@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({'status': 'healthy', 'timestamp': datetime.now().isoformat()})


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
            cmd = f"helm install {release_name} {chart} --namespace {namespace} --values {values_file}"
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
            create_pvc(pvc_name, namespace, storage_size)

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

        cmd = f"kubectl get deployments -n {namespace} -l deployed-by=siab-deployer -o json"
        result = run_command(cmd)

        if not result['success']:
            return jsonify({'error': result['stderr']}), 500

        deployments = json.loads(result['stdout'])
        apps = []

        for item in deployments.get('items', []):
            metadata = item.get('metadata', {})
            spec = item.get('spec', {})
            status = item.get('status', {})

            apps.append({
                'name': metadata.get('name'),
                'namespace': metadata.get('namespace'),
                'replicas': spec.get('replicas'),
                'ready_replicas': status.get('readyReplicas', 0),
                'created': metadata.get('creationTimestamp')
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

        return jsonify({
            'success': result['success'],
            'message': f"Application {name} deleted"
        })
    except Exception as e:
        logger.error(f"Delete application error: {str(e)}")
        return jsonify({'error': str(e)}), 500


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
