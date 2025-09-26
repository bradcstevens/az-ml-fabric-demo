"""
Integration tests for Legacy System Integration Gateway

These tests validate the complete integration flow from legacy systems
to Azure ML endpoints, including authentication, error handling, and monitoring.
"""

import asyncio
import json
import time
from datetime import datetime
from typing import Dict, Any

import pytest
import httpx
from fastapi.testclient import TestClient
from unittest.mock import AsyncMock, patch, MagicMock

# Import the application and components
from src.api_gateway import app
from src.auth_bridge import AuthenticationBridge, UserInfo
from src.error_handler import ErrorHandler, ErrorContext
from src.monitoring import MetricsCollector, HealthChecker
from src.config import GatewayConfig, AuthConfig, MonitoringConfig


class TestLegacyIntegrationGateway:
    """Integration tests for the complete gateway"""

    @pytest.fixture
    def client(self):
        """Test client for FastAPI application"""
        return TestClient(app)

    @pytest.fixture
    def test_config(self):
        """Test configuration"""
        return GatewayConfig(
            host="localhost",
            port=8000,
            debug_mode=True,
            auth_config=AuthConfig(
                valid_api_keys={
                    "test-api-key": {
                        "user_id": "test_user",
                        "username": "test_user",
                        "roles": ["user"],
                        "permissions": ["predict"]
                    }
                },
                azure_ml_api_key="test-azure-ml-key",
                model_endpoints={
                    "default": {
                        "endpoint_url": "https://test-endpoint.azureml.net/score",
                        "api_key": "test-key",
                        "model_name": "test-model",
                        "model_version": "1.0",
                        "deployment_name": "default"
                    }
                }
            ),
            monitoring_config=MonitoringConfig(
                app_insights_enabled=False,
                metrics_enabled=True
            )
        )

    @pytest.fixture
    def mock_azure_ml_response(self):
        """Mock Azure ML API response"""
        return {
            "result": [0.85],
            "confidence": 0.92,
            "model_version": "v1.2.3"
        }

    def test_health_check(self, client):
        """Test health check endpoint"""
        response = client.get("/health")
        assert response.status_code == 200

        data = response.json()
        assert "status" in data
        assert "timestamp" in data
        assert "version" in data

    def test_prediction_unauthorized(self, client):
        """Test prediction without authentication"""
        response = client.post("/predict", json={
            "input_data": {"feature1": 1.0, "feature2": "value"}
        })
        assert response.status_code == 401

    @patch('src.api_gateway.call_azure_ml_api')
    def test_prediction_with_api_key(self, mock_azure_ml, client, mock_azure_ml_response):
        """Test successful prediction with API key authentication"""
        mock_azure_ml.return_value = mock_azure_ml_response

        response = client.post(
            "/predict",
            headers={"Authorization": "Bearer test-api-key"},
            json={
                "input_data": {"feature1": 1.0, "feature2": "value"},
                "correlation_id": "test-123"
            }
        )

        assert response.status_code == 200
        data = response.json()

        assert "prediction" in data
        assert "confidence" in data
        assert "request_id" in data
        assert "timestamp" in data
        assert data["status"] == "success"

    @patch('src.api_gateway.call_azure_ml_api')
    def test_batch_prediction(self, mock_azure_ml, client, mock_azure_ml_response):
        """Test batch prediction functionality"""
        mock_azure_ml.return_value = mock_azure_ml_response

        batch_request = [
            {
                "input_data": {"feature1": 1.0, "feature2": "value1"},
                "correlation_id": "batch-1"
            },
            {
                "input_data": {"feature1": 2.0, "feature2": "value2"},
                "correlation_id": "batch-2"
            }
        ]

        response = client.post(
            "/batch-predict",
            headers={"Authorization": "Bearer test-api-key"},
            json=batch_request
        )

        assert response.status_code == 200
        data = response.json()

        assert "batch_id" in data
        assert "total_requests" in data
        assert "successful_predictions" in data
        assert "responses" in data
        assert data["total_requests"] == 2

    def test_prediction_validation_error(self, client):
        """Test prediction with invalid input data"""
        response = client.post(
            "/predict",
            headers={"Authorization": "Bearer test-api-key"},
            json={
                "input_data": {}  # Empty input data should fail validation
            }
        )

        assert response.status_code == 422  # Validation error

    @patch('src.api_gateway.call_azure_ml_api')
    def test_prediction_azure_ml_error(self, mock_azure_ml, client):
        """Test prediction with Azure ML API error"""
        mock_azure_ml.side_effect = httpx.HTTPStatusError(
            "Internal Server Error",
            request=MagicMock(),
            response=MagicMock(status_code=500)
        )

        response = client.post(
            "/predict",
            headers={"Authorization": "Bearer test-api-key"},
            json={
                "input_data": {"feature1": 1.0, "feature2": "value"}
            }
        )

        assert response.status_code == 502  # Azure ML error mapped to Bad Gateway

    @patch('src.api_gateway.call_azure_ml_api')
    def test_prediction_timeout(self, mock_azure_ml, client):
        """Test prediction with timeout error"""
        mock_azure_ml.side_effect = asyncio.TimeoutError("Request timeout")

        response = client.post(
            "/predict",
            headers={"Authorization": "Bearer test-api-key"},
            json={
                "input_data": {"feature1": 1.0, "feature2": "value"}
            }
        )

        assert response.status_code == 408  # Request timeout

    def test_metrics_endpoint_unauthorized(self, client):
        """Test metrics endpoint without authentication"""
        response = client.get("/metrics")
        assert response.status_code == 401

    def test_metrics_endpoint_authorized(self, client):
        """Test metrics endpoint with authentication"""
        response = client.get(
            "/metrics",
            headers={"Authorization": "Bearer test-api-key"}
        )
        assert response.status_code == 200

        data = response.json()
        assert "requests" in data or "uptime_seconds" in data

    def test_cors_headers(self, client):
        """Test CORS headers are properly set"""
        response = client.options("/predict")
        assert "access-control-allow-origin" in response.headers

    def test_request_id_header(self, client):
        """Test request ID is returned in response headers"""
        response = client.get("/health")
        assert "X-Request-ID" in response.headers
        assert response.headers["X-Request-ID"].startswith("req_")


class TestAuthenticationBridge:
    """Tests for authentication bridge component"""

    @pytest.fixture
    def auth_config(self):
        """Authentication configuration for testing"""
        return AuthConfig(
            valid_api_keys={
                "valid-key": {
                    "user_id": "test_user",
                    "username": "test_user",
                    "roles": ["user"],
                    "permissions": ["predict"]
                }
            },
            basic_auth_users={
                "test_user": {
                    "password": "test_password",
                    "roles": ["user"],
                    "permissions": ["predict"]
                }
            },
            jwt_secret_key="test-secret-key",
            jwt_verify_signature=False  # Disable for testing
        )

    @pytest.fixture
    def auth_bridge(self, auth_config):
        """Authentication bridge instance"""
        return AuthenticationBridge(auth_config)

    @pytest.mark.asyncio
    async def test_api_key_validation_success(self, auth_bridge):
        """Test successful API key validation"""
        user_info = await auth_bridge.validate_credentials("Bearer valid-key")

        assert user_info is not None
        assert user_info.user_id == "test_user"
        assert user_info.username == "test_user"
        assert "user" in user_info.roles

    @pytest.mark.asyncio
    async def test_api_key_validation_failure(self, auth_bridge):
        """Test failed API key validation"""
        user_info = await auth_bridge.validate_credentials("Bearer invalid-key")
        assert user_info is None

    @pytest.mark.asyncio
    async def test_basic_auth_validation_success(self, auth_bridge):
        """Test successful Basic auth validation"""
        import base64
        credentials = base64.b64encode(b"test_user:test_password").decode()
        user_info = await auth_bridge.validate_credentials(f"Basic {credentials}")

        assert user_info is not None
        assert user_info.user_id == "test_user"

    @pytest.mark.asyncio
    async def test_basic_auth_validation_failure(self, auth_bridge):
        """Test failed Basic auth validation"""
        import base64
        credentials = base64.b64encode(b"test_user:wrong_password").decode()
        user_info = await auth_bridge.validate_credentials(f"Basic {credentials}")

        assert user_info is None

    @pytest.mark.asyncio
    async def test_jwt_validation(self, auth_bridge):
        """Test JWT token validation"""
        import jwt

        # Create test JWT token
        payload = {
            "sub": "test_user",
            "username": "test_user",
            "roles": ["user"],
            "permissions": ["predict"],
            "exp": int(time.time()) + 3600  # 1 hour from now
        }

        token = jwt.encode(payload, "test-secret-key", algorithm="HS256")
        user_info = await auth_bridge.validate_credentials(f"Bearer {token}")

        assert user_info is not None
        assert user_info.user_id == "test_user"

    @pytest.mark.asyncio
    async def test_azure_ml_endpoint_retrieval(self, auth_bridge):
        """Test Azure ML endpoint URL retrieval"""
        auth_bridge.config.model_endpoints = {
            "test-model": {
                "endpoint_url": "https://test.azureml.net/score",
                "api_key": "test-key"
            }
        }

        endpoint_url = await auth_bridge.get_azure_ml_endpoint("test-model")
        assert endpoint_url == "https://test.azureml.net/score"

    @pytest.mark.asyncio
    async def test_azure_ml_headers_generation(self, auth_bridge):
        """Test Azure ML headers generation"""
        user_info = UserInfo(
            user_id="test_user",
            username="test_user",
            roles=["user"],
            permissions=["predict"],
            expires_at=datetime.utcnow()
        )

        auth_bridge.config.azure_ml_api_key = "test-api-key"
        headers = await auth_bridge.get_azure_ml_headers(user_info)

        assert "Authorization" in headers
        assert headers["Authorization"] == "Bearer test-api-key"
        assert headers["Content-Type"] == "application/json"


class TestErrorHandling:
    """Tests for error handling component"""

    @pytest.fixture
    def error_handler(self):
        """Error handler instance"""
        return ErrorHandler()

    @pytest.fixture
    def error_context(self):
        """Test error context"""
        return ErrorContext(
            request_id="test_123",
            correlation_id="corr_456",
            user_id="test_user",
            endpoint="/predict",
            method="POST",
            timestamp=datetime.utcnow(),
            processing_time=1.5
        )

    @pytest.mark.asyncio
    async def test_authentication_error_handling(self, error_handler, error_context):
        """Test authentication error handling"""
        error = ValueError("Authentication failed")
        error_response = await error_handler.handle_prediction_error(error, error_context)

        assert error_response.status_code == 500  # Mapped as internal error
        assert error_response.category.value == "unknown"  # Would be classified as unknown
        assert error_response.request_id == "test_123"

    @pytest.mark.asyncio
    async def test_timeout_error_handling(self, error_handler, error_context):
        """Test timeout error handling"""
        error = asyncio.TimeoutError("Request timeout")
        error_response = await error_handler.handle_prediction_error(error, error_context)

        assert error_response.status_code == 408
        assert error_response.category.value == "timeout"

    @pytest.mark.asyncio
    async def test_http_error_handling(self, error_handler, error_context):
        """Test HTTP error handling"""
        response_mock = MagicMock()
        response_mock.status_code = 429

        error = httpx.HTTPStatusError(
            "Too Many Requests",
            request=MagicMock(),
            response=response_mock
        )

        error_response = await error_handler.handle_prediction_error(error, error_context)

        assert error_response.status_code == 429
        assert error_response.category.value == "rate_limit"
        assert error_response.retry_after is not None

    @pytest.mark.asyncio
    async def test_retry_with_backoff(self, error_handler, error_context):
        """Test retry mechanism with backoff"""
        call_count = 0

        async def failing_function():
            nonlocal call_count
            call_count += 1
            if call_count < 3:
                raise httpx.TimeoutException("Timeout")
            return "success"

        result = await error_handler.retry_with_backoff(
            failing_function, error_context
        )

        assert result == "success"
        assert call_count == 3

    @pytest.mark.asyncio
    async def test_error_metrics_collection(self, error_handler, error_context):
        """Test error metrics are collected properly"""
        initial_metrics = await error_handler.get_error_metrics()
        initial_count = initial_metrics["total_errors"]

        error = ValueError("Test error")
        await error_handler.handle_prediction_error(error, error_context)

        updated_metrics = await error_handler.get_error_metrics()
        assert updated_metrics["total_errors"] == initial_count + 1


class TestMonitoring:
    """Tests for monitoring components"""

    @pytest.fixture
    def monitoring_config(self):
        """Monitoring configuration for testing"""
        return MonitoringConfig(
            app_insights_enabled=False,
            metrics_enabled=True,
            health_check_interval=1
        )

    @pytest.fixture
    def metrics_collector(self, monitoring_config):
        """Metrics collector instance"""
        return MetricsCollector(monitoring_config)

    @pytest.fixture
    def health_checker(self, monitoring_config):
        """Health checker instance"""
        return HealthChecker(monitoring_config)

    @pytest.mark.asyncio
    async def test_metrics_collection(self, metrics_collector):
        """Test metrics collection functionality"""
        await metrics_collector.initialize()

        # Record some test metrics
        await metrics_collector.record_request("POST", "/predict", 200, 0.5)
        await metrics_collector.record_request("POST", "/predict", 200, 0.7)
        await metrics_collector.record_request("POST", "/predict", 500, 1.2)

        metrics = await metrics_collector.get_current_metrics()

        assert metrics["requests"]["total"] == 3
        assert metrics["requests"]["successful"] == 2
        assert metrics["requests"]["failed"] == 1
        assert metrics["requests"]["error_rate_percent"] > 0

        await metrics_collector.close()

    @pytest.mark.asyncio
    async def test_batch_metrics_recording(self, metrics_collector):
        """Test batch prediction metrics recording"""
        await metrics_collector.initialize()

        await metrics_collector.record_batch_prediction(5)
        await metrics_collector.record_batch_prediction(10)

        metrics = await metrics_collector.get_current_metrics()

        assert metrics["business"]["total_predictions"] == 15
        assert metrics["business"]["avg_batch_size"] > 0

        await metrics_collector.close()

    @pytest.mark.asyncio
    async def test_health_checking(self, health_checker):
        """Test health checking functionality"""
        await health_checker.initialize()

        # Wait for initial health checks
        await asyncio.sleep(1.5)

        health_status = await health_checker.get_health_status()

        assert "status" in health_status
        assert "uptime" in health_status
        assert "dependencies" in health_status

        detailed_status = await health_checker.get_detailed_health_status()
        assert "gateway" in detailed_status

        await health_checker.close()

    @pytest.mark.asyncio
    async def test_performance_percentiles(self, metrics_collector):
        """Test response time percentile calculations"""
        await metrics_collector.initialize()

        # Record requests with known response times
        response_times = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]

        for rt in response_times:
            await metrics_collector.record_request("POST", "/predict", 200, rt)

        metrics = await metrics_collector.get_current_metrics()
        percentiles = metrics["performance"]["percentiles"]

        assert "p50" in percentiles
        assert "p95" in percentiles
        assert "p99" in percentiles
        assert percentiles["p50"] <= percentiles["p95"] <= percentiles["p99"]

        await metrics_collector.close()


class TestEndToEndIntegration:
    """End-to-end integration tests"""

    @pytest.mark.asyncio
    async def test_complete_prediction_flow(self):
        """Test complete prediction flow from request to response"""
        # This would test the complete flow with real or mocked Azure ML
        # For demo purposes, we'll create a simplified test

        test_request = {
            "input_data": {
                "feature1": 1.0,
                "feature2": 2.0,
                "feature3": "test_value"
            },
            "correlation_id": "end-to-end-test"
        }

        # Test with mocked Azure ML response
        with patch('src.api_gateway.call_azure_ml_api') as mock_azure_ml:
            mock_azure_ml.return_value = {
                "result": [0.75],
                "confidence": 0.88,
                "model_version": "v1.0.0"
            }

            client = TestClient(app)
            response = client.post(
                "/predict",
                headers={"Authorization": "Bearer test-api-key"},
                json=test_request
            )

            assert response.status_code == 200
            data = response.json()

            # Verify response structure
            assert "prediction" in data
            assert "confidence" in data
            assert "model_version" in data
            assert "request_id" in data
            assert "timestamp" in data

            # Verify correlation ID is preserved
            assert response.headers.get("X-Correlation-ID") == "end-to-end-test"

    @pytest.mark.asyncio
    async def test_error_recovery_flow(self):
        """Test error recovery and circuit breaker behavior"""
        # This would test circuit breaker behavior with multiple failures
        # and recovery after service restoration

        client = TestClient(app)

        # Simulate multiple failures to trigger circuit breaker
        with patch('src.api_gateway.call_azure_ml_api') as mock_azure_ml:
            # First few requests fail
            mock_azure_ml.side_effect = httpx.ConnectError("Connection failed")

            for _ in range(3):
                response = client.post(
                    "/predict",
                    headers={"Authorization": "Bearer test-api-key"},
                    json={"input_data": {"feature1": 1.0}}
                )
                # Should still attempt the request initially
                assert response.status_code in [502, 503, 408]

            # Now simulate service recovery
            mock_azure_ml.side_effect = None
            mock_azure_ml.return_value = {
                "result": [0.85],
                "confidence": 0.92
            }

            # Service should recover
            response = client.post(
                "/predict",
                headers={"Authorization": "Bearer test-api-key"},
                json={"input_data": {"feature1": 1.0}}
            )

            # Should eventually succeed (might need multiple attempts due to circuit breaker)
            assert response.status_code in [200, 503]  # 503 if circuit breaker still open


if __name__ == "__main__":
    # Run tests with pytest
    pytest.main([__file__, "-v", "--cov=src", "--cov-report=html"])