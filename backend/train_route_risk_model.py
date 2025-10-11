from flask import Flask, request, jsonify
import requests
import polyline
import firebase_admin
from firebase_admin import credentials, db
from flask_cors import CORS



app = Flask(__name__)
CORS(app)
# ✅ Firebase Initialization (with fallback)
try:
    print("🚀 Initializing Firebase...")
    cred = credentials.Certificate("serviceAccountKey.json")
    firebase_admin.initialize_app(cred, {
        'databaseURL': 'https://juantap-db-default-rtdb.firebaseio.com'
    })
    print("✅ Firebase connected successfully!")
    FIREBASE_OK = True
except Exception as e:
    print("⚠️ Firebase initialization failed:", e)
    FIREBASE_OK = False

# ✅ OpenRouteService API key (must be plain alphanumeric)
ORS_API_KEY = "eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6IjZkNTQ2YzZmZmE0ZDQ0Yzc5OWFiMTQ3Yzg2ZTllZTI5IiwiaCI6Im11cm11cjY0In0="  # e.g. 5b3ce3597851110001cf6248abc1234a


@app.route("/", methods=["GET"])
def index():
    return {"message": "Flask + Firebase + ORS API is running properly!"}


@app.route("/safe-route", methods=["POST"])
def safe_route():
    try:
        data = request.get_json(force=True)
        origin = data.get("origin")
        destination = data.get("destination")

        if not origin or not destination:
            return jsonify({"error": "Missing origin or destination"}), 400

        # 🔹 Load danger zones
        danger_zones = db.reference("danger_zones").get() or {}

        # 🔹 Request the main route from OpenRouteService
        ors_url = "https://api.openrouteservice.org/v2/directions/driving-car"
        headers = {
            "Authorization": ORS_API_KEY.strip(),
            "Content-Type": "application/json"
        }
        payload = {"coordinates": [origin, destination]}
        ors_response = requests.post(ors_url, json=payload, headers=headers)

        if ors_response.status_code != 200:
            return jsonify({"error": "ORS request failed", "details": ors_response.text}), 500

        ors_data = ors_response.json()
        route_geometry = ors_data["features"][0]["geometry"]["coordinates"]
        route_coords = [(lat, lng) for lng, lat in route_geometry]

        # 🔹 Compute if route intersects any danger zone
        risky_zones = []
        adjusted_points = []

        for (lat, lng) in route_coords:
            in_danger = False
            for zone_id, zone in danger_zones.items():
                zlat, zlng, zrad = zone["lat"], zone["lng"], zone["radius"]
                dist = ((lat - zlat)**2 + (lng - zlng)**2)**0.5 * 111000
                if dist <= zrad:
                    in_danger = True
                    risky_zones.append(zone["name"])
                    # Offset 100 m outward in same direction from zone center
                    offset_factor = (zrad + 100) / 111000
                    lat = zlat + (lat - zlat) * (offset_factor / (dist / 111000))
                    lng = zlng + (lng - zlng) * (offset_factor / (dist / 111000))
            adjusted_points.append((lat, lng))

        # 🔹 Generate new safe route request from adjusted points
        safe_start = [adjusted_points[0][1], adjusted_points[0][0]]
        safe_end = [adjusted_points[-1][1], adjusted_points[-1][0]]
        payload_safe = {"coordinates": [safe_start, safe_end]}
        ors_safe_response = requests.post(ors_url, json=payload_safe, headers=headers)
        if ors_safe_response.status_code != 200:
            return jsonify({
                "error": "Safe route request failed",
                "details": ors_safe_response.text
            }), 500

        ors_safe_data = ors_safe_response.json()
        safe_geometry = ors_safe_data["features"][0]["geometry"]["coordinates"]
        safe_route_coords = [(lat, lng) for lng, lat in safe_geometry]

        return jsonify({
            "status": "OK",
            "risky_zones": list(set(risky_zones)),
            "route_points_count": len(safe_route_coords),
            "safe_route": safe_route_coords
        })

    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == "__main__":
    print("🚦 Flask server starting up...")
    print("📋 Registered routes:")
    print(app.url_map)
    import os

    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port)
