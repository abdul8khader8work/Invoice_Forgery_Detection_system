"""
Configuration for automated model retraining pipeline
Feature flag: ENABLE_AUTO_RETRAIN (default: false)
"""
from pydantic_settings import BaseSettings
from typing import Optional


class RetrainingConfig(BaseSettings):
    """Configuration for automated model retraining"""
    
    # Feature flag
    enable_auto_retrain: bool = False
    
    # Retraining thresholds
    min_new_samples: int = 100  # Minimum new samples before retraining
    max_drift_threshold: float = 0.15  # Max data drift before retraining needed
    min_accuracy_threshold: float = 0.85  # Minimum acceptable accuracy
    
    # Scheduling
    retrain_schedule: str = "weekly"  # Options: daily, weekly, monthly
    retrain_hour: int = 2  # Hour of day to run (0-23)
    retrain_day: Optional[int] = 0  # Day of week (0=Sunday) for weekly, or day of month for monthly
    
    # Model validation
    validation_split: float = 0.2  # Validation data split ratio
    min_improvement_threshold: float = 0.02  # Min accuracy improvement to deploy new model
    
    # Rollback
    keep_previous_models: int = 3  # Number of previous model versions to keep
    
    # Dry run mode (validate without deploying)
    dry_run: bool = True  # Default to dry-run for safety
    
    class Config:
        env_file = ".env"
        env_prefix = "RETRAIN_"


# Global config instance
retrain_config = RetrainingConfig()
