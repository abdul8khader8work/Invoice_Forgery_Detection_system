# Debug script to test scan endpoint
import requests
import json

# Test with a simple file
try:
    # Create a test file
    with open('test.txt', 'w') as f:
        f.write('Test invoice content')
    
    # Upload to backend
    with open('test.txt', 'rb') as f:
        files = {'file': ('test.txt', f, 'text/plain')}
        response = requests.post('http://127.0.0.1:8000/scan', files=files)
        
    print(f"Status Code: {response.status_code}")
    print(f"Response: {response.text}")
    
except Exception as e:
    print(f"Error: {e}")

input("Press Enter to continue...")
