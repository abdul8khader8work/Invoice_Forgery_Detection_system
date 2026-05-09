"""
Quick test script to verify /invoices endpoint
"""
import requests

print("Testing Backend Endpoints...")
print("=" * 50)

# Test health endpoint
print("\n1. Testing /health:")
try:
    response = requests.get("http://127.0.0.1:8000/health", timeout=5)
    print(f"   Status: {response.status_code}")
    print(f"   Response: {response.json()}")
except Exception as e:
    print(f"   ERROR: {e}")

# Test invoices endpoint
print("\n2. Testing /invoices:")
try:
    response = requests.get("http://127.0.0.1:8000/invoices", timeout=5)
    print(f"   Status: {response.status_code}")
    if response.status_code == 200:
        print(f"   Response: {response.json()}")
    else:
        print(f"   Error: {response.text}")
except Exception as e:
    print(f"   ERROR: {e}")

# Test root endpoint
print("\n3. Testing / (root):")
try:
    response = requests.get("http://127.0.0.1:8000/", timeout=5)
    print(f"   Status: {response.status_code}")
    print(f"   Response: {response.json()}")
except Exception as e:
    print(f"   ERROR: {e}")

print("\n" + "=" * 50)
print("Test complete!")
