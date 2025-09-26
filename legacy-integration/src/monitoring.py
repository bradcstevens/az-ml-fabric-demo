"""
Monitoring and observability components for Legacy Integration Gateway

This module provides comprehensive monitoring, metrics collection,
and health checking capabilities for production operations.
"""

import asyncio
import json
import logging
import time
from datetime import datetime, timedelta
from typing import Dict, Any, Optional, List, Callable
from dataclasses import dataclass, field
from collections import defaultdict, deque
import platform
import psutil

import httpx
from opencensus.ext.azure.log_exporter import AzureLogHandler
from opencensus.ext.azure.trace_exporter import AzureExporter
from opencensus.trace.tracer import Tracer
from opencensus.trace import config_integration

from .config import MonitoringConfig


logger = logging.getLogger(__name__)


@dataclass
class ServiceMetrics:
    """Service performance metrics"""
    # Request metrics
    total_requests: int = 0
    successful_requests: int = 0
    failed_requests: int = 0

    # Timing metrics
    total_processing_time: float = 0.0
    min_processing_time: float = float('inf')
    max_processing_time: float = 0.0

    # Response time percentiles
    response_times: deque = field(default_factory=lambda: deque(maxlen=10000))

    # Error metrics
    errors_by_status: Dict[int, int] = field(default_factory=lambda: defaultdict(int))
    errors_by_category: Dict[str, int] = field(default_factory=lambda: defaultdict(int))

    # Business metrics
    predictions_made: int = 0
    batch_requests: int = 0
    avg_batch_size: float = 0.0

    # System metrics
    cpu_usage: float = 0.0
    memory_usage: float = 0.0
    disk_usage: float = 0.0

    # Timestamps
    start_time: datetime = field(default_factory=datetime.utcnow)
    last_updated: datetime = field(default_factory=datetime.utcnow)


@dataclass
class HealthStatus:
    """Health check status"""
    service: str
    status: str  # healthy, degraded, unhealthy
    last_check: datetime
    response_time: float
    error_message: Optional[str] = None
    details: Dict[str, Any] = field(default_factory=dict)


class MetricsCollector:
    """Collects and aggregates service metrics"""

    def __init__(self, config: MonitoringConfig):
        self.config = config
        self.metrics = ServiceMetrics()
        self._lock = asyncio.Lock()
        self._collection_task = None
        self._azure_tracer = None

        # Initialize Application Insights if enabled
        if config.app_insights_enabled and config.app_insights_connection_string:
            self._init_app_insights()

    def _init_app_insights(self):
        """Initialize Azure Application Insights"""
        try:
            # Configure Azure Log Handler
            azure_log_handler = AzureLogHandler(
                connection_string=self.config.app_insights_connection_string
            )

            # Add to root logger if structured logging is enabled
            if self.config.structured_logging:
                root_logger = logging.getLogger()
                root_logger.addHandler(azure_log_handler)
                root_logger.setLevel(logging.INFO)

            # Configure tracing
            config_integration.trace_integrations(['httpx', 'requests'])
            self._azure_tracer = Tracer(
                exporter=AzureExporter(
                    connection_string=self.config.app_insights_connection_string
                )
            )

            logger.info("Application Insights initialized successfully")

        except Exception as e:
            logger.error(f"Failed to initialize Application Insights: {str(e)}")

    async def initialize(self):
        """Initialize metrics collection"""
        try:
            self.metrics.start_time = datetime.utcnow()

            if self.config.metrics_enabled:
                self._collection_task = asyncio.create_task(self.collector_task())
                logger.info("Metrics collection initialized")

        except Exception as e:
            logger.error(f"Failed to initialize metrics collection: {str(e)}")
            raise

    async def collector_task(self):
        """Background task for periodic metrics collection"""
        while True:
            try:
                await self._collect_system_metrics()
                await asyncio.sleep(self.config.metrics_collection_interval)
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Error in metrics collection task: {str(e)}")
                await asyncio.sleep(10)  # Retry after 10 seconds

    async def record_request(
        self,
        method: str,
        endpoint: str,
        status_code: int,
        processing_time: float,
        error_category: Optional[str] = None
    ):
        """Record request metrics"""
        async with self._lock:
            self.metrics.total_requests += 1
            self.metrics.total_processing_time += processing_time
            self.metrics.last_updated = datetime.utcnow()

            # Update timing metrics
            self.metrics.min_processing_time = min(
                self.metrics.min_processing_time, processing_time
            )
            self.metrics.max_processing_time = max(
                self.metrics.max_processing_time, processing_time
            )

            # Store response time for percentile calculations
            self.metrics.response_times.append(processing_time)

            # Track success/failure
            if 200 <= status_code < 400:
                self.metrics.successful_requests += 1
            else:
                self.metrics.failed_requests += 1
                self.metrics.errors_by_status[status_code] += 1

                if error_category:
                    self.metrics.errors_by_category[error_category] += 1

            # Track predictions
            if endpoint == "/predict":
                self.metrics.predictions_made += 1
            elif endpoint == "/batch-predict":
                self.metrics.batch_requests += 1

        # Send to Application Insights if enabled
        if self._azure_tracer:
            await self._send_request_telemetry(
                method, endpoint, status_code, processing_time
            )

    async def record_batch_prediction(self, batch_size: int):
        """Record batch prediction metrics"""
        async with self._lock:
            self.metrics.predictions_made += batch_size

            # Update average batch size
            total_batches = self.metrics.batch_requests
            if total_batches > 0:
                current_avg = self.metrics.avg_batch_size
                self.metrics.avg_batch_size = (
                    (current_avg * (total_batches - 1) + batch_size) / total_batches
                )

    async def _collect_system_metrics(self):
        """Collect system-level metrics"""
        try:
            # CPU usage
            cpu_percent = psutil.cpu_percent(interval=1)

            # Memory usage
            memory = psutil.virtual_memory()
            memory_percent = memory.percent

            # Disk usage
            disk = psutil.disk_usage('/')
            disk_percent = (disk.used / disk.total) * 100

            async with self._lock:
                self.metrics.cpu_usage = cpu_percent
                self.metrics.memory_usage = memory_percent
                self.metrics.disk_usage = disk_percent

            # Send system metrics to Application Insights
            if self._azure_tracer:
                await self._send_system_telemetry(cpu_percent, memory_percent, disk_percent)

        except Exception as e:
            logger.error(f"Failed to collect system metrics: {str(e)}")

    async def _send_request_telemetry(
        self,
        method: str,
        endpoint: str,
        status_code: int,
        processing_time: float
    ):
        """Send request telemetry to Application Insights"""
        try:
            # This would integrate with Application Insights SDK
            # For demo purposes, we'll log the telemetry
            telemetry_data = {
                "eventType": "request",
                "method": method,
                "endpoint": endpoint,
                "statusCode": status_code,
                "processingTime": processing_time,
                "timestamp": datetime.utcnow().isoformat()
            }

            logger.info("Request telemetry", extra=telemetry_data)

        except Exception as e:
            logger.error(f"Failed to send request telemetry: {str(e)}")

    async def _send_system_telemetry(
        self,
        cpu_percent: float,
        memory_percent: float,
        disk_percent: float
    ):
        """Send system telemetry to Application Insights"""
        try:
            telemetry_data = {
                "eventType": "systemMetrics",
                "cpuUsage": cpu_percent,
                "memoryUsage": memory_percent,
                "diskUsage": disk_percent,
                "timestamp": datetime.utcnow().isoformat()
            }

            logger.info("System telemetry", extra=telemetry_data)

        except Exception as e:
            logger.error(f"Failed to send system telemetry: {str(e)}")

    async def get_current_metrics(self) -> Dict[str, Any]:
        """Get current service metrics"""
        async with self._lock:
            uptime = (datetime.utcnow() - self.metrics.start_time).total_seconds()

            # Calculate percentiles
            response_times_list = list(self.metrics.response_times)
            percentiles = {}

            if response_times_list:
                response_times_list.sort()
                n = len(response_times_list)

                percentiles = {
                    "p50": self._calculate_percentile(response_times_list, 50),
                    "p95": self._calculate_percentile(response_times_list, 95),
                    "p99": self._calculate_percentile(response_times_list, 99)
                }

            # Calculate rates
            requests_per_second = self.metrics.total_requests / uptime if uptime > 0 else 0
            error_rate = (
                (self.metrics.failed_requests / self.metrics.total_requests * 100)
                if self.metrics.total_requests > 0 else 0
            )

            avg_processing_time = (
                self.metrics.total_processing_time / self.metrics.total_requests
                if self.metrics.total_requests > 0 else 0
            )

            return {
                "uptime_seconds": uptime,
                "requests": {
                    "total": self.metrics.total_requests,
                    "successful": self.metrics.successful_requests,
                    "failed": self.metrics.failed_requests,
                    "requests_per_second": round(requests_per_second, 2),
                    "error_rate_percent": round(error_rate, 2)
                },
                "performance": {
                    "avg_processing_time": round(avg_processing_time, 3),
                    "min_processing_time": round(self.metrics.min_processing_time, 3) if self.metrics.min_processing_time != float('inf') else 0,
                    "max_processing_time": round(self.metrics.max_processing_time, 3),
                    "percentiles": {k: round(v, 3) for k, v in percentiles.items()}
                },
                "business": {
                    "total_predictions": self.metrics.predictions_made,
                    "batch_requests": self.metrics.batch_requests,
                    "avg_batch_size": round(self.metrics.avg_batch_size, 1)
                },
                "system": {
                    "cpu_usage_percent": round(self.metrics.cpu_usage, 1),
                    "memory_usage_percent": round(self.metrics.memory_usage, 1),
                    "disk_usage_percent": round(self.metrics.disk_usage, 1)
                },
                "errors": {
                    "by_status_code": dict(self.metrics.errors_by_status),
                    "by_category": dict(self.metrics.errors_by_category)
                },
                "last_updated": self.metrics.last_updated.isoformat()
            }

    def _calculate_percentile(self, sorted_values: List[float], percentile: int) -> float:
        """Calculate percentile from sorted values"""
        if not sorted_values:
            return 0.0

        k = (len(sorted_values) - 1) * percentile / 100
        f = int(k)
        c = k - f

        if f == len(sorted_values) - 1:
            return sorted_values[f]
        else:
            return sorted_values[f] + c * (sorted_values[f + 1] - sorted_values[f])

    async def close(self):
        """Clean up metrics collection"""
        try:
            if self._collection_task:
                self._collection_task.cancel()
                try:
                    await self._collection_task
                except asyncio.CancelledError:
                    pass

            logger.info("Metrics collection closed")

        except Exception as e:
            logger.error(f"Error closing metrics collection: {str(e)}")


class HealthChecker:
    """Health checking for the service and its dependencies"""

    def __init__(self, config: MonitoringConfig):
        self.config = config
        self.health_status: Dict[str, HealthStatus] = {}
        self._check_task = None
        self._lock = asyncio.Lock()

    async def initialize(self):
        """Initialize health checking"""
        try:
            # Initialize health status for all services
            services = ["gateway", "azure_ml", "key_vault", "app_insights"]

            for service in services:
                self.health_status[service] = HealthStatus(
                    service=service,
                    status="unknown",
                    last_check=datetime.utcnow(),
                    response_time=0.0
                )

            # Start periodic health checks
            self._check_task = asyncio.create_task(self.periodic_check_task())
            logger.info("Health checking initialized")

        except Exception as e:
            logger.error(f"Failed to initialize health checking: {str(e)}")
            raise

    async def periodic_check_task(self):
        """Background task for periodic health checks"""
        while True:
            try:
                await self._perform_health_checks()
                await asyncio.sleep(self.config.health_check_interval)
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Error in health check task: {str(e)}")
                await asyncio.sleep(10)  # Retry after 10 seconds

    async def _perform_health_checks(self):
        """Perform health checks for all services"""
        try:
            # Check gateway health (self)
            await self._check_gateway_health()

            # Check Azure ML health
            if self.config.azure_ml_health_check_enabled:
                await self._check_azure_ml_health()

            # Check other dependencies
            await self._check_key_vault_health()
            await self._check_app_insights_health()

        except Exception as e:
            logger.error(f"Health checks failed: {str(e)}")

    async def _check_gateway_health(self):
        """Check gateway service health"""
        try:
            start_time = time.time()

            # Check basic functionality
            status = "healthy"
            error_message = None

            # Check system resources
            memory = psutil.virtual_memory()
            cpu_percent = psutil.cpu_percent()

            details = {
                "memory_usage_percent": memory.percent,
                "cpu_usage_percent": cpu_percent,
                "available_memory_mb": memory.available // (1024 * 1024),
                "process_id": os.getpid(),
                "python_version": platform.python_version()
            }

            # Determine status based on resource usage
            if memory.percent > 90 or cpu_percent > 95:
                status = "degraded"
                error_message = "High resource usage"
            elif memory.percent > 95:
                status = "unhealthy"
                error_message = "Critical resource usage"

            response_time = time.time() - start_time

            async with self._lock:
                self.health_status["gateway"] = HealthStatus(
                    service="gateway",
                    status=status,
                    last_check=datetime.utcnow(),
                    response_time=response_time,
                    error_message=error_message,
                    details=details
                )

        except Exception as e:
            async with self._lock:
                self.health_status["gateway"] = HealthStatus(
                    service="gateway",
                    status="unhealthy",
                    last_check=datetime.utcnow(),
                    response_time=0.0,
                    error_message=str(e)
                )

    async def _check_azure_ml_health(self):
        """Check Azure ML endpoint health"""
        try:
            if not self.config.azure_ml_health_check_endpoint:
                return

            start_time = time.time()

            async with httpx.AsyncClient(timeout=self.config.health_check_timeout) as client:
                response = await client.get(self.config.azure_ml_health_check_endpoint)
                response_time = time.time() - start_time

                status = "healthy" if response.status_code == 200 else "degraded"
                error_message = None if response.status_code == 200 else f"HTTP {response.status_code}"

                details = {
                    "status_code": response.status_code,
                    "response_time_ms": round(response_time * 1000, 2)
                }

            async with self._lock:
                self.health_status["azure_ml"] = HealthStatus(
                    service="azure_ml",
                    status=status,
                    last_check=datetime.utcnow(),
                    response_time=response_time,
                    error_message=error_message,
                    details=details
                )

        except Exception as e:
            async with self._lock:
                self.health_status["azure_ml"] = HealthStatus(
                    service="azure_ml",
                    status="unhealthy",
                    last_check=datetime.utcnow(),
                    response_time=0.0,
                    error_message=str(e)
                )

    async def _check_key_vault_health(self):
        """Check Azure Key Vault health"""
        try:
            # This would check Key Vault connectivity
            # For demo purposes, we'll simulate the check
            start_time = time.time()

            # Simulate Key Vault check
            await asyncio.sleep(0.1)  # Simulate network call

            response_time = time.time() - start_time

            async with self._lock:
                self.health_status["key_vault"] = HealthStatus(
                    service="key_vault",
                    status="healthy",
                    last_check=datetime.utcnow(),
                    response_time=response_time,
                    details={"simulated": True}
                )

        except Exception as e:
            async with self._lock:
                self.health_status["key_vault"] = HealthStatus(
                    service="key_vault",
                    status="unhealthy",
                    last_check=datetime.utcnow(),
                    response_time=0.0,
                    error_message=str(e)
                )

    async def _check_app_insights_health(self):
        """Check Application Insights health"""
        try:
            # This would check Application Insights connectivity
            # For demo purposes, we'll simulate the check
            start_time = time.time()

            status = "healthy" if self.config.app_insights_enabled else "disabled"

            # Simulate App Insights check
            await asyncio.sleep(0.05)  # Simulate network call

            response_time = time.time() - start_time

            async with self._lock:
                self.health_status["app_insights"] = HealthStatus(
                    service="app_insights",
                    status=status,
                    last_check=datetime.utcnow(),
                    response_time=response_time,
                    details={
                        "enabled": self.config.app_insights_enabled,
                        "simulated": True
                    }
                )

        except Exception as e:
            async with self._lock:
                self.health_status["app_insights"] = HealthStatus(
                    service="app_insights",
                    status="unhealthy",
                    last_check=datetime.utcnow(),
                    response_time=0.0,
                    error_message=str(e)
                )

    async def get_health_status(self) -> Dict[str, Any]:
        """Get current health status"""
        async with self._lock:
            overall_status = "healthy"
            unhealthy_services = []

            service_statuses = {}
            for service, health in self.health_status.items():
                service_statuses[service] = health.status

                if health.status == "unhealthy":
                    overall_status = "unhealthy"
                    unhealthy_services.append(service)
                elif health.status == "degraded" and overall_status == "healthy":
                    overall_status = "degraded"

            uptime = (datetime.utcnow() - min(
                health.last_check for health in self.health_status.values()
            )).total_seconds()

            return {
                "status": overall_status,
                "uptime": uptime,
                "azure_ml_status": self.health_status.get("azure_ml", HealthStatus("azure_ml", "unknown", datetime.utcnow(), 0.0)).status,
                "dependencies": service_statuses,
                "unhealthy_services": unhealthy_services,
                "last_check": max(
                    health.last_check for health in self.health_status.values()
                ).isoformat()
            }

    async def get_detailed_health_status(self) -> Dict[str, Any]:
        """Get detailed health status with service details"""
        async with self._lock:
            detailed_status = {}

            for service, health in self.health_status.items():
                detailed_status[service] = {
                    "status": health.status,
                    "last_check": health.last_check.isoformat(),
                    "response_time": round(health.response_time, 3),
                    "error_message": health.error_message,
                    "details": health.details
                }

            return detailed_status

    async def close(self):
        """Clean up health checking"""
        try:
            if self._check_task:
                self._check_task.cancel()
                try:
                    await self._check_task
                except asyncio.CancelledError:
                    pass

            logger.info("Health checking closed")

        except Exception as e:
            logger.error(f"Error closing health checking: {str(e)}")


# Example usage and testing
if __name__ == "__main__":
    import asyncio
    import os
    from .config import MonitoringConfig

    async def test_monitoring():
        config = MonitoringConfig()

        # Test metrics collection
        metrics = MetricsCollector(config)
        await metrics.initialize()

        # Simulate some requests
        for i in range(10):
            await metrics.record_request("POST", "/predict", 200, 0.5 + i * 0.1)
            await asyncio.sleep(0.1)

        # Get metrics
        current_metrics = await metrics.get_current_metrics()
        print(f"Metrics: {json.dumps(current_metrics, indent=2)}")

        # Test health checking
        health_checker = HealthChecker(config)
        await health_checker.initialize()

        await asyncio.sleep(2)  # Let health checks run

        health_status = await health_checker.get_health_status()
        print(f"Health: {json.dumps(health_status, indent=2)}")

        # Cleanup
        await metrics.close()
        await health_checker.close()

    # Run test
    # asyncio.run(test_monitoring())