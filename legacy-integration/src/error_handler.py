"""
Error handling and resilience components for Legacy Integration Gateway

This module provides comprehensive error handling, retry logic, and
circuit breaker patterns for reliable production operation.
"""

import asyncio
import logging
import time
import traceback
from datetime import datetime, timedelta
from typing import Dict, Any, Optional, Callable, Type, Tuple
from dataclasses import dataclass, field
from enum import Enum

import httpx
from circuitbreaker import circuit, CircuitBreakerError


logger = logging.getLogger(__name__)


class ErrorCategory(Enum):
    """Error categories for classification"""
    AUTHENTICATION = "authentication"
    AUTHORIZATION = "authorization"
    VALIDATION = "validation"
    TIMEOUT = "timeout"
    RATE_LIMIT = "rate_limit"
    AZURE_ML_ERROR = "azure_ml_error"
    NETWORK_ERROR = "network_error"
    INTERNAL_ERROR = "internal_error"
    CIRCUIT_BREAKER = "circuit_breaker"
    UNKNOWN = "unknown"


class ErrorSeverity(Enum):
    """Error severity levels"""
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"


@dataclass
class ErrorMetrics:
    """Error metrics for monitoring"""
    total_errors: int = 0
    errors_by_category: Dict[ErrorCategory, int] = field(default_factory=dict)
    errors_by_severity: Dict[ErrorSeverity, int] = field(default_factory=dict)
    last_error_time: Optional[datetime] = None
    error_rate_1min: float = 0.0
    error_rate_5min: float = 0.0
    error_rate_15min: float = 0.0


@dataclass
class ErrorContext:
    """Context information for error handling"""
    request_id: str
    correlation_id: Optional[str]
    user_id: Optional[str]
    endpoint: str
    method: str
    timestamp: datetime
    processing_time: float
    retry_count: int = 0


@dataclass
class ErrorResponse:
    """Standardized error response"""
    error_id: str
    status_code: int
    error_code: str
    message: str
    detail: Optional[str]
    category: ErrorCategory
    severity: ErrorSeverity
    timestamp: str
    request_id: Optional[str]
    correlation_id: Optional[str]
    retry_after: Optional[int] = None
    support_info: Optional[Dict[str, str]] = None


class RetryPolicy:
    """Configurable retry policy"""

    def __init__(
        self,
        max_attempts: int = 3,
        base_delay: float = 1.0,
        max_delay: float = 60.0,
        exponential_base: float = 2.0,
        jitter: bool = True
    ):
        self.max_attempts = max_attempts
        self.base_delay = base_delay
        self.max_delay = max_delay
        self.exponential_base = exponential_base
        self.jitter = jitter

    def should_retry(self, exception: Exception, attempt: int) -> bool:
        """Determine if request should be retried"""
        if attempt >= self.max_attempts:
            return False

        # Define retryable exceptions
        retryable_exceptions = (
            httpx.TimeoutException,
            httpx.ConnectTimeout,
            httpx.ReadTimeout,
            httpx.NetworkError,
            ConnectionError,
            asyncio.TimeoutError
        )

        if isinstance(exception, retryable_exceptions):
            return True

        # Check for specific HTTP status codes
        if isinstance(exception, httpx.HTTPStatusError):
            # Retry on 5xx errors and specific 4xx errors
            return exception.response.status_code in [429, 502, 503, 504]

        return False

    def get_delay(self, attempt: int) -> float:
        """Calculate delay for retry attempt"""
        delay = self.base_delay * (self.exponential_base ** attempt)
        delay = min(delay, self.max_delay)

        if self.jitter:
            # Add jitter to prevent thundering herd
            import random
            delay = delay * (0.5 + random.random() * 0.5)

        return delay


class CircuitBreakerManager:
    """Manages circuit breakers for different endpoints"""

    def __init__(self):
        self._circuit_breakers: Dict[str, Callable] = {}

    def get_circuit_breaker(
        self,
        endpoint: str,
        failure_threshold: int = 5,
        recovery_timeout: int = 30,
        expected_exception: Type[Exception] = Exception
    ) -> Callable:
        """Get or create circuit breaker for endpoint"""
        if endpoint not in self._circuit_breakers:
            @circuit(
                failure_threshold=failure_threshold,
                recovery_timeout=recovery_timeout,
                expected_exception=expected_exception
            )
            async def protected_call(func: Callable, *args, **kwargs):
                return await func(*args, **kwargs)

            self._circuit_breakers[endpoint] = protected_call

        return self._circuit_breakers[endpoint]

    def get_circuit_breaker_state(self, endpoint: str) -> Dict[str, Any]:
        """Get circuit breaker state information"""
        if endpoint in self._circuit_breakers:
            cb = self._circuit_breakers[endpoint]
            if hasattr(cb, '__wrapped__'):
                circuit_breaker = cb.__wrapped__
                return {
                    "state": circuit_breaker.current_state,
                    "failure_count": circuit_breaker.failure_count,
                    "last_failure_time": circuit_breaker.last_failure,
                    "next_attempt_time": circuit_breaker.next_attempt_time
                }
        return {"state": "unknown"}


class ErrorHandler:
    """Main error handling coordinator"""

    def __init__(self):
        self.retry_policy = RetryPolicy()
        self.circuit_breaker_manager = CircuitBreakerManager()
        self.error_metrics = ErrorMetrics()
        self._error_log: list = []
        self._lock = asyncio.Lock()

    async def handle_prediction_error(
        self,
        exception: Exception,
        context: ErrorContext
    ) -> ErrorResponse:
        """Handle prediction-related errors"""
        try:
            # Classify error
            category, severity = self._classify_error(exception)

            # Generate error response
            error_response = await self._create_error_response(
                exception, category, severity, context
            )

            # Record metrics
            await self._record_error_metrics(category, severity, context)

            # Log error
            await self._log_error(exception, error_response, context)

            # Trigger alerts if needed
            await self._check_alert_conditions(category, severity)

            return error_response

        except Exception as e:
            logger.error(f"Error in error handler: {str(e)}")
            # Fallback error response
            return ErrorResponse(
                error_id=f"err_{int(time.time() * 1000)}",
                status_code=500,
                error_code="HANDLER_ERROR",
                message="Internal error in error handler",
                detail=str(e),
                category=ErrorCategory.INTERNAL_ERROR,
                severity=ErrorSeverity.CRITICAL,
                timestamp=datetime.utcnow().isoformat(),
                request_id=context.request_id,
                correlation_id=context.correlation_id
            )

    async def retry_with_backoff(
        self,
        func: Callable,
        context: ErrorContext,
        *args,
        **kwargs
    ) -> Any:
        """Execute function with retry and backoff"""
        last_exception = None

        for attempt in range(self.retry_policy.max_attempts):
            try:
                context.retry_count = attempt
                return await func(*args, **kwargs)

            except Exception as e:
                last_exception = e

                if not self.retry_policy.should_retry(e, attempt):
                    break

                if attempt < self.retry_policy.max_attempts - 1:
                    delay = self.retry_policy.get_delay(attempt)
                    logger.warning(
                        f"Request {context.request_id} failed (attempt {attempt + 1}), "
                        f"retrying in {delay:.2f}s: {str(e)}"
                    )
                    await asyncio.sleep(delay)

        # All retries exhausted
        logger.error(
            f"Request {context.request_id} failed after {self.retry_policy.max_attempts} attempts"
        )
        raise last_exception

    def _classify_error(self, exception: Exception) -> Tuple[ErrorCategory, ErrorSeverity]:
        """Classify error by category and severity"""
        # Authentication/Authorization errors
        if isinstance(exception, (PermissionError, ValueError)) and "auth" in str(exception).lower():
            return ErrorCategory.AUTHENTICATION, ErrorSeverity.MEDIUM

        # Timeout errors
        if isinstance(exception, (asyncio.TimeoutError, httpx.TimeoutException)):
            return ErrorCategory.TIMEOUT, ErrorSeverity.MEDIUM

        # HTTP errors
        if isinstance(exception, httpx.HTTPStatusError):
            status_code = exception.response.status_code

            if status_code == 401:
                return ErrorCategory.AUTHENTICATION, ErrorSeverity.MEDIUM
            elif status_code == 403:
                return ErrorCategory.AUTHORIZATION, ErrorSeverity.MEDIUM
            elif status_code == 429:
                return ErrorCategory.RATE_LIMIT, ErrorSeverity.LOW
            elif 400 <= status_code < 500:
                return ErrorCategory.VALIDATION, ErrorSeverity.LOW
            elif 500 <= status_code < 600:
                return ErrorCategory.AZURE_ML_ERROR, ErrorSeverity.HIGH

        # Circuit breaker errors
        if isinstance(exception, CircuitBreakerError):
            return ErrorCategory.CIRCUIT_BREAKER, ErrorSeverity.HIGH

        # Network errors
        if isinstance(exception, (httpx.NetworkError, ConnectionError)):
            return ErrorCategory.NETWORK_ERROR, ErrorSeverity.MEDIUM

        # Default classification
        return ErrorCategory.UNKNOWN, ErrorSeverity.MEDIUM

    async def _create_error_response(
        self,
        exception: Exception,
        category: ErrorCategory,
        severity: ErrorSeverity,
        context: ErrorContext
    ) -> ErrorResponse:
        """Create standardized error response"""
        error_id = f"err_{int(time.time() * 1000)}_{context.request_id[-8:]}"

        # Map category to HTTP status code
        status_code_map = {
            ErrorCategory.AUTHENTICATION: 401,
            ErrorCategory.AUTHORIZATION: 403,
            ErrorCategory.VALIDATION: 400,
            ErrorCategory.TIMEOUT: 408,
            ErrorCategory.RATE_LIMIT: 429,
            ErrorCategory.AZURE_ML_ERROR: 502,
            ErrorCategory.NETWORK_ERROR: 503,
            ErrorCategory.CIRCUIT_BREAKER: 503,
            ErrorCategory.INTERNAL_ERROR: 500,
            ErrorCategory.UNKNOWN: 500
        }

        status_code = status_code_map.get(category, 500)

        # Generate user-friendly error messages
        message_map = {
            ErrorCategory.AUTHENTICATION: "Authentication failed",
            ErrorCategory.AUTHORIZATION: "Access denied",
            ErrorCategory.VALIDATION: "Invalid request data",
            ErrorCategory.TIMEOUT: "Request timeout",
            ErrorCategory.RATE_LIMIT: "Rate limit exceeded",
            ErrorCategory.AZURE_ML_ERROR: "ML service temporarily unavailable",
            ErrorCategory.NETWORK_ERROR: "Network connectivity issue",
            ErrorCategory.CIRCUIT_BREAKER: "Service temporarily unavailable",
            ErrorCategory.INTERNAL_ERROR: "Internal server error",
            ErrorCategory.UNKNOWN: "An unexpected error occurred"
        }

        message = message_map.get(category, "An error occurred")

        # Add retry-after header for appropriate errors
        retry_after = None
        if category in [ErrorCategory.RATE_LIMIT, ErrorCategory.CIRCUIT_BREAKER]:
            retry_after = 60  # Suggest retry after 60 seconds

        # Support information
        support_info = {
            "documentation": "https://docs.company.com/legacy-integration",
            "support_email": "ml-support@company.com",
            "status_page": "https://status.company.com"
        }

        return ErrorResponse(
            error_id=error_id,
            status_code=status_code,
            error_code=f"{category.value.upper()}_{severity.value.upper()}",
            message=message,
            detail=str(exception) if severity in [ErrorSeverity.HIGH, ErrorSeverity.CRITICAL] else None,
            category=category,
            severity=severity,
            timestamp=datetime.utcnow().isoformat(),
            request_id=context.request_id,
            correlation_id=context.correlation_id,
            retry_after=retry_after,
            support_info=support_info
        )

    async def _record_error_metrics(
        self,
        category: ErrorCategory,
        severity: ErrorSeverity,
        context: ErrorContext
    ):
        """Record error metrics"""
        async with self._lock:
            self.error_metrics.total_errors += 1
            self.error_metrics.last_error_time = datetime.utcnow()

            # Update category counts
            if category not in self.error_metrics.errors_by_category:
                self.error_metrics.errors_by_category[category] = 0
            self.error_metrics.errors_by_category[category] += 1

            # Update severity counts
            if severity not in self.error_metrics.errors_by_severity:
                self.error_metrics.errors_by_severity[severity] = 0
            self.error_metrics.errors_by_severity[severity] += 1

            # Calculate error rates (simplified implementation)
            # In production, you'd use a sliding window
            self.error_metrics.error_rate_1min = min(self.error_metrics.total_errors, 60)

    async def _log_error(
        self,
        exception: Exception,
        error_response: ErrorResponse,
        context: ErrorContext
    ):
        """Log error with appropriate level"""
        log_data = {
            "error_id": error_response.error_id,
            "request_id": context.request_id,
            "correlation_id": context.correlation_id,
            "category": error_response.category.value,
            "severity": error_response.severity.value,
            "endpoint": context.endpoint,
            "method": context.method,
            "processing_time": context.processing_time,
            "retry_count": context.retry_count,
            "user_id": context.user_id
        }

        if error_response.severity == ErrorSeverity.CRITICAL:
            logger.critical(f"Critical error: {error_response.message}", extra=log_data)
        elif error_response.severity == ErrorSeverity.HIGH:
            logger.error(f"High severity error: {error_response.message}", extra=log_data)
        elif error_response.severity == ErrorSeverity.MEDIUM:
            logger.warning(f"Medium severity error: {error_response.message}", extra=log_data)
        else:
            logger.info(f"Low severity error: {error_response.message}", extra=log_data)

        # Store error for analysis
        async with self._lock:
            self._error_log.append({
                "timestamp": datetime.utcnow(),
                "exception": exception,
                "error_response": error_response,
                "context": context,
                "traceback": traceback.format_exc()
            })

            # Keep only recent errors (last 1000)
            if len(self._error_log) > 1000:
                self._error_log = self._error_log[-1000:]

    async def _check_alert_conditions(self, category: ErrorCategory, severity: ErrorSeverity):
        """Check if alerts should be triggered"""
        try:
            # Critical errors always trigger alerts
            if severity == ErrorSeverity.CRITICAL:
                await self._trigger_alert("critical_error", {
                    "category": category.value,
                    "severity": severity.value,
                    "timestamp": datetime.utcnow().isoformat()
                })

            # High error rate alerts
            if self.error_metrics.error_rate_1min > 10:  # More than 10 errors per minute
                await self._trigger_alert("high_error_rate", {
                    "error_rate": self.error_metrics.error_rate_1min,
                    "timestamp": datetime.utcnow().isoformat()
                })

            # Circuit breaker alerts
            if category == ErrorCategory.CIRCUIT_BREAKER:
                await self._trigger_alert("circuit_breaker_open", {
                    "timestamp": datetime.utcnow().isoformat()
                })

        except Exception as e:
            logger.error(f"Failed to check alert conditions: {str(e)}")

    async def _trigger_alert(self, alert_type: str, alert_data: Dict[str, Any]):
        """Trigger alert (integrate with your alerting system)"""
        try:
            # This would integrate with your alerting system
            # Examples: PagerDuty, OpsGenie, Azure Monitor, etc.
            logger.warning(f"ALERT: {alert_type} - {alert_data}")

            # Example: Send to Azure Monitor (implement as needed)
            # await self._send_to_azure_monitor(alert_type, alert_data)

        except Exception as e:
            logger.error(f"Failed to trigger alert: {str(e)}")

    async def get_error_metrics(self) -> Dict[str, Any]:
        """Get current error metrics"""
        async with self._lock:
            return {
                "total_errors": self.error_metrics.total_errors,
                "errors_by_category": {
                    cat.value: count for cat, count in self.error_metrics.errors_by_category.items()
                },
                "errors_by_severity": {
                    sev.value: count for sev, count in self.error_metrics.errors_by_severity.items()
                },
                "last_error_time": self.error_metrics.last_error_time.isoformat() if self.error_metrics.last_error_time else None,
                "error_rates": {
                    "1min": self.error_metrics.error_rate_1min,
                    "5min": self.error_metrics.error_rate_5min,
                    "15min": self.error_metrics.error_rate_15min
                }
            }

    async def get_recent_errors(self, limit: int = 100) -> List[Dict[str, Any]]:
        """Get recent error log entries"""
        async with self._lock:
            recent_errors = self._error_log[-limit:] if self._error_log else []
            return [
                {
                    "timestamp": error["timestamp"].isoformat(),
                    "error_id": error["error_response"].error_id,
                    "category": error["error_response"].category.value,
                    "severity": error["error_response"].severity.value,
                    "message": error["error_response"].message,
                    "request_id": error["context"].request_id,
                    "endpoint": error["context"].endpoint
                }
                for error in recent_errors
            ]

    async def clear_metrics(self):
        """Clear error metrics (for testing/reset)"""
        async with self._lock:
            self.error_metrics = ErrorMetrics()
            self._error_log.clear()


# Example usage and testing
if __name__ == "__main__":
    import asyncio

    async def test_error_handler():
        handler = ErrorHandler()

        # Create test context
        context = ErrorContext(
            request_id="test_123",
            correlation_id="corr_456",
            user_id="test_user",
            endpoint="/predict",
            method="POST",
            timestamp=datetime.utcnow(),
            processing_time=1.5
        )

        # Test different error types
        test_errors = [
            httpx.HTTPStatusError("Unauthorized", request=None, response=type('Response', (), {'status_code': 401})()),
            asyncio.TimeoutError("Request timeout"),
            ValueError("Invalid input data"),
            Exception("Unknown error")
        ]

        for error in test_errors:
            error_response = await handler.handle_prediction_error(error, context)
            print(f"Error: {error.__class__.__name__}")
            print(f"Response: {error_response.error_code} - {error_response.message}")
            print("---")

        # Get metrics
        metrics = await handler.get_error_metrics()
        print(f"Metrics: {metrics}")

    # Run test
    # asyncio.run(test_error_handler())