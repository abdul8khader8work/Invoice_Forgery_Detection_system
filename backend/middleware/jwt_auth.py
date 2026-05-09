"""
JWT Authentication Middleware (Stub)
Feature-flagged additive authentication layer
"""
import os
from typing import Optional
from fastapi import HTTPException, Depends, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

# Feature flag for JWT auth
ENABLE_JWT_AUTH = os.getenv('ENABLE_JWT_AUTH', 'false').lower() == 'true'

security = HTTPBearer(auto_error=False)


def get_optional_auth(credentials: Optional[HTTPAuthorizationCredentials] = Depends(security)):
    """
    Optional authentication dependency.
    If JWT auth is disabled, returns None.
    If JWT auth is enabled, validates token and returns user info.
    """
    if not ENABLE_JWT_AUTH:
        return None
    
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    # Validate JWT token (stub implementation)
    # TODO: Replace with real JWT validation
    try:
        # For now, accept any token that starts with "Bearer"
        # In production, decode and validate JWT
        if credentials.credentials:
            return {"user_id": "stub_user", "token": credentials.credentials}
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token",
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Authentication failed: {str(e)}",
        )


def require_auth(user: dict = Depends(get_optional_auth)):
    """
    Require authentication dependency.
    Returns 401 if not authenticated.
    """
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user
