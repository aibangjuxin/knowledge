import os
import time
import ssl
from flask import Flask, jsonify, Blueprint, request

app = Flask(__name__)

# 1. Load Environment Variables
BASE_PATH = os.getenv('BASE_PATH', '/api/v1')
API_NAME = os.getenv('API_NAME', 'default-api') # User requested 'name'
MINOR_VERSION = os.getenv('MINOR_VERSION', '1.0.0')
HTTPS_CERT_PWD = os.getenv('HTTPS_CERT_PWD')

# Simulation state for Startup Probe
STARTUP_DELAY = 5 # seconds
start_time = time.time()

print(f"--- Configuration ---")
print(f"BASE_PATH: {BASE_PATH}")
print(f"API_NAME: {API_NAME}")
print(f"MINOR_VERSION: {MINOR_VERSION}")
print(f"HTTPS_CERT_PWD: {'******' if HTTPS_CERT_PWD else 'Not Set'}")
print(f"---------------------")

# Create a Blueprint to handle BASE_PATH
bp = Blueprint('app_routes', __name__, url_prefix=BASE_PATH)

@bp.route('/info', methods=['GET'])
def info():
    """Returns the API info including version and name."""
    return jsonify({
        "apiName": API_NAME,
        "minorVersion": MINOR_VERSION,
        "basePath": BASE_PATH
    })

# --- Probes ---

@bp.route('/well-known/liveness', methods=['GET'])
def liveness():
    """Liveness Probe: Is the process running?"""
    return jsonify({"status": "ALIVE"}), 200

@bp.route('/well-known/readiness', methods=['GET'])
def readiness():
    """Readiness Probe: Is the app ready to serve traffic?"""
    # Simulate a check (e.g., DB connection, cache warm-up)
    # For demo, we assume ready if started.
    return jsonify({"status": "READY"}), 200

@bp.route('/well-known/startup', methods=['GET'])
def startup():
    """Startup Probe: Has the app finished initializing?"""
    if time.time() - start_time < STARTUP_DELAY:
        # Simulate startup delay (e.g. loading ML models)
        return jsonify({"status": "INITIALIZING"}), 503
    return jsonify({"status": "STARTED"}), 200

# Register the blueprint
app.register_blueprint(bp)

@app.route('/')
def root():
    return f"Service running. Try paths starting with {BASE_PATH}"

if __name__ == '__main__':
    # SSL Context Configuration
    ssl_context = None
    cert_path = 'cert.pem'
    key_path = 'key.pem'

    if os.path.exists(cert_path) and os.path.exists(key_path):
        print("SSL Certificates found. Enabling HTTPS.")
        if HTTPS_CERT_PWD:
            print(f"Using HTTPS_CERT_PWD to unlock private key.")
            # Flask (Werkzeug) ssl_context tuple: (cert_file, key_file)
            # To use a password-protected key, we need an SSLContext object
            ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            ctx.load_cert_chain(certfile=cert_path, keyfile=key_path, password=HTTPS_CERT_PWD)
            ssl_context = ctx
        else:
            print("No HTTPS_CERT_PWD provided. Assuming unencrypted key.")
            ssl_context = (cert_path, key_path)
    else:
        print("Warning: 'cert.pem' or 'key.pem' not found. Running in HTTP mode.")

    app.run(host='0.0.0.0', port=8443, ssl_context=ssl_context)
