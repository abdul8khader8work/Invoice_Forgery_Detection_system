import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import time

app = FastAPI(title="Debug Backend")

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
async def root():
    return {"message": "Debug Backend Running", "time": time.time()}

@app.get("/health")
async def health():
    return {"status": "healthy", "debug": True}

@app.post("/scan")
async def debug_scan():
    return {"message": "Scan endpoint reached", "debug": True}

if __name__ == "__main__":
    print("🔧 DEBUG BACKEND STARTING")
    print("📍 Available at: http://127.0.0.1:8000")
    print("📍 Available at: http://localhost:8000")
    print("📍 Available at: http://0.0.0.0:8000")
    
    uvicorn.run(app, host="127.0.0.1", port=8000, reload=True)
