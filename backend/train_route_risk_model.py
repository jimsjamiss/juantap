from flask import Flask, request, jsonify
import requests
import firebase_admin
from firebase_admin import credentials, db
from flask_cors import CORS
import joblib
import numpy as np
from datetime import datetime
import math
import json, os
import polyline

# ---------------------------------------------------------
# 🔹 Flask App Initialization
# ---------------------------------------------------------
app = Flask(__name__)
CORS(app)

# ---------------------------------------------------------
# 🔹 Firebase Initialization
# ---------------------------------------------------------
firebase_key_data = os.environ.get("FIREBASE_KEY")
if not firebase_key_data:
    raise ValueError("Missing FIREBASE_KEY environment variable!")

cred = credentials.Certificate(json.loads(firebase_key_data))

firebase_admin.initialize_app(cred, {
    'databaseURL': 'https://juantap-db-2dbeb-default-rtdb.firebaseio.com/'
})

# ---------------------------------------------------------
# 🔹 ORS API and Model
# ---------------------------------------------------------
ORS_API_KEY = "eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6IjZkNTQ2YzZmZmE0ZDQ0Yzc5OWFiMTQ3Yzg2ZTllZTI5IiwiaCI6Im11cm11cjY0In0="
MODEL_PATH = "route_safety_model.pkl"
model = joblib.load(MODEL_PATH)
print("✅ Random Forest model loaded")

# ---------------------------------------------------------
# 🔹 Default Route
# ---------------------------------------------------------
@app.route("/", methods=["GET"])
def home():
    return jsonify({"message": "Flask + Firebase + Random Forest API is running properly!"})

# ---------------------------------------------------------
# 🔹 Safe Route Prediction Endpoint
# ---------------------------------------------------------
@app.route("/ml-safe-route", methods=["POST"])
def ml_safe_route():
    try:
        # --- Step 1: Parse JSON safely ---
        print("📩 Raw Request Body:", request.data)

        if not request.data:
            return jsonify({"error": "Empty request body"}), 400

        raw_body = request.data.decode("utf-8").strip()
        print("📄 Decoded Body:", raw_body)

        data = json.loads(raw_body)
        print("✅ Parsed JSON:", data)

        origin = data.get("origin")
        destination = data.get("destination")

        if not origin or not destination:
            return jsonify({"error": "Missing 'origin' or 'destination' in request body"}), 400

        # --- Step 2: Get danger zones from Firebase ---
        danger_zones = db.reference("danger_zones").get() or {}
        print(f"📍 Loaded {len(danger_zones)} danger zones from Firebase")

        # --- Step 3: Fetch route from OpenRouteService ---
        ors_url = "https://api.openrouteservice.org/v2/directions/driving-car"
        headers = {"Authorization": ORS_API_KEY, "Content-Type": "application/json"}
        payload = {"coordinates": [origin, destination]}

        ors_response = requests.post(ors_url, json=payload, headers=headers)
        print("🛰 ORS Response Code:", ors_response.status_code)

        # Check ORS success
        if ors_response.status_code != 200:
            print("❌ ORS Error:", ors_response.text)
            return jsonify({"error": f"ORS request failed: {ors_response.text}"}), 400

        ors_data = ors_response.json()
        if "routes" not in ors_data or not ors_data["routes"]:
            return jsonify({"error": "No routes found from ORS"}), 400

        route_geometry = ors_data["routes"][0].get("geometry")
        if not route_geometry:
            return jsonify({"error": "ORS route missing geometry"}), 400

        # --- Step 4: Decode and analyze route ---
        route_coords = polyline.decode(route_geometry)
        results = []
        now = datetime.now().hour

        for lat, lng in route_coords:
            # Distance to nearest danger zone
            min_dist = float("inf")
            count_nearby = 0

            for zone in danger_zones.values():

                # Safe read with default radius
                zlat = zone.get("lat")
                zlng = zone.get("lng")
                zrad = zone.get("radius", 120)  # FIXED

                # Skip bad zones
                if zlat is None or zlng is None:
                    continue

                # Compute distance
                dist = math.sqrt((lat - zlat) ** 2 + (lng - zlng) ** 2) * 111000
                min_dist = min(min_dist, dist)

                if dist <= 500:
                    count_nearby += 1

            # Example dummy density
            route_density = np.random.randint(20, 100)

            # Predict risk
            features = np.array([[min_dist, count_nearby, now, route_density]])
            prediction = model.predict(features)[0]
            prob = model.predict_proba(features)[0][1]

            results.append({
                "lat": lat,
                "lng": lng,
                "distance_to_nearest_zone": round(min_dist, 2),
                "zones_within_500m": count_nearby,
                "risk_score": round(prob, 3),
                "prediction": "Danger" if prediction == 1 else "Safe"
            })

        # --- Step 5: Return JSON result ---
        return jsonify({
            "status": "OK",
            "point_count": len(results),
            "route_analysis": results
        }), 200

    except json.JSONDecodeError as e:
        print("❌ JSON Decode Error:", str(e))
        return jsonify({"error": f"Invalid JSON: {str(e)}"}), 400

    except Exception as e:
        import traceback
        traceback.print_exc()
        print("❌ Server Error:", str(e))
        return jsonify({"error": str(e)}), 500

# ---------------------------------------------------------
# 🔹 Allow all CORS requests
# ---------------------------------------------------------
@app.after_request
def after_request(response):
    response.headers.add('Access-Control-Allow-Origin', '*')
    response.headers.add('Access-Control-Allow-Headers', 'Content-Type,Authorization')
    response.headers.add('Access-Control-Allow-Methods', 'GET,POST,OPTIONS')
    return response

# ---------------------------------------------------------
# 🔹 Run the Flask app
# ---------------------------------------------------------
if __name__ == "__main__":
    import os
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port, debug=True)
