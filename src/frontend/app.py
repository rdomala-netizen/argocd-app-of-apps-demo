from flask import Flask, jsonify
import requests
import os

app = Flask(__name__)

BACKEND_URL = os.getenv(
    "BACKEND_URL",
    "http://backend-svc:80/api/message"
)

@app.get("/")
def home():
    try:
        backend_response = requests.get(BACKEND_URL, timeout=3).json()
    except requests.RequestException as e:
        backend_response = {"error": f"backend unreachable: {e}"}

    return jsonify(
        service="frontend",
        ui_message="Hello from Frontend",
        backend_response=backend_response
    )

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=4000)
