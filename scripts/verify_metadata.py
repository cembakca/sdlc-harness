
import asyncio
import os
import sys
from bson import ObjectId
from pprint import pprint

# Add server directory to path
sys.path.append(os.path.join(os.path.dirname(__file__), "../server"))

from app.core.database import get_database, connect_to_mongo, close_mongo_connection
from app.services.snapshots import SnapshotService



async def main():
    await connect_to_mongo()
    try:
        db = get_database()
        snapshot_service = SnapshotService(db)
        
        URL_ID = "698ce4d8077af457d65e12b4"
        print(f"🔍 Checking latest snapshot for URL ID: {URL_ID}")
        
        snapshot = await snapshot_service.collection.find_one(
            {"url_id": ObjectId(URL_ID), "status": "success"},
            sort=[("timestamp", -1)]
        )
        
        if not snapshot:
            print("❌ Snapshot not found")
            return

        SNAPSHOT_ID = str(snapshot["_id"])
        print(f"📸 Found snapshot: {SNAPSHOT_ID}")
        print(f"Status: {snapshot.get('status')}")
            
        print("\n--- Snapshot Data ---")
        pprint(snapshot.get("mobile", {}).get("metadata"))
        pprint(snapshot.get("desktop", {}).get("metadata"))
        
        if snapshot.get("mobile", {}).get("metadata"):
             print("✅ Mobile metadata found")
        else:
             print("❌ Mobile metadata MISSING")
             
        if snapshot.get("desktop", {}).get("metadata"):
             print("✅ Desktop metadata found")
        else:
             print("❌ Desktop metadata MISSING")

    except Exception as e:
        print(f"❌ Error: {e}")
    finally:
        await close_mongo_connection()

if __name__ == "__main__":
    asyncio.run(main())
