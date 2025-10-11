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


@app.route("/safe-route", methods=["POST", "GET"])
def safe_route():
    try:
        if request.method == "GET":
            return jsonify({"message": "Use POST with origin and destination."})

        data = request.get_json(force=True)
        origin = data.get("origin")
        destination = data.get("destination")

        if not origin or not destination:
            return jsonify({"error": "Missing origin or destination"}), 400

        # 🔹 Step 1: Load danger zones
        danger_zones = {}
        if FIREBASE_OK:
            try:
                danger_zones = db.reference("danger_zones").get() or {}
                print(f"📍 Loaded {len(danger_zones)} danger zones from Firebase.")
            except Exception as e:
                print("⚠️ Could not load danger zones:", e)
        else:
            print("⚠️ Skipping Firebase (not connected).")

        # 🔹 Step 2: Call OpenRouteService
        ors_url = "https://api.openrouteservice.org/v2/directions/driving-car"
        headers = {
            "Authorization": ORS_API_KEY.strip(),
            "Content-Type": "application/json"
        }
        payload = {"coordinates": [origin, destination]}
        ors_response = requests.post(ors_url, json=payload, headers=headers)
        ors_data = ors_response.json()

        print("🔁 ORS Response Code:", ors_response.status_code)
        print("📦 ORS Keys:", list(ors_data.keys()))

        # 🔹 Step 3: Decode geometry (handle both formats)
        route_coords = []
        if "features" in ors_data:
            route_geometry = ors_data["features"][0]["geometry"]["coordinates"]
            route_coords = [(lat, lng) for lng, lat in route_geometry]
        elif "routes" in ors_data:
            encoded_polyline = ors_data["routes"][0]["geometry"]
            route_coords = [(lat, lng) for lat, lng in polyline.decode(encoded_polyline)]
        else:
            return jsonify({
                "error": "No valid route found in ORS response",
                "details": ors_data
            }), 500

        # 🔹 Step 4: Danger zone proximity
        risky_points = []
        for lat, lng in route_coords:
            for zone_id, zone in danger_zones.items():
                zlat, zlng, zrad = zone.get("lat"), zone.get("lng"), zone.get("radius")
                if zlat and zlng and zrad:
                    distance = ((lat - zlat) ** 2 + (lng - zlng) ** 2) ** 0.5 * 111000
                    if distance < zrad:
                        risky_points.append({
                            "zone": zone.get("name", "Unnamed Zone"),
                            "distance_m": round(distance, 1),
                            "location": {"lat": lat, "lng": lng}
                        })

        risk_level = "High" if risky_points else "Low"

        return jsonify({
            "status": "OK",
            "risk_level": risk_level,
            "risky_points": risky_points,
            "route_points_count": len(route_coords),
            "sample_points": route_coords[:5]
        })

    except Exception as e:
        print("🔥 Exception:", e)
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    print("🚦 Flask server starting up...")
    print("📋 Registered routes:")
    print(app.url_map)
    app.run(debug=True)
