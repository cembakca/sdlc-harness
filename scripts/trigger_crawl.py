
import asyncio
import os
import sys
from bson import ObjectId



from app.core.database import get_database, connect_to_mongo, close_mongo_connection
from app.services.snapshots import SnapshotService
from app.workers.tasks import _perform_crawl

URL_ID = "698ce4d8077af457d65e12b4"

async def main():
    await connect_to_mongo()
    try:
        db = get_database()
        snapshot_service = SnapshotService(db)
        
        print(f"🚀 Triggering new crawl for URL ID: {URL_ID}")
        
        # Create new snapshot
        snapshot = await snapshot_service.create(
            url_id=URL_ID,
            trigger_source="manual"
        )
        
        if not snapshot:
            print("❌ Failed to create snapshot")
            return
            
        snapshot_id = str(snapshot["_id"])
        print(f"📸 Created snapshot: {snapshot_id}")
        
        print("🕷️ Starting crawl... (This might take a while)")
        
        # Queue crawl task via Celery
        from app.workers.tasks import crawl_url_task
        task = crawl_url_task.delay(
            url_id=URL_ID,
            snapshot_id=snapshot_id,
            trigger_source="manual"
        )
        
        print(f"🚀 Task queued: {task.id}")
        print("Check debug_crawler.py to monitor progress.")
            
    except Exception as e:
        print(f"❌ Script Error: {e}")
    finally:
        await close_mongo_connection()

if __name__ == "__main__":
    asyncio.run(main())
