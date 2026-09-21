
import asyncio
import os
import sys
from datetime import datetime, timedelta
from bson import ObjectId
from pprint import pprint

# Add server directory to path
sys.path.append(os.path.join(os.path.dirname(__file__), "../server"))

from app.core.database import get_database, connect_to_mongo
from app.services.snapshots import get_snapshot_service

async def main():
    print("🚀 Starting Metadata Diff Test...")
    
    # 1. Connect to DB
    await connect_to_mongo()
    db = get_database()
    service = get_snapshot_service()
    
    # 2. Setup Test Data
    # Find or create a test URL
    url_collection = db.urls
    test_url = await url_collection.find_one({"url": "https://test-diff.com"})
    
    if not test_url:
        result = await url_collection.insert_one({
            "url": "https://test-diff.com",
            "name": "Test Diff URL",
            "project_id": ObjectId(), # Fake project ID
            "created_at": datetime.utcnow(),
            "is_active": True,
            "frequency": "manual"
        })
        url_id = str(result.inserted_id)
        print(f"Created test URL: {url_id}")
    else:
        url_id = str(test_url["_id"])
        print(f"Using test URL: {url_id}")

    # 3. Create Snapshot A (Baseline)
    print("\n📸 Creating Snapshot A (Baseline)...")
    snap_a = await service.create(url_id, "manual")
    snap_a_id = snap_a["_id"]
    
    # Mock data for A
    meta_a = {
        "title": "Old Title",
        "description": "Old Description",
        "robots": "index, follow",
        "canonical": "https://test-diff.com",
        "og_image": "https://test-diff.com/old.jpg"
    }
    
    # Manually complete A (to make it "success")
    await service.complete(
        snap_a_id,
        paths={"screenshot": "a.jpg", "html": "a.html"},
        metrics={"lcp": 100},
        mobile_data={"metrics": {"lcp": 100}, "metadata": meta_a, "http_status": 200},
        desktop_data={"metrics": {"lcp": 100}, "metadata": meta_a, "http_status": 200}
    )
    # Ensure it is older
    await service.collection.update_one(
        {"_id": ObjectId(snap_a_id)}, 
        {"$set": {"timestamp": datetime.utcnow() - timedelta(minutes=5)}}
    )
    print(f"Snapshot A completed ({snap_a_id}). Metadata: {meta_a['title']}")

    # 4. Create Snapshot B (Changed)
    print("\n📸 Creating Snapshot B (Changed)...")
    snap_b = await service.create(url_id, "manual")
    snap_b_id = snap_b["_id"]
    
    # Mock data for B (Different Title & Robots)
    meta_b = {
        "title": "New Title", # CHANGED
        "description": "Old Description",
        "robots": "noindex, nofollow", # CHANGED
        "canonical": "https://test-diff.com",
        "og_image": "https://test-diff.com/old.jpg"
    }
    
    # Complete B - This should trigger diff calculation because it finds A
    await service.complete(
        snap_b_id,
        paths={"screenshot": "b.jpg", "html": "b.html"},
        metrics={"lcp": 100},
        mobile_data={"metrics": {"lcp": 100}, "metadata": meta_b, "http_status": 200},
        desktop_data={"metrics": {"lcp": 100}, "metadata": meta_b, "http_status": 200}
    )
    
    # 5. Verify Results
    print("\n🔍 Verifying Snapshot B...")
    final_b = await service.get_by_id(snap_b_id)
    
    mobile_diff = final_b.get("mobile", {}).get("metadata_diff")
    
    if mobile_diff:
        print("✅ Metadata Diff Found!")
        pprint(mobile_diff)
        
        if mobile_diff.get("title_changed") and mobile_diff.get("prev_values", {}).get("title") == "Old Title":
             print("✅ Title change detected correctly.")
        else:
             print("❌ Title change NOT detected or wrong previous value.")
             
        if mobile_diff.get("robots_changed") and mobile_diff.get("prev_values", {}).get("robots") == "index, follow":
             print("✅ Robots change detected correctly.")
        else:
             print("❌ Robots change NOT detected.")
             
    else:
        print("❌ No Metadata Diff found in Snapshot B.")

    # Cleanup
    print("\nCleaning up test data...")
    await service.delete(snap_a_id)
    await service.delete(snap_b_id)
    await url_collection.delete_one({"_id": ObjectId(url_id)})
    
    print("Done.")

if __name__ == "__main__":
    asyncio.run(main())
