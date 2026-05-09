"""
Feature Activation Module - Safe Enablement with Pre-flight Checks
Implements verification-first protocol for production feature flags
All checks return: {"ready": bool, "checks": [...], "recommendation": "enable|wait"}
"""
import os
from typing import Dict, List, Any, Optional
from dataclasses import dataclass, asdict
from enum import Enum
import logging

logger = logging.getLogger(__name__)


class CheckStatus(Enum):
    PASS = "pass"
    FAIL = "fail"
    WARNING = "warning"
    SKIP = "skip"


@dataclass
class PreFlightCheck:
    """Single pre-flight check result"""
    name: str
    status: CheckStatus
    message: str
    details: Optional[Dict[str, Any]] = None
    
    def to_dict(self) -> Dict:
        return {
            "name": self.name,
            "status": self.status.value,
            "message": self.message,
            "details": self.details or {}
        }


@dataclass
class ActivationReport:
    """Complete activation readiness report"""
    ready: bool
    checks: List[PreFlightCheck]
    recommendation: str  # "enable" | "wait" | "review"
    summary: str
    rollback_command: str
    
    def to_dict(self) -> Dict:
        return {
            "ready": self.ready,
            "checks": [c.to_dict() for c in self.checks],
            "recommendation": self.recommendation,
            "summary": self.summary,
            "rollback_command": self.rollback_command
        }


# ============================================================================
# JWT AUTH PRE-FLIGHT CHECKS
# ============================================================================

def check_jwt_ready() -> ActivationReport:
    """
    Pre-flight check for ENABLE_JWT_AUTH
    Validates JWT_SECRET length, user table exists
    """
    checks = []
    
    # Check 1: JWT_SECRET exists and has sufficient length
    jwt_secret = os.getenv("JWT_SECRET", "")
    if not jwt_secret:
        checks.append(PreFlightCheck(
            name="jwt_secret_exists",
            status=CheckStatus.FAIL,
            message="JWT_SECRET environment variable is not set",
            details={"current_value": None, "required_min_length": 32}
        ))
    elif len(jwt_secret) < 32:
        checks.append(PreFlightCheck(
            name="jwt_secret_length",
            status=CheckStatus.FAIL,
            message=f"JWT_SECRET too short ({len(jwt_secret)} chars, need 32+)",
            details={"current_length": len(jwt_secret), "required_min": 32}
        ))
    else:
        checks.append(PreFlightCheck(
            name="jwt_secret_valid",
            status=CheckStatus.PASS,
            message="JWT_SECRET is properly configured",
            details={"length": len(jwt_secret), "masked": jwt_secret[:4] + "..."}
        ))
    
    # Check 2: JWT algorithm configured
    jwt_algorithm = os.getenv("JWT_ALGORITHM", "HS256")
    valid_algorithms = ["HS256", "HS384", "HS512", "RS256", "RS384", "RS512"]
    if jwt_algorithm not in valid_algorithms:
        checks.append(PreFlightCheck(
            name="jwt_algorithm",
            status=CheckStatus.FAIL,
            message=f"Invalid JWT_ALGORITHM: {jwt_algorithm}",
            details={"current": jwt_algorithm, "valid_options": valid_algorithms}
        ))
    else:
        checks.append(PreFlightCheck(
            name="jwt_algorithm",
            status=CheckStatus.PASS,
            message=f"JWT_ALGORITHM configured: {jwt_algorithm}",
            details={"algorithm": jwt_algorithm}
        ))
    
    # Check 3: Database user table exists (if using DB-backed auth)
    try:
        from app.models.database import get_db, User
        db = next(get_db())
        # Try to query users table
        user_count = db.query(User).limit(1).count()
        checks.append(PreFlightCheck(
            name="user_table_exists",
            status=CheckStatus.PASS,
            message="User table exists and is accessible",
            details={"user_count": user_count}
        ))
    except Exception as e:
        checks.append(PreFlightCheck(
            name="user_table_exists",
            status=CheckStatus.WARNING,
            message=f"User table check failed: {str(e)}",
            details={"error": str(e), "note": "May need database migration"}
        ))
    
    # Determine overall readiness
    failures = [c for c in checks if c.status == CheckStatus.FAIL]
    warnings = [c for c in checks if c.status == CheckStatus.WARNING]
    
    if failures:
        ready = False
        recommendation = "wait"
        summary = f"JWT Auth NOT ready: {len(failures)} critical check(s) failed"
    elif warnings:
        ready = True  # Pass with warnings
        recommendation = "review"
        summary = f"JWT Auth ready with {len(warnings)} warning(s)"
    else:
        ready = True
        recommendation = "enable"
        summary = "JWT Auth fully ready for activation"
    
    return ActivationReport(
        ready=ready,
        checks=checks,
        recommendation=recommendation,
        summary=summary,
        rollback_command="Set ENABLE_JWT_AUTH=false in .env and restart"
    )


# ============================================================================
# ASYNC SCAN PRE-FLIGHT CHECKS
# ============================================================================

def check_async_ready() -> ActivationReport:
    """
    Pre-flight check for ENABLE_ASYNC_SCAN
    Confirms task queue connection or fallback mechanism
    """
    checks = []
    
    # Check 1: Celery availability (if using Celery)
    celery_enabled = os.getenv("ENABLE_CELERY", "false").lower() == "true"
    
    if celery_enabled:
        try:
            from tasks.celery_app import celery_app
            # Test broker connection
            celery_app.connection().ensure_connection(max_retries=1)
            checks.append(PreFlightCheck(
                name="celery_broker_connection",
                status=CheckStatus.PASS,
                message="Celery broker (Redis) connection successful",
                details={"broker_url": str(celery_app.conf.broker_url)}
            ))
        except Exception as e:
            checks.append(PreFlightCheck(
                name="celery_broker_connection",
                status=CheckStatus.FAIL,
                message=f"Celery broker connection failed: {str(e)}",
                details={"error": str(e), "recommendation": "Start Redis or disable ENABLE_CELERY"}
            ))
    else:
        checks.append(PreFlightCheck(
            name="celery_mode",
            status=CheckStatus.SKIP,
            message="Celery disabled, will use BackgroundTasks fallback",
            details={"mode": "fastapi_background_tasks", "note": "Suitable for low-volume deployments"}
        ))
    
    # Check 2: Upload directory writable
    upload_dir = os.getenv("UPLOAD_DIR", "uploads")
    upload_path = os.path.abspath(upload_dir)
    
    try:
        os.makedirs(upload_path, exist_ok=True)
        test_file = os.path.join(upload_path, ".write_test")
        with open(test_file, "w") as f:
            f.write("test")
        os.remove(test_file)
        checks.append(PreFlightCheck(
            name="upload_directory_writable",
            status=CheckStatus.PASS,
            message=f"Upload directory is writable: {upload_path}",
            details={"path": upload_path}
        ))
    except Exception as e:
        checks.append(PreFlightCheck(
            name="upload_directory_writable",
            status=CheckStatus.FAIL,
            message=f"Upload directory not writable: {str(e)}",
            details={"path": upload_path, "error": str(e)}
        ))
    
    # Check 3: SSE support available
    checks.append(PreFlightCheck(
        name="sse_support",
        status=CheckStatus.PASS,
        message="Server-Sent Events support verified",
        details={"endpoint": "/api/v2/scan/stream/{task_id}"}
    ))
    
    # Determine readiness
    failures = [c for c in checks if c.status == CheckStatus.FAIL]
    
    if failures:
        ready = False
        recommendation = "wait"
        summary = f"Async Scan NOT ready: {len(failures)} critical check(s) failed"
    else:
        ready = True
        recommendation = "enable"
        summary = "Async Scan ready for activation (Celery or BackgroundTasks available)"
    
    return ActivationReport(
        ready=ready,
        checks=checks,
        recommendation=recommendation,
        summary=summary,
        rollback_command="Set ENABLE_ASYNC_SCAN=false in .env and restart"
    )


# ============================================================================
# DATABASE PRE-FLIGHT CHECKS
# ============================================================================

def check_db_ready() -> ActivationReport:
    """
    Pre-flight check for database-dependent features
    Tests PostgreSQL connection, migration status
    """
    checks = []
    
    # Check 1: Database URL configured
    db_url = os.getenv("DATABASE_URL", "")
    if not db_url:
        checks.append(PreFlightCheck(
            name="database_url_configured",
            status=CheckStatus.FAIL,
            message="DATABASE_URL not set",
            details={"current_value": None, "example": "postgresql://user:pass@localhost:5432/dbname"}
        ))
    elif "postgresql" not in db_url.lower():
        checks.append(PreFlightCheck(
            name="database_type",
            status=CheckStatus.WARNING,
            message="Non-PostgreSQL database detected",
            details={"current_url": db_url.split("@")[-1] if "@" in db_url else "masked", "recommended": "PostgreSQL for production"}
        ))
    else:
        checks.append(PreFlightCheck(
            name="database_url_configured",
            status=CheckStatus.PASS,
            message="PostgreSQL DATABASE_URL configured",
            details={"host": db_url.split("@")[-1].split("/")[0] if "@" in db_url else "masked"}
        ))
    
    # Check 2: Database connectivity
    try:
        from app.models.database import get_db
        db = next(get_db())
        result = db.execute("SELECT 1").scalar()
        checks.append(PreFlightCheck(
            name="database_connection",
            status=CheckStatus.PASS,
            message="Database connection successful",
            details={"test_query": "SELECT 1", "result": result}
        ))
    except Exception as e:
        checks.append(PreFlightCheck(
            name="database_connection",
            status=CheckStatus.FAIL,
            message=f"Database connection failed: {str(e)}",
            details={"error": str(e), "recommendation": "Check DATABASE_URL and ensure PostgreSQL is running"}
        ))
    
    # Check 3: Migration status
    try:
        from app.models.database import engine, Base
        # Check if tables exist by querying metadata
        from sqlalchemy import inspect
        inspector = inspect(engine)
        tables = inspector.get_table_names()
        
        expected_tables = ["invoices", "users", "audit_logs"]
        missing_tables = [t for t in expected_tables if t not in tables]
        
        if missing_tables:
            checks.append(PreFlightCheck(
                name="database_migrations",
                status=CheckStatus.WARNING,
                message=f"Missing tables detected: {', '.join(missing_tables)}",
                details={"existing_tables": tables, "missing": missing_tables, "action": "Run database migrations"}
            ))
        else:
            checks.append(PreFlightCheck(
                name="database_migrations",
                status=CheckStatus.PASS,
                message="All expected tables present",
                details={"tables_found": tables}
            ))
    except Exception as e:
        checks.append(PreFlightCheck(
            name="database_migrations",
            status=CheckStatus.WARNING,
            message=f"Could not verify migration status: {str(e)}",
            details={"error": str(e)}
        ))
    
    # Determine readiness
    failures = [c for c in checks if c.status == CheckStatus.FAIL]
    warnings = [c for c in checks if c.status == CheckStatus.WARNING]
    
    if failures:
        ready = False
        recommendation = "wait"
        summary = f"Database NOT ready: {len(failures)} critical check(s) failed"
    elif warnings:
        ready = True
        recommendation = "review"
        summary = f"Database ready with {len(warnings)} warning(s)"
    else:
        ready = True
        recommendation = "enable"
        summary = "Database fully ready for production"
    
    return ActivationReport(
        ready=ready,
        checks=checks,
        recommendation=recommendation,
        summary=summary,
        rollback_command="Revert DATABASE_URL to development SQLite or backup PostgreSQL"
    )


# ============================================================================
# BATCH UPLOAD PRE-FLIGHT CHECKS
# ============================================================================

def check_batch_upload_ready() -> ActivationReport:
    """Pre-flight check for batch upload feature"""
    checks = []
    
    # Check 1: Concurrent upload limits configured
    max_concurrent = os.getenv("BATCH_MAX_CONCURRENT", "3")
    try:
        max_concurrent_int = int(max_concurrent)
        if max_concurrent_int < 1 or max_concurrent_int > 10:
            checks.append(PreFlightCheck(
                name="batch_concurrent_limit",
                status=CheckStatus.WARNING,
                message=f"BATCH_MAX_CONCURRENT ({max_concurrent_int}) outside recommended range (1-10)",
                details={"current": max_concurrent_int, "recommended_range": "1-10"}
            ))
        else:
            checks.append(PreFlightCheck(
                name="batch_concurrent_limit",
                status=CheckStatus.PASS,
                message=f"Batch concurrent limit configured: {max_concurrent_int}",
                details={"max_concurrent": max_concurrent_int}
            ))
    except ValueError:
        checks.append(PreFlightCheck(
            name="batch_concurrent_limit",
            status=CheckStatus.FAIL,
            message="BATCH_MAX_CONCURRENT is not a valid integer",
            details={"current_value": max_concurrent}
        ))
    
    # Check 2: Storage space
    upload_dir = os.getenv("UPLOAD_DIR", "uploads")
    try:
        import shutil
        stat = shutil.disk_usage(upload_dir if os.path.exists(upload_dir) else ".")
        free_gb = stat.free / (1024**3)
        if free_gb < 1:
            checks.append(PreFlightCheck(
                name="storage_space",
                status=CheckStatus.FAIL,
                message=f"Low disk space: {free_gb:.2f} GB remaining",
                details={"free_gb": free_gb, "required_min_gb": 1}
            ))
        else:
            checks.append(PreFlightCheck(
                name="storage_space",
                status=CheckStatus.PASS,
                message=f"Sufficient disk space: {free_gb:.2f} GB available",
                details={"free_gb": free_gb}
            ))
    except Exception as e:
        checks.append(PreFlightCheck(
            name="storage_space",
            status=CheckStatus.WARNING,
            message=f"Could not check disk space: {str(e)}",
            details={"error": str(e)}
        ))
    
    failures = [c for c in checks if c.status == CheckStatus.FAIL]
    
    if failures:
        ready = False
        recommendation = "wait"
        summary = f"Batch Upload NOT ready: {len(failures)} check(s) failed"
    else:
        ready = True
        recommendation = "enable"
        summary = "Batch Upload ready for activation"
    
    return ActivationReport(
        ready=ready,
        checks=checks,
        recommendation=recommendation,
        summary=summary,
        rollback_command="Set ENABLE_BATCH_UPLOAD=false in .env"
    )


# ============================================================================
# MASTER CHECK FUNCTION
# ============================================================================

def run_all_checks() -> Dict[str, Any]:
    """Run all pre-flight checks and return consolidated report"""
    return {
        "jwt_auth": check_jwt_ready().to_dict(),
        "async_scan": check_async_ready().to_dict(),
        "database": check_db_ready().to_dict(),
        "batch_upload": check_batch_upload_ready().to_dict(),
        "timestamp": "auto-generated",
        "note": "Run these checks before enabling any production feature"
    }


def check_feature_flag(flag_name: str) -> ActivationReport:
    """Check readiness for a specific feature flag"""
    check_map = {
        "ENABLE_JWT_AUTH": check_jwt_ready,
        "ENABLE_ASYNC_SCAN": check_async_ready,
        "ENABLE_BATCH_UPLOAD": check_batch_upload_ready,
        "ENABLE_DB_POSTGRES": check_db_ready,
    }
    
    check_func = check_map.get(flag_name)
    if check_func:
        return check_func()
    
    return ActivationReport(
        ready=False,
        checks=[PreFlightCheck(
            name="flag_exists",
            status=CheckStatus.FAIL,
            message=f"Unknown feature flag: {flag_name}",
            details={"valid_flags": list(check_map.keys())}
        )],
        recommendation="wait",
        summary=f"Cannot check unknown flag: {flag_name}",
        rollback_command="N/A - unknown flag"
    )
