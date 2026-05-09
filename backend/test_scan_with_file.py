import requests
import os

# Create a test image file (simple text file for testing)
test_file_path = "test_invoice.txt"
with open(test_file_path, "w") as f:
    f.write("Invoice #123\nAmount: $100.00\nDate: 2024-01-01")

try:
    # Test scan endpoint with file
    with open(test_file_path, "rb") as f:
        files = {"file": f}
        response = requests.post('http://localhost:8000/api/scan', files=files, timeout=30)
        print(f"Scan Status: {response.status_code}")
        print(f"Scan Response: {response.text}")
        
        if response.status_code == 200:
            print("✅ Scan endpoint working correctly")
        else:
            print(f"❌ Scan failed with status {response.status_code}")
            
except Exception as e:
    print(f"Error: {e}")
finally:
    # Clean up test file
    if os.path.exists(test_file_path):
        os.remove(test_file_path)
