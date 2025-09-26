"""
Legacy System Integration API Gateway

This module provides a REST API gateway that translates legacy system requests
to Azure ML real-time prediction API calls without requiring changes to legacy applications.
"""

import asyncio
import json
import logging
import time
from datetime import datetime
from typing import Dict, Any, Optional, List
from dataclasses import dataclass, asdict
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request, Response, Depends, Security
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from pydantic import BaseModel, Field, validator
import httpx
import uvicorn
from circuitbreaker import circuit

from .auth_bridge import AuthenticationBridge
from .error_handler import ErrorHandler
from .monitoring import MetricsCollector, HealthChecker
from .config import GatewayConfig


# Logging configuration
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Security
security = HTTPBearer()

# Configuration
config = GatewayConfig()

# Global components
auth_bridge = AuthenticationBridge(config.auth_config)
error_handler = ErrorHandler()
metrics = MetricsCollector()
health_checker = HealthChecker()


# Request/Response Models
class LegacyPredictionRequest(BaseModel):
    """Legacy system prediction request format"""
    input_data: Dict[str, Any] = Field(..., description="Input features for prediction")
    model_id: Optional[str] = Field(None, description="Optional model identifier")
    correlation_id: Optional[str] = Field(None, description="Request correlation ID")

    @validator('input_data')
    def validate_input_data(cls, v):
        if not v:
            raise ValueError("input_data cannot be empty")
        return v


class LegacyPredictionResponse(BaseModel):
    """Legacy system prediction response format"""
    prediction: Any = Field(..., description="Prediction result")
    confidence: Optional[float] = Field(None, description="Prediction confidence score")
    model_version: Optional[str] = Field(None, description="Model version used")
    request_id: str = Field(..., description="Unique request identifier")
    timestamp: str = Field(..., description="Response timestamp")
    status: str = Field(default="success", description="Response status")


class HealthStatus(BaseModel):
    """Health check response"""
    status: str
    timestamp: str
    version: str
    uptime_seconds: float
    azure_ml_status: str
    dependencies: Dict[str, str]


@dataclass
class RequestContext:
    """Request processing context"""
    request_id: str
    correlation_id: Optional[str]
    start_time: float
    legacy_format: bool
    auth_token: Optional[str]


# Application lifecycle
@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifecycle management"""
    logger.info("Starting Legacy Integration API Gateway")

    # Initialize components
    await health_checker.initialize()
    await metrics.initialize()

    # Start background tasks
    asyncio.create_task(metrics.collector_task())
    asyncio.create_task(health_checker.periodic_check_task())

    yield

    # Cleanup
    logger.info("Shutting down API Gateway")
    await metrics.close()
    await health_checker.close()


# FastAPI application
app = FastAPI(
    title="Legacy System Integration Gateway",
    description="API Gateway for integrating legacy systems with Azure ML real-time predictions",
    version="1.0.0",
    lifespan=lifespan
)

# Middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=config.cors_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["*"],
)

app.add_middleware(
    TrustedHostMiddleware,
    allowed_hosts=config.allowed_hosts
)


# Request context middleware
@app.middleware("http")
async def request_context_middleware(request: Request, call_next):
    """Add request context and metrics collection"""
    start_time = time.time()
    request_id = f"req_{int(start_time * 1000)}"

    # Extract correlation ID from headers
    correlation_id = request.headers.get("X-Correlation-ID")

    # Determine if this is a legacy format request
    legacy_format = request.headers.get("X-Legacy-Format", "false").lower() == "true"

    # Store context
    request.state.context = RequestContext(
        request_id=request_id,
        correlation_id=correlation_id,
        start_time=start_time,
        legacy_format=legacy_format,
        auth_token=request.headers.get("Authorization")
    )

    # Process request
    response = await call_next(request)

    # Record metrics
    processing_time = time.time() - start_time
    await metrics.record_request(
        method=request.method,
        endpoint=str(request.url.path),
        status_code=response.status_code,
        processing_time=processing_time
    )

    # Add response headers
    response.headers["X-Request-ID"] = request_id
    response.headers["X-Processing-Time"] = f"{processing_time:.3f}s"

    if correlation_id:
        response.headers["X-Correlation-ID"] = correlation_id

    return response


# Authentication dependency
async def authenticate_request(credentials: HTTPAuthorizationCredentials = Security(security)):
    """Authenticate incoming requests"""
    try:
        # Validate credentials using auth bridge
        user_info = await auth_bridge.validate_credentials(credentials.credentials)
        if not user_info:
            raise HTTPException(status_code=401, detail="Invalid authentication credentials")
        return user_info
    except Exception as e:
        logger.error(f"Authentication error: {str(e)}")
        raise HTTPException(status_code=401, detail="Authentication failed")


# Circuit breaker for Azure ML API calls
@circuit(failure_threshold=5, recovery_timeout=30, expected_exception=Exception)
async def call_azure_ml_api(endpoint: str, payload: Dict[str, Any], headers: Dict[str, str]) -> Dict[str, Any]:
    """Make circuit-breaker protected call to Azure ML API"""
    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(endpoint, json=payload, headers=headers)
        response.raise_for_status()
        return response.json()


# API Endpoints
@app.get("/health", response_model=HealthStatus)
async def health_check():
    """Health check endpoint"""
    try:
        health_data = await health_checker.get_health_status()
        return HealthStatus(
            status=health_data["status"],
            timestamp=datetime.utcnow().isoformat(),
            version="1.0.0",
            uptime_seconds=health_data["uptime"],
            azure_ml_status=health_data["azure_ml_status"],
            dependencies=health_data["dependencies"]
        )
    except Exception as e:
        logger.error(f"Health check failed: {str(e)}")
        raise HTTPException(status_code=503, detail="Service unavailable")


@app.get("/metrics")
async def get_metrics(user_info: Dict = Depends(authenticate_request)):
    """Get service metrics (authenticated endpoint)"""
    try:
        metrics_data = await metrics.get_current_metrics()
        return metrics_data
    except Exception as e:
        logger.error(f"Metrics retrieval failed: {str(e)}")
        raise HTTPException(status_code=500, detail="Failed to retrieve metrics")


@app.post("/predict", response_model=LegacyPredictionResponse)
async def predict(
    request: LegacyPredictionRequest,
    http_request: Request,
    user_info: Dict = Depends(authenticate_request)
):
    """Main prediction endpoint for legacy systems"""
    context: RequestContext = http_request.state.context

    try:
        logger.info(f"Processing prediction request {context.request_id}")

        # Transform legacy request to Azure ML format
        azure_ml_payload = await transform_request_to_azure_ml(request, context)

        # Get Azure ML endpoint and headers
        endpoint_url = await auth_bridge.get_azure_ml_endpoint(request.model_id)
        auth_headers = await auth_bridge.get_azure_ml_headers(user_info)

        # Make prediction call with circuit breaker
        azure_ml_response = await call_azure_ml_api(
            endpoint=endpoint_url,
            payload=azure_ml_payload,
            headers=auth_headers
        )

        # Transform Azure ML response to legacy format
        legacy_response = await transform_response_to_legacy(
            azure_ml_response,
            context
        )

        logger.info(f"Successfully processed request {context.request_id}")
        return legacy_response

    except HTTPException:
        raise
    except Exception as e:
        error_response = await error_handler.handle_prediction_error(e, context)
        logger.error(f"Prediction failed for request {context.request_id}: {str(e)}")
        raise HTTPException(
            status_code=error_response["status_code"],
            detail=error_response["detail"]
        )


@app.post("/batch-predict")
async def batch_predict(
    requests: List[LegacyPredictionRequest],
    http_request: Request,
    user_info: Dict = Depends(authenticate_request)
):
    """Batch prediction endpoint for legacy systems"""
    context: RequestContext = http_request.state.context

    try:
        logger.info(f"Processing batch prediction with {len(requests)} requests")

        # Process requests concurrently with rate limiting
        semaphore = asyncio.Semaphore(config.max_concurrent_requests)

        async def process_single_request(req: LegacyPredictionRequest) -> LegacyPredictionResponse:
            async with semaphore:
                # Create sub-context for individual request
                sub_context = RequestContext(
                    request_id=f"{context.request_id}_{req.correlation_id or 'batch'}",
                    correlation_id=req.correlation_id,
                    start_time=time.time(),
                    legacy_format=context.legacy_format,
                    auth_token=context.auth_token
                )

                azure_ml_payload = await transform_request_to_azure_ml(req, sub_context)
                endpoint_url = await auth_bridge.get_azure_ml_endpoint(req.model_id)
                auth_headers = await auth_bridge.get_azure_ml_headers(user_info)

                azure_ml_response = await call_azure_ml_api(
                    endpoint=endpoint_url,
                    payload=azure_ml_payload,
                    headers=auth_headers
                )

                return await transform_response_to_legacy(azure_ml_response, sub_context)

        # Execute batch processing
        responses = await asyncio.gather(
            *[process_single_request(req) for req in requests],
            return_exceptions=True
        )

        # Handle any exceptions in batch
        processed_responses = []
        for i, response in enumerate(responses):
            if isinstance(response, Exception):
                error_response = await error_handler.handle_prediction_error(response, context)
                processed_responses.append({
                    "error": True,
                    "status_code": error_response["status_code"],
                    "detail": error_response["detail"],
                    "request_index": i
                })
            else:
                processed_responses.append(response)

        return {
            "batch_id": context.request_id,
            "total_requests": len(requests),
            "successful_predictions": len([r for r in processed_responses if not r.get("error")]),
            "failed_predictions": len([r for r in processed_responses if r.get("error")]),
            "responses": processed_responses
        }

    except Exception as e:
        logger.error(f"Batch prediction failed: {str(e)}")
        raise HTTPException(status_code=500, detail="Batch prediction failed")


# Helper functions
async def transform_request_to_azure_ml(
    request: LegacyPredictionRequest,
    context: RequestContext
) -> Dict[str, Any]:
    """Transform legacy request format to Azure ML API format"""
    # Map legacy input format to Azure ML expected format
    # This would be customized based on specific Azure ML model requirements

    azure_ml_payload = {
        "data": [request.input_data],
        "method": "predict"
    }

    # Add metadata if needed
    if request.model_id:
        azure_ml_payload["model_id"] = request.model_id

    if context.correlation_id:
        azure_ml_payload["correlation_id"] = context.correlation_id

    return azure_ml_payload


async def transform_response_to_legacy(
    azure_ml_response: Dict[str, Any],
    context: RequestContext
) -> LegacyPredictionResponse:
    """Transform Azure ML response to legacy format"""

    # Extract prediction from Azure ML response
    # This would be customized based on specific Azure ML response format
    prediction = azure_ml_response.get("result", [None])[0]
    confidence = azure_ml_response.get("confidence", None)
    model_version = azure_ml_response.get("model_version", None)

    return LegacyPredictionResponse(
        prediction=prediction,
        confidence=confidence,
        model_version=model_version,
        request_id=context.request_id,
        timestamp=datetime.utcnow().isoformat(),
        status="success"
    )


# Application entry point
if __name__ == "__main__":
    uvicorn.run(
        "api_gateway:app",
        host=config.host,
        port=config.port,
        log_level=config.log_level,
        reload=config.debug_mode
    )