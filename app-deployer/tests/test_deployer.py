#!/usr/bin/env python3
"""
SIAB Application Deployer - Test Suite

Run with: pytest test_deployer.py -v
Or run directly: python test_deployer.py

Tests cover:
- API endpoint functionality
- Content type detection
- GitHub repo fetching
- Pre-built image detection
- Docker-compose parsing
- Kubernetes manifest generation
- Integration with cluster (if available)
"""

import os
import sys
import json
import unittest
from unittest.mock import patch, MagicMock

# Add parent directory to path for imports
import importlib.util
backend_dir = os.path.join(os.path.dirname(__file__), '..', 'backend')
spec = importlib.util.spec_from_file_location('api', os.path.join(backend_dir, 'app-deployer-api.py'))
api = importlib.util.module_from_spec(spec)
spec.loader.exec_module(api)


class TestContentTypeDetection(unittest.TestCase):
    """Test content type detection logic"""

    def test_detect_kubernetes_manifest(self):
        """Test detection of Kubernetes manifests"""
        manifest = """
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 3
"""
        result = api.detect_content_type(manifest, 'deployment.yaml')
        self.assertEqual(result['type'], 'manifest')
        self.assertIn('Deployment', result['kinds'])

    def test_detect_docker_compose(self):
        """Test detection of Docker Compose files"""
        compose = """
version: '3.8'
services:
  web:
    image: nginx:latest
    ports:
      - "80:80"
  db:
    image: postgres:15
"""
        result = api.detect_content_type(compose, 'docker-compose.yml')
        self.assertEqual(result['type'], 'compose')
        self.assertIn('web', result['services'])
        self.assertIn('db', result['services'])

    def test_detect_dockerfile(self):
        """Test detection of Dockerfiles"""
        dockerfile = """
FROM python:3.11-slim
RUN pip install flask
COPY . /app
CMD ["python", "/app/app.py"]
"""
        result = api.detect_content_type(dockerfile, 'Dockerfile')
        self.assertEqual(result['type'], 'dockerfile')
        self.assertIn('python:3.11-slim', result['base_image'])

    def test_detect_helm_chart(self):
        """Test detection of Helm Chart.yaml"""
        chart = """
apiVersion: v2
name: my-chart
description: A Helm chart
appVersion: "1.0.0"
version: 0.1.0
"""
        result = api.detect_content_type(chart, 'Chart.yaml')
        self.assertEqual(result['type'], 'helm')

    def test_detect_json_manifest(self):
        """Test detection of JSON Kubernetes manifests"""
        manifest = json.dumps({
            "apiVersion": "v1",
            "kind": "Service",
            "metadata": {"name": "my-service"},
            "spec": {"ports": [{"port": 80}]}
        })
        result = api.detect_content_type(manifest, 'service.json')
        self.assertEqual(result['type'], 'manifest')
        self.assertIn('Service', result['kinds'])


class TestPrebuiltImageDetection(unittest.TestCase):
    """Test pre-built image detection"""

    def test_linuxserver_image_detection(self):
        """Test detection of linuxserver pre-built images"""
        dockerfile = "FROM ghcr.io/linuxserver/baseimage-alpine:3.18"
        repo_info = {'org': 'linuxserver', 'repo': 'docker-wireshark'}

        image, port = api.check_prebuilt_image(dockerfile, repo_info)

        self.assertEqual(image, 'lscr.io/linuxserver/wireshark:latest')
        self.assertEqual(port, 3000)

    def test_linuxserver_plex_detection(self):
        """Test detection of plex image"""
        repo_info = {'org': 'linuxserver', 'repo': 'docker-plex'}
        image, port = api.check_prebuilt_image("FROM something", repo_info)

        self.assertEqual(image, 'lscr.io/linuxserver/plex:latest')

    def test_ghcr_image_in_dockerfile(self):
        """Test detection of ghcr.io references in Dockerfile"""
        dockerfile = """
FROM ghcr.io/someorg/someapp:v1.0
RUN echo hello
"""
        image, port = api.check_prebuilt_image(dockerfile)
        self.assertEqual(image, 'ghcr.io/someorg/someapp:latest')

    def test_no_prebuilt_for_custom_dockerfile(self):
        """Test that custom Dockerfiles don't return pre-built images"""
        dockerfile = """
FROM python:3.11-slim
RUN pip install flask
COPY . /app
"""
        image, port = api.check_prebuilt_image(dockerfile)
        self.assertIsNone(image)


class TestDockerComposeParsing(unittest.TestCase):
    """Test Docker Compose to Kubernetes conversion"""

    def test_basic_compose_parsing(self):
        """Test basic docker-compose.yml parsing"""
        compose = """
version: '3.8'
services:
  web:
    image: nginx:latest
    ports:
      - "8080:80"
"""
        manifests = api.parse_docker_compose(compose)

        # Should generate deployment and service
        self.assertEqual(len(manifests), 2)

        deployment = next(m for m in manifests if m['kind'] == 'Deployment')
        service = next(m for m in manifests if m['kind'] == 'Service')

        self.assertEqual(deployment['metadata']['name'], 'web')
        self.assertEqual(
            deployment['spec']['template']['spec']['containers'][0]['image'],
            'nginx:latest'
        )

    def test_compose_with_environment_list(self):
        """Test docker-compose with environment as list"""
        compose = """
services:
  app:
    image: myapp:latest
    environment:
      - DB_HOST=localhost
      - DB_PORT=5432
"""
        manifests = api.parse_docker_compose(compose)
        deployment = next(m for m in manifests if m['kind'] == 'Deployment')

        env_vars = deployment['spec']['template']['spec']['containers'][0]['env']
        env_names = [e['name'] for e in env_vars]

        self.assertIn('DB_HOST', env_names)
        self.assertIn('DB_PORT', env_names)

    def test_compose_with_environment_dict(self):
        """Test docker-compose with environment as dict"""
        compose = """
services:
  app:
    image: myapp:latest
    environment:
      DB_HOST: localhost
      DB_PORT: 5432
"""
        manifests = api.parse_docker_compose(compose)
        deployment = next(m for m in manifests if m['kind'] == 'Deployment')

        env_vars = deployment['spec']['template']['spec']['containers'][0]['env']
        env_names = [e['name'] for e in env_vars]

        self.assertIn('DB_HOST', env_names)
        self.assertIn('DB_PORT', env_names)

    def test_compose_multiple_services(self):
        """Test docker-compose with multiple services"""
        compose = """
services:
  frontend:
    image: nginx:latest
    ports:
      - "80:80"
  backend:
    image: python:3.11
    ports:
      - "5000:5000"
  db:
    image: postgres:15
    ports:
      - "5432:5432"
"""
        manifests = api.parse_docker_compose(compose)

        # 3 services * 2 resources (deployment + service) = 6 manifests
        self.assertEqual(len(manifests), 6)

        deployment_names = [m['metadata']['name'] for m in manifests if m['kind'] == 'Deployment']
        self.assertIn('frontend', deployment_names)
        self.assertIn('backend', deployment_names)
        self.assertIn('db', deployment_names)


class TestManifestGeneration(unittest.TestCase):
    """Test Kubernetes manifest generation"""

    def test_create_deployment_from_image(self):
        """Test creating deployment from pre-built image"""
        manifests, error = api.create_deployment_from_image(
            name='my-app',
            image='nginx:latest',
            namespace='default',
            port=80
        )

        self.assertIsNone(error)
        self.assertEqual(len(manifests), 2)

        deployment = manifests[0]
        self.assertEqual(deployment['kind'], 'Deployment')
        self.assertEqual(deployment['metadata']['name'], 'my-app')
        self.assertEqual(deployment['metadata']['namespace'], 'default')
        self.assertEqual(
            deployment['spec']['template']['spec']['containers'][0]['image'],
            'nginx:latest'
        )

    def test_create_deployment_with_env_vars(self):
        """Test deployment with environment variables"""
        env_vars = [
            {'name': 'FOO', 'value': 'bar'},
            {'name': 'BAZ', 'value': 'qux'}
        ]

        manifests, error = api.create_deployment_from_image(
            name='my-app',
            image='nginx:latest',
            namespace='default',
            port=80,
            env_vars=env_vars
        )

        deployment = manifests[0]
        container_env = deployment['spec']['template']['spec']['containers'][0]['env']

        self.assertEqual(len(container_env), 2)
        self.assertEqual(container_env[0]['name'], 'FOO')

    def test_deployment_labels(self):
        """Test that deployments have correct labels"""
        manifests, _ = api.create_deployment_from_image(
            name='test-app',
            image='nginx:latest',
            namespace='default',
            port=80
        )

        deployment = manifests[0]
        self.assertEqual(deployment['metadata']['labels']['app'], 'test-app')
        self.assertEqual(deployment['metadata']['labels']['deployed-by'], 'siab-deployer')


class TestAPIEndpoints(unittest.TestCase):
    """Test Flask API endpoints"""

    def setUp(self):
        """Set up test client"""
        api.app.config['TESTING'] = True
        self.client = api.app.test_client()

    def test_health_endpoint(self):
        """Test /health endpoint"""
        response = self.client.get('/health')
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertEqual(data['status'], 'healthy')

    def test_fetch_git_no_url(self):
        """Test fetch-git with no URL"""
        response = self.client.post(
            '/api/fetch-git',
            json={},
            content_type='application/json'
        )
        self.assertEqual(response.status_code, 400)
        data = json.loads(response.data)
        self.assertFalse(data['success'])

    def test_smart_deploy_missing_name(self):
        """Test smart deploy with missing name"""
        response = self.client.post(
            '/api/deploy/smart',
            json={'content': 'test'},
            content_type='application/json'
        )
        self.assertEqual(response.status_code, 400)
        data = json.loads(response.data)
        self.assertFalse(data['success'])

    def test_smart_deploy_invalid_name(self):
        """Test smart deploy with invalid name format"""
        response = self.client.post(
            '/api/deploy/smart',
            json={
                'name': 'Invalid_Name',
                'content': 'test',
                'type': 'manifest'
            },
            content_type='application/json'
        )
        self.assertEqual(response.status_code, 400)
        data = json.loads(response.data)
        self.assertIn('Invalid name format', data['error'])


class TestGitURLParsing(unittest.TestCase):
    """Test Git URL parsing and conversion"""

    def test_github_blob_url_conversion(self):
        """Test that GitHub blob URLs are converted to raw URLs"""
        # This tests the URL conversion logic
        url = 'https://github.com/user/repo/blob/main/file.yaml'
        expected = 'https://raw.githubusercontent.com/user/repo/main/file.yaml'

        if 'github.com' in url and '/blob/' in url:
            converted = url.replace('github.com', 'raw.githubusercontent.com').replace('/blob/', '/')
        else:
            converted = url

        self.assertEqual(converted, expected)

    def test_repo_info_extraction(self):
        """Test extraction of repo org/name from URL"""
        url = 'https://github.com/linuxserver/docker-wireshark'
        repo_parts = url.rstrip('/').split('/')

        if len(repo_parts) >= 5:
            repo_info = {
                'org': repo_parts[3],
                'repo': repo_parts[4]
            }
        else:
            repo_info = None

        self.assertEqual(repo_info['org'], 'linuxserver')
        self.assertEqual(repo_info['repo'], 'docker-wireshark')


class TestIntegrationWithCluster(unittest.TestCase):
    """Integration tests that require a running cluster

    These tests are skipped if kubectl is not available.
    """

    @classmethod
    def setUpClass(cls):
        """Check if cluster is available"""
        result = api.run_command('kubectl cluster-info')
        cls.cluster_available = result['success']

    def setUp(self):
        """Set up test client"""
        api.app.config['TESTING'] = True
        self.client = api.app.test_client()

    def test_namespace_creation(self):
        """Test namespace creation"""
        if not self.cluster_available:
            self.skipTest("Kubernetes cluster not available")

        result = api.ensure_namespace('test-deployer-ns')
        self.assertTrue(result)

        # Cleanup
        api.run_command('kubectl delete namespace test-deployer-ns --ignore-not-found')

    def test_list_namespaces(self):
        """Test listing namespaces"""
        if not self.cluster_available:
            self.skipTest("Kubernetes cluster not available")

        response = self.client.get('/api/namespaces')
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertIn('default', data['namespaces'])


class TestEdgeCases(unittest.TestCase):
    """Test edge cases and error handling"""

    def test_empty_compose_file(self):
        """Test handling of empty compose file"""
        with self.assertRaises(Exception):
            api.parse_docker_compose("")

    def test_invalid_yaml(self):
        """Test handling of invalid YAML"""
        invalid_yaml = "this: is: not: valid: yaml: ["
        result = api.detect_content_type(invalid_yaml)
        self.assertEqual(result['type'], 'unknown')

    def test_name_validation_edge_cases(self):
        """Test name validation with edge cases"""
        api.app.config['TESTING'] = True
        client = api.app.test_client()

        # Single character should be valid
        response = client.post(
            '/api/deploy/smart',
            json={'name': 'a', 'content': 'apiVersion: v1\nkind: Service'},
            content_type='application/json'
        )
        # May fail for other reasons but not name validation
        data = json.loads(response.data)
        self.assertNotIn('Invalid name format', data.get('error', ''))

        # Uppercase should be invalid
        response = client.post(
            '/api/deploy/smart',
            json={'name': 'MyApp', 'content': 'test'},
            content_type='application/json'
        )
        data = json.loads(response.data)
        self.assertIn('Invalid name format', data.get('error', ''))


def run_tests():
    """Run all tests and return results"""
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()

    # Add all test classes
    suite.addTests(loader.loadTestsFromTestCase(TestContentTypeDetection))
    suite.addTests(loader.loadTestsFromTestCase(TestPrebuiltImageDetection))
    suite.addTests(loader.loadTestsFromTestCase(TestDockerComposeParsing))
    suite.addTests(loader.loadTestsFromTestCase(TestManifestGeneration))
    suite.addTests(loader.loadTestsFromTestCase(TestAPIEndpoints))
    suite.addTests(loader.loadTestsFromTestCase(TestGitURLParsing))
    suite.addTests(loader.loadTestsFromTestCase(TestEdgeCases))
    suite.addTests(loader.loadTestsFromTestCase(TestIntegrationWithCluster))

    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)

    return result.wasSuccessful()


if __name__ == '__main__':
    success = run_tests()
    sys.exit(0 if success else 1)
