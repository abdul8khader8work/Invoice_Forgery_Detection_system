"""
Centralized Feature Flag Management
Provides safe, auditable control over Phase 4 production features
"""
from pydantic_settings import BaseSettings
from typing import Dict, Any, Optional
import os
from datetime import datetime
import json
from pathlib import Path


class FeatureFlags(BaseSettings):
    """Feature flag configuration with environment variable support"""
    
    # Phase 4 Production Features
    enable_jwt_auth: bool = False
    enable_async_scan: bool = False
    enable_db_v2: bool = False
    enable_security_hardening: bool = False
    
    # Additional Phase 5 Features
    enable_batch_upload: bool = False
    enable_analytics_dashboard: bool = False
    enable_offline_cache: bool = False
    enable_push_notifications: bool = False
    enable_auto_retrain: bool = False
    enable_celery: bool = False
    
    class Config:
        env_file = ".env"
        case_sensitive = False
        env_prefix = ""  # Direct env variable mapping (e.g., ENABLE_JWT_AUTH)
        extra = "ignore"  # Ignore extra fields like GROQ_API_KEY
    
    def get_flag_state(self, flag_name: str) -> Dict[str, Any]:
        """
        Get current state and metadata for a specific flag
        
        Args:
            flag_name: Name of the flag (e.g., "enable_jwt_auth")
            
        Returns:
            Dictionary with flag state, timestamp, and metadata
        """
        flag_value = getattr(self, flag_name, False)
        
        return {
            "flag_name": flag_name,
            "enabled": flag_value,
            "last_checked": datetime.utcnow().isoformat(),
            "config_source": "environment_variable"
        }
    
    def get_all_flags(self) -> Dict[str, Dict[str, Any]]:
        """
        Get state of all feature flags
        
        Returns:
            Dictionary mapping flag names to their states
        """
        flags = {}
        for field_name in self.model_fields:
            flags[field_name] = self.get_flag_state(field_name)
        return flags
    
    def is_enabled(self, flag_name: str) -> bool:
        """
        Check if a specific flag is enabled
        
        Args:
            flag_name: Name of the flag
            
        Returns:
            True if flag is enabled, False otherwise
        """
        return getattr(self, flag_name, False)
    
    def enable_flag(self, flag_name: str) -> None:
        """
        Enable a specific flag (runtime only - not persisted)
        
        Args:
            flag_name: Name of the flag to enable
        """
        if hasattr(self, flag_name):
            setattr(self, flag_name, True)
    
    def disable_flag(self, flag_name: str) -> None:
        """
        Disable a specific flag (runtime only - not persisted)
        
        Args:
            flag_name: Name of the flag to disable
        """
        if hasattr(self, flag_name):
            setattr(self, flag_name, False)


class FeatureFlagValidator:
    """Pre-flight validation for feature flags"""
    
    @staticmethod
    def validate_jwt_auth() -> Dict[str, Any]:
        """
        Validate prerequisites for JWT authentication
        
        Returns:
            Dictionary with validation result and details
        """
        issues = []
        warnings = []
        
        # Check JWT_SECRET
        jwt_secret = os.getenv("JWT_SECRET")
        if not jwt_secret:
            issues.append("JWT_SECRET environment variable not set")
        elif len(jwt_secret) < 32:
            issues.append("JWT_SECRET too weak (minimum 32 characters required)")
        
        # Check DATABASE_URL
        db_url = os.getenv("DATABASE_URL")
        if not db_url:
            issues.append("DATABASE_URL not set")
        elif not db_url.startswith("postgresql"):
            warnings.append("DATABASE_URL not using PostgreSQL (JWT auth requires PostgreSQL)")
        
        # Check for required files
        middleware_path = Path("middleware/jwt_auth.py")
        if not middleware_path.exists():
            issues.append("JWT auth middleware file missing: middleware/jwt_auth.py")
        
        return {
            "flag": "enable_jwt_auth",
            "ready": len(issues) == 0,
            "issues": issues,
            "warnings": warnings,
            "timestamp": datetime.utcnow().isoformat()
        }
    
    @staticmethod
    def validate_async_scan() -> Dict[str, Any]:
        """
        Validate prerequisites for async scan processing
        
        Returns:
            Dictionary with validation result and details
        """
        issues = []
        warnings = []
        
        # Check SSE manager
        sse_path = Path("tasks/sse_manager.py")
        if not sse_path.exists():
            issues.append("SSE manager file missing: tasks/sse_manager.py")
        
        # Check scan tasks
        scan_tasks_path = Path("tasks/scan_tasks.py")
        if not scan_tasks_path.exists():
            issues.append("Scan tasks file missing: tasks/scan_tasks.py")
        
        # Check Redis (optional)
        redis_url = os.getenv("REDIS_URL")
        if not redis_url:
            warnings.append("REDIS_URL not set (will use BackgroundTasks fallback)")
        
        return {
            "flag": "enable_async_scan",
            "ready": len(issues) == 0,
            "issues": issues,
            "warnings": warnings,
            "timestamp": datetime.utcnow().isoformat()
        }
    
    @staticmethod
    def validate_db_v2() -> Dict[str, Any]:
        """
        Validate prerequisites for PostgreSQL migration
        
        Returns:
            Dictionary with validation result and details
        """
        issues = []
        warnings = []
        
        # Check DATABASE_URL
        db_url = os.getenv("DATABASE_URL")
        if not db_url:
            issues.append("DATABASE_URL not set")
        elif not db_url.startswith("postgresql"):
            issues.append("DATABASE_URL must use PostgreSQL for DB V2")
        
        # Check migration script
        migration_path = Path("db/migrations/migrate_sqlite_to_postgres.py")
        if not migration_path.exists():
            issues.append("Migration script missing: db/migrations/migrate_sqlite_to_postgres.py")
        
        # Check PostgreSQL migration SQL
        sql_path = Path("db/migrations/001_init_postgres.sql")
        if not sql_path.exists():
            issues.append("PostgreSQL migration SQL missing: db/migrations/001_init_postgres.sql")
        
        # Check SQLite database (source for migration)
        sqlite_db = Path("invoice_dev.db")
        if not sqlite_db.exists():
            warnings.append("SQLite database not found (no data to migrate)")
        
        return {
            "flag": "enable_db_v2",
            "ready": len(issues) == 0,
            "issues": issues,
            "warnings": warnings,
            "timestamp": datetime.utcnow().isoformat()
        }
    
    @staticmethod
    def validate_security_hardening() -> Dict[str, Any]:
        """
        Validate prerequisites for security hardening
        
        Returns:
            Dictionary with validation result and details
        """
        issues = []
        warnings = []
        
        # Check security headers middleware
        headers_path = Path("middleware/security_headers.py")
        if not headers_path.exists():
            issues.append("Security headers middleware missing: middleware/security_headers.py")
        
        # Check rate limiter middleware
        rate_limiter_path = Path("middleware/rate_limiter.py")
        if not rate_limiter_path.exists():
            issues.append("Rate limiter middleware missing: middleware/rate_limiter.py")
        
        # Check file validation middleware
        file_validation_path = Path("middleware/file_validation.py")
        if not file_validation_path.exists():
            issues.append("File validation middleware missing: middleware/file_validation.py")
        
        # Check CORS configuration
        cors_origins = os.getenv("CORS_ORIGINS")
        if not cors_origins or cors_origins == "*":
            issues.append("CORS_ORIGINS not configured or set to wildcard (security risk)")
        
        # Check rate limit configuration
        rate_limit = os.getenv("RATE_LIMIT_REQUESTS_PER_MINUTE")
        if not rate_limit:
            warnings.append("RATE_LIMIT_REQUESTS_PER_MINUTE not configured")
        
        return {
            "flag": "enable_security_hardening",
            "ready": len(issues) == 0,
            "issues": issues,
            "warnings": warnings,
            "timestamp": datetime.utcnow().isoformat()
        }
    
    @classmethod
    def validate_all(cls) -> Dict[str, Dict[str, Any]]:
        """
        Validate all feature flags
        
        Returns:
            Dictionary mapping flag names to validation results
        """
        return {
            "enable_jwt_auth": cls.validate_jwt_auth(),
            "enable_async_scan": cls.validate_async_scan(),
            "enable_db_v2": cls.validate_db_v2(),
            "enable_security_hardening": cls.validate_security_hardening(),
        }


# Global feature flags instance
feature_flags = FeatureFlags()
feature_flag_validator = FeatureFlagValidator()


# Usage examples:
# if feature_flags.is_enabled("enable_jwt_auth"):
#     app.add_middleware(JWTAuthMiddleware)
#
# validation_result = feature_flag_validator.validate_jwt_auth()
# if validation_result["ready"]:
#     # Enable JWT auth
#     pass
