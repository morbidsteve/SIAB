#!/usr/bin/env python3
"""
SIAB Application Catalog API
Provides REST API for browsing and deploying pre-configured applications
"""

from flask import Flask, jsonify, request, send_from_directory
from flask_cors import CORS
import os
import yaml
import subprocess
import json
from datetime import datetime

app = Flask(__name__)
CORS(app)

# Configuration
APPS_DIR = os.path.join(os.path.dirname(__file__), '../apps')
DEPLOYED_APPS_FILE = '/tmp/siab-deployed-apps.json'

def load_deployed_apps():
    """Load list of deployed applications"""
    if os.path.exists(DEPLOYED_APPS_FILE):
        with open(DEPLOYED_APPS_FILE, 'r') as f:
            return json.load(f)
    return []

def save_deployed_apps(apps):
    """Save list of deployed applications"""
    with open(DEPLOYED_APPS_FILE, 'w') as f:
        json.dump(apps, f, indent=2)

def get_app_metadata(app_dir):
    """Extract metadata from app directory"""
    metadata_file = os.path.join(app_dir, 'metadata.yaml')
    manifest_file = os.path.join(app_dir, 'manifest.yaml')

    if not os.path.exists(metadata_file):
        return None

    with open(metadata_file, 'r') as f:
        metadata = yaml.safe_load(f)

    # Check if app is deployed
    deployed_apps = load_deployed_apps()
    is_deployed = metadata['id'] in [app['id'] for app in deployed_apps]
    metadata['deployed'] = is_deployed

    return metadata

@app.route('/api/categories', methods=['GET'])
def get_categories():
    """Get all application categories"""
    categories = {}

    for cat_dir in os.listdir(APPS_DIR):
        cat_path = os.path.join(APPS_DIR, cat_dir)
        if os.path.isdir(cat_path):
            count = len([d for d in os.listdir(cat_path)
                        if os.path.isdir(os.path.join(cat_path, d))])
            categories[cat_dir] = {
                'name': cat_dir.replace('-', ' ').title(),
                'count': count
            }

    return jsonify(categories)

@app.route('/api/apps', methods=['GET'])
def get_apps():
    """Get all available applications"""
    category = request.args.get('category')
    apps = []

    for cat_dir in os.listdir(APPS_DIR):
        cat_path = os.path.join(APPS_DIR, cat_dir)

        if category and cat_dir != category:
            continue

        if os.path.isdir(cat_path):
            for app_dir in os.listdir(cat_path):
                app_path = os.path.join(cat_path, app_dir)
                if os.path.isdir(app_path):
                    metadata = get_app_metadata(app_path)
                    if metadata:
                        metadata['category'] = cat_dir
                        apps.append(metadata)

    # Sort by name
    apps.sort(key=lambda x: x['name'])

    return jsonify(apps)

@app.route('/api/apps/<app_id>', methods=['GET'])
def get_app(app_id):
    """Get details for a specific application"""
    for cat_dir in os.listdir(APPS_DIR):
        cat_path = os.path.join(APPS_DIR, cat_dir)
        if os.path.isdir(cat_path):
            for app_dir in os.listdir(cat_path):
                app_path = os.path.join(cat_path, app_dir)
                metadata = get_app_metadata(app_path)
                if metadata and metadata['id'] == app_id:
                    # Include manifest
                    manifest_file = os.path.join(app_path, 'manifest.yaml')
                    with open(manifest_file, 'r') as f:
                        metadata['manifest'] = f.read()
                    return jsonify(metadata)

    return jsonify({'error': 'Application not found'}), 404

@app.route('/api/apps/<app_id>/deploy', methods=['POST'])
def deploy_app(app_id):
    """Deploy an application to the cluster"""
    data = request.json
    namespace = data.get('namespace', 'default')
    custom_values = data.get('values', {})

    # Find app
    for cat_dir in os.listdir(APPS_DIR):
        cat_path = os.path.join(APPS_DIR, cat_dir)
        if os.path.isdir(cat_path):
            for app_dir in os.listdir(cat_path):
                app_path = os.path.join(cat_path, app_dir)
                metadata = get_app_metadata(app_path)
                if metadata and metadata['id'] == app_id:
                    manifest_file = os.path.join(app_path, 'manifest.yaml')

                    try:
                        # Apply manifest
                        cmd = f'kubectl apply -f {manifest_file} -n {namespace}'
                        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)

                        if result.returncode == 0:
                            # Track deployment
                            deployed_apps = load_deployed_apps()
                            deployed_apps.append({
                                'id': app_id,
                                'name': metadata['name'],
                                'namespace': namespace,
                                'deployed_at': datetime.now().isoformat()
                            })
                            save_deployed_apps(deployed_apps)

                            return jsonify({
                                'success': True,
                                'message': f"{metadata['name']} deployed successfully",
                                'output': result.stdout
                            })
                        else:
                            return jsonify({
                                'success': False,
                                'error': result.stderr
                            }), 500

                    except Exception as e:
                        return jsonify({
                            'success': False,
                            'error': str(e)
                        }), 500

    return jsonify({'error': 'Application not found'}), 404

@app.route('/api/apps/<app_id>/undeploy', methods=['POST'])
def undeploy_app(app_id):
    """Remove an application from the cluster"""
    data = request.json
    namespace = data.get('namespace', 'default')

    # Find app
    for cat_dir in os.listdir(APPS_DIR):
        cat_path = os.path.join(APPS_DIR, cat_dir)
        if os.path.isdir(cat_path):
            for app_dir in os.listdir(cat_path):
                app_path = os.path.join(cat_path, app_dir)
                metadata = get_app_metadata(app_path)
                if metadata and metadata['id'] == app_id:
                    manifest_file = os.path.join(app_path, 'manifest.yaml')

                    try:
                        # Delete manifest
                        cmd = f'kubectl delete -f {manifest_file} -n {namespace}'
                        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)

                        # Remove from deployed list
                        deployed_apps = load_deployed_apps()
                        deployed_apps = [app for app in deployed_apps if app['id'] != app_id]
                        save_deployed_apps(deployed_apps)

                        return jsonify({
                            'success': True,
                            'message': f"{metadata['name']} removed successfully"
                        })

                    except Exception as e:
                        return jsonify({
                            'success': False,
                            'error': str(e)
                        }), 500

    return jsonify({'error': 'Application not found'}), 404

@app.route('/api/deployed', methods=['GET'])
def get_deployed():
    """Get list of deployed applications"""
    return jsonify(load_deployed_apps())

@app.route('/api/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({'status': 'ok', 'timestamp': datetime.now().isoformat()})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
