import requests

# Test the scan endpoint with a simple request
print("Testing /scan endpoint...")

try:
    # Test with a minimal request
    response = requests.get("http://127.0.0.1:8000/health", timeout=5)
    print(f"Health check: {response.status_code}")
    print(f"Response: {response.json()}")
except Exception as e:
    print(f"Health check failed: {e}")

print("\nBackend must be running to see detailed errors.")
print("Check the backend console window for the full error traceback.")
