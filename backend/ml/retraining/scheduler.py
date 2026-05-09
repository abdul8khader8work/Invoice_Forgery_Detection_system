"""
Automated Model Retraining Scheduler
Uses APScheduler for cron-like triggers (daily/weekly)
Feature flag: ENABLE_AUTO_RETRAIN (default: false)
"""
import asyncio
import logging
from datetime import datetime
from typing import Optional

try:
    from apscheduler.schedulers.asyncio import AsyncIOScheduler
    from apscheduler.triggers.cron import CronTrigger
    AP_SCHEDULER_AVAILABLE = True
except ImportError:
    AP_SCHEDULER_AVAILABLE = False

from .config import retrain_config
from .pipeline import retraining_pipeline

logger = logging.getLogger(__name__)


class RetrainingScheduler:
    """Scheduler for automated model retraining"""
    
    def __init__(self, config=None):
        self.config = config or retrain_config
        self.scheduler: Optional[AsyncIOScheduler] = None
        self._initialized = False
    
    async def initialize(self):
        """Initialize the scheduler"""
        if not AP_SCHEDULER_AVAILABLE:
            logger.warning("APScheduler not available. Install with: pip install apscheduler")
            return
        
        if self._initialized:
            return
        
        self.scheduler = AsyncIOScheduler()
        
        # Schedule retraining job based on configuration
        if self.config.enable_auto_retrain:
            self._schedule_retraining()
            logger.info(f"Retraining scheduled: {self.config.retrain_schedule}")
        else:
            logger.info("Auto-retraining disabled (enable_auto_retrain=false)")
        
        self._initialized = True
    
    def _schedule_retraining(self):
        """Schedule the retraining job based on config"""
        if not self.scheduler:
            return
        
        # Build cron trigger based on schedule type
        if self.config.retrain_schedule == "daily":
            trigger = CronTrigger(
                hour=self.config.retrain_hour,
                minute=0
            )
        elif self.config.retrain_schedule == "weekly":
            trigger = CronTrigger(
                day_of_week=self.config.retrain_day or 0,  # Sunday default
                hour=self.config.retrain_hour,
                minute=0
            )
        elif self.config.retrain_schedule == "monthly":
            trigger = CronTrigger(
                day=self.config.retrain_day or 1,  # 1st of month
                hour=self.config.retrain_hour,
                minute=0
            )
        else:
            logger.error(f"Unknown schedule type: {self.config.retrain_schedule}")
            return
        
        # Add job to scheduler
        self.scheduler.add_job(
            self._run_retraining,
            trigger=trigger,
            id='model_retraining',
            name='Automated Model Retraining',
            replace_existing=True
        )
        
        logger.info(
            f"Scheduled retraining: {self.config.retrain_schedule} "
            f"at hour {self.config.retrain_hour}"
        )
    
    async def _run_retraining(self):
        """Execute the retraining pipeline"""
        logger.info("Starting scheduled model retraining...")
        
        if not self.config.enable_auto_retrain:
            logger.info("Auto-retraining disabled, skipping")
            return
        
        try:
            result = retraining_pipeline.run_pipeline(dry_run=self.config.dry_run)
            
            if result["status"] == "success":
                logger.info(f"Retraining completed successfully: {result}")
            elif result["status"] == "skipped":
                logger.info(f"Retraining skipped: {result.get('reason')}")
            else:
                logger.error(f"Retraining failed: {result}")
                
        except Exception as e:
            logger.error(f"Unexpected error during retraining: {str(e)}")
    
    async def start(self):
        """Start the scheduler"""
        if not self.scheduler:
            logger.warning("Scheduler not initialized")
            return
        
        self.scheduler.start()
        logger.info("Retraining scheduler started")
    
    async def stop(self):
        """Stop the scheduler"""
        if self.scheduler:
            self.scheduler.shutdown()
            logger.info("Retraining scheduler stopped")
    
    async def trigger_now(self, dry_run: Optional[bool] = None) -> dict:
        """
        Manually trigger retraining immediately
        
        Args:
            dry_run: Override dry-run setting for this run
            
        Returns:
            Retraining result
        """
        logger.info("Manually triggering retraining...")
        
        is_dry_run = dry_run if dry_run is not None else self.config.dry_run
        return retraining_pipeline.run_pipeline(dry_run=is_dry_run)
    
    def get_next_run_time(self) -> Optional[datetime]:
        """Get the next scheduled run time"""
        if not self.scheduler:
            return None
        
        job = self.scheduler.get_job('model_retraining')
        if job:
            return job.next_run_time
        return None
    
    def get_schedule_info(self) -> dict:
        """Get current schedule configuration"""
        return {
            "enabled": self.config.enable_auto_retrain,
            "schedule": self.config.retrain_schedule,
            "hour": self.config.retrain_hour,
            "day": self.config.retrain_day,
            "dry_run": self.config.dry_run,
            "next_run": self.get_next_run_time().isoformat() if self.get_next_run_time() else None
        }


# Global scheduler instance
retraining_scheduler = RetrainingScheduler()


# FastAPI lifecycle hooks
async def start_scheduler():
    """Start the retraining scheduler (call from FastAPI startup)"""
    await retraining_scheduler.initialize()
    await retraining_scheduler.start()


async def stop_scheduler():
    """Stop the retraining scheduler (call from FastAPI shutdown)"""
    await retraining_scheduler.stop()
