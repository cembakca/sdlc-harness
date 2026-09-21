
import asyncio
import os
import sys
from datetime import datetime
from bson import ObjectId

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
        print(f"🔍 Checking latest snapshot for URL ID: {URL_ID}...")
    
        # Find latest snapshot
        snapshots = await snapshot_service.collection.find({"url_id": ObjectId(URL_ID)}).sort("timestamp", -1).limit(1).to_list(None)
        
        if not snapshots:
            print("❌ No snapshots found.")
            return

        print(f"⚠️ Found {len(snapshots)} snapshots.")
        
        for snap in snapshots:
            print(f"\n--- Snapshot {snap['_id']} ---")
            print(f"URL ID: {snap['url_id']}")
            print(f"Started: {snap['timestamp']}")
            print(f"Status: {snap['status']}")
            if snap.get("error_message"):
                 print(f"Message: {snap['error_message']}")
            
            # Print logs if available
            if "logs" in snap and snap["logs"]:
                print("\nAll Logs:")
                for log in snap["logs"]:
                    print(f"[{log['timestamp']}] [{log.get('device', 'SYSTEM')}] {log['message']}")
            else:
                print("\nNo logs found.")

    except Exception as e:
        print(f"❌ Error: {e}")
    finally:
        await close_mongo_connection()



if __name__ == "__main__":
    asyncio.run(main())
