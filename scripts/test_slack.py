
import asyncio
import os
import sys

# Add project root to path
sys.path.append(os.getcwd())

from server.app.services.notifications import SlackProvider

async def test_slack():
    webhook_url = input("Enter Slack Webhook URL: ").strip()
    if not webhook_url:
        print("Skipping test (no URL provided)")
        return

    provider = SlackProvider(webhook_url)
    print(f"Testing with URL: {webhook_url}...")
    
    success = await provider.send_alert(
        title="🚀 Crawlens Test Alert",
        message="This is a test notification from the HKA-001 implementation.",
        color="good",
        fields=[
            {"title": "Environment", "value": "Development", "short": True},
            {"title": "Status", "value": "Working", "short": True}
        ]
    )
    
    if success:
        print("✅ Notification sent successfully!")
    else:
        print("❌ Failed to send notification.")

if __name__ == "__main__":
    asyncio.run(test_slack())
