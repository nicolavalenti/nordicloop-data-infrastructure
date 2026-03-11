import os
import psycopg2
import requests
from dotenv import load_dotenv

load_dotenv()

AMPLITUDE_API_KEY = os.environ["AMPLITUDE_API_KEY"]

DB_PARAMS = {
    "database": "nordic_loop",
    "user": "nickvalenti",
    "host": "localhost",
    "port": "5432"
}

def send_batch(api_key, events):
    response = requests.post(
        "https://api.eu.amplitude.com/2/httpapi",
        json={"api_key": api_key, "events": events}
    )
    if response.status_code != 200:
        print(f"Error: {response.text}")
    return response.status_code

conn = psycopg2.connect(**DB_PARAMS)
cur = conn.cursor()
events = []

# Event 1: Item Uploaded
cur.execute("""
    SELECT mi.id, mi.org_id, mi.uploaded_by, mi.category_id, mi.status, mi.created_at,
           o.name AS org_name
    FROM material_items mi
    JOIN organisations o ON o.id = mi.org_id
""")
for row in cur.fetchall():
    events.append({
        "user_id": f"user_{row[2]}",
        "event_type": "Item Uploaded",
        "event_properties": {
            "item_id": row[0],
            "org": row[6],
            "category_id": row[3],
            "status": row[4]
        },
        "time": int(row[5].timestamp() * 1000)
    })

# Event 2: Item Classified
cur.execute("""
    SELECT ac.id, mi.uploaded_by, ac.llm_decision, ac.yolo_confidence_score,
           ac.model_version, ac.classified_at, o.name AS org_name
    FROM ai_classifications ac
    JOIN material_items mi ON mi.id = ac.material_item_id
    JOIN organisations o ON o.id = mi.org_id
""")
for row in cur.fetchall():
    events.append({
        "user_id": f"user_{row[1]}",
        "event_type": "Item Classified",
        "event_properties": {
            "llm_decision": row[2],
            "yolo_confidence": float(row[3]) if row[3] else None,
            "model_version": row[4],
            "org": row[6]
        },
        "time": int(row[5].timestamp() * 1000)
    })

# Event 3: Internal Match Completed
cur.execute("""
    SELECT im.id, im.requested_by, im.co2_saved_kg, im.status,
           im.completed_at, o.name AS org_name
    FROM internal_matches im
    JOIN organisations o ON o.id = im.org_id
    WHERE im.completed_at IS NOT NULL
""")
for row in cur.fetchall():
    events.append({
        "user_id": f"user_{row[1]}",
        "event_type": "Internal Match Completed",
        "event_properties": {
            "co2_saved_kg": float(row[2]) if row[2] else None,
            "status": row[3],
            "org": row[5]
        },
        "time": int(row[4].timestamp() * 1000)
    })

# Event 4: Item Listed Externally
cur.execute("""
    SELECT el.id, el.listed_by, el.asking_price_sek, el.status,
           el.listed_at, o.name AS org_name
    FROM external_listings el
    JOIN organisations o ON o.id = el.org_id
""")
for row in cur.fetchall():
    events.append({
        "user_id": f"user_{row[1]}",
        "event_type": "Item Listed Externally",
        "event_properties": {
            "asking_price_sek": float(row[2]) if row[2] else None,
            "status": row[3],
            "org": row[5]
        },
        "time": int(row[4].timestamp() * 1000)
    })

# Event 5: External Match Completed
cur.execute("""
    SELECT em.id, em.buyer_user_id, em.agreed_price_sek, em.co2_saved_kg,
           em.completed_at, o.name AS org_name
    FROM external_matches em
    JOIN organisations o ON o.id = em.seller_org_id
    WHERE em.completed_at IS NOT NULL
""")
for row in cur.fetchall():
    events.append({
        "user_id": f"user_{row[1]}",
        "event_type": "External Match Completed",
        "event_properties": {
            "agreed_price_sek": float(row[2]) if row[2] else None,
            "co2_saved_kg": float(row[3]) if row[3] else None,
            "org": row[5]
        },
        "time": int(row[4].timestamp() * 1000)
    })

# Send in batches of 100
print(f"Total events to send: {len(events)}")
for i in range(0, len(events), 100):
    batch = events[i:i+100]
    status = send_batch(AMPLITUDE_API_KEY, batch)
    print(f"Batch {i//100 + 1}: status {status}")

cur.close()
conn.close()
print("Done.")