import requests
import json

def test_connection():
    print("Testing Backend Connection...")
    
    # Test health endpoint
    try:
        response = requests.get('http://127.0.0.1:8000/health')
        print(f"Health Status: {response.status_code}")
        print(f"Health Response: {response.json()}")
    except Exception as e:
        print(f"Health Error: {e}")
        return False
    
    # Test scan endpoint with empty request
    try:
        response = requests.post('http://127.0.0.1:8000/scan')
        print(f"Scan Status: {response.status_code}")
        print(f"Scan Response: {response.text}")
    except Exception as e:
        print(f"Scan Error: {e}")
    
    return True

if __name__ == "__main__":
    test_connection()
    input("Press Enter to continue...")
