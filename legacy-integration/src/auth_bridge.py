"""
Authentication Bridge for Legacy Systems

This module handles authentication translation between legacy systems
and Azure ML endpoints, supporting multiple authentication methods.
"""

import asyncio
import json
import logging
import time
from datetime import datetime, timedelta
from typing import Dict, Any, Optional, List
from dataclasses import dataclass
import hashlib
import base64

import httpx
import jwt
from cryptography.fernet import Fernet
from azure.identity.aio import DefaultAzureCredential, ClientSecretCredential
from azure.keyvault.secrets.aio import SecretClient

from .config import AuthConfig


logger = logging.getLogger(__name__)


@dataclass
class UserInfo:
    """User information from authentication"""
    user_id: str
    username: str
    roles: List[str]
    permissions: List[str]
    expires_at: datetime


@dataclass
class AzureMLEndpointInfo:
    """Azure ML endpoint configuration"""
    endpoint_url: str
    api_key: str
    model_name: str
    model_version: str
    deployment_name: str


class TokenCache:
    """In-memory token cache with TTL"""

    def __init__(self):
        self._cache: Dict[str, Dict[str, Any]] = {}
        self._lock = asyncio.Lock()

    async def get(self, key: str) -> Optional[Dict[str, Any]]:
        """Get cached token if not expired"""
        async with self._lock:
            if key in self._cache:
                token_data = self._cache[key]
                if datetime.utcnow() < token_data["expires_at"]:
                    return token_data
                else:
                    del self._cache[key]
            return None

    async def set(self, key: str, token_data: Dict[str, Any], ttl_seconds: int = 3600):
        """Cache token with TTL"""
        async with self._lock:
            token_data["expires_at"] = datetime.utcnow() + timedelta(seconds=ttl_seconds)
            self._cache[key] = token_data

    async def clear(self, key: str = None):
        """Clear cache entry or all entries"""
        async with self._lock:
            if key:
                self._cache.pop(key, None)
            else:
                self._cache.clear()


class AuthenticationBridge:
    """Authentication bridge for legacy system integration"""

    def __init__(self, config: AuthConfig):
        self.config = config
        self.token_cache = TokenCache()
        self.azure_credential = None
        self.secret_client = None
        self._endpoint_cache: Dict[str, AzureMLEndpointInfo] = {}
        self._cipher_suite = Fernet(config.encryption_key.encode())

    async def initialize(self):
        """Initialize Azure authentication components"""
        try:
            # Initialize Azure credentials
            if self.config.use_managed_identity:
                self.azure_credential = DefaultAzureCredential()
            else:
                self.azure_credential = ClientSecretCredential(
                    tenant_id=self.config.azure_tenant_id,
                    client_id=self.config.azure_client_id,
                    client_secret=self.config.azure_client_secret
                )

            # Initialize Key Vault client if configured
            if self.config.key_vault_url:
                self.secret_client = SecretClient(
                    vault_url=self.config.key_vault_url,
                    credential=self.azure_credential
                )

            logger.info("Authentication bridge initialized successfully")

        except Exception as e:
            logger.error(f"Failed to initialize authentication bridge: {str(e)}")
            raise

    async def validate_credentials(self, auth_token: str) -> Optional[UserInfo]:
        """Validate incoming authentication credentials"""
        try:
            # Check cache first
            cache_key = self._generate_cache_key(auth_token)
            cached_user = await self.token_cache.get(cache_key)
            if cached_user:
                return UserInfo(**cached_user["user_info"])

            # Determine authentication method
            auth_method = self._detect_auth_method(auth_token)

            user_info = None
            if auth_method == "bearer_jwt":
                user_info = await self._validate_jwt_token(auth_token)
            elif auth_method == "api_key":
                user_info = await self._validate_api_key(auth_token)
            elif auth_method == "basic_auth":
                user_info = await self._validate_basic_auth(auth_token)
            elif auth_method == "legacy_token":
                user_info = await self._validate_legacy_token(auth_token)

            if user_info:
                # Cache successful authentication
                await self.token_cache.set(
                    cache_key,
                    {"user_info": user_info.__dict__},
                    ttl_seconds=self.config.token_cache_ttl
                )

            return user_info

        except Exception as e:
            logger.error(f"Credential validation failed: {str(e)}")
            return None

    async def get_azure_ml_endpoint(self, model_id: Optional[str] = None) -> str:
        """Get Azure ML endpoint URL for the specified model"""
        try:
            # Use default model if none specified
            if not model_id:
                model_id = self.config.default_model_id

            # Check cache first
            if model_id in self._endpoint_cache:
                return self._endpoint_cache[model_id].endpoint_url

            # Retrieve endpoint configuration
            endpoint_info = await self._get_endpoint_info(model_id)
            if endpoint_info:
                self._endpoint_cache[model_id] = endpoint_info
                return endpoint_info.endpoint_url

            raise ValueError(f"No endpoint configured for model: {model_id}")

        except Exception as e:
            logger.error(f"Failed to get Azure ML endpoint: {str(e)}")
            raise

    async def get_azure_ml_headers(self, user_info: UserInfo) -> Dict[str, str]:
        """Get authentication headers for Azure ML API calls"""
        try:
            # Get Azure ML API key
            api_key = await self._get_azure_ml_api_key(user_info)

            headers = {
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
                "User-Agent": "Legacy-Integration-Gateway/1.0"
            }

            # Add additional headers if needed
            if self.config.add_correlation_headers:
                headers["X-User-ID"] = user_info.user_id
                headers["X-Request-Time"] = datetime.utcnow().isoformat()

            return headers

        except Exception as e:
            logger.error(f"Failed to generate Azure ML headers: {str(e)}")
            raise

    def _detect_auth_method(self, auth_token: str) -> str:
        """Detect the authentication method from the token format"""
        if auth_token.startswith("Bearer "):
            token_part = auth_token[7:]
            if self._is_jwt_token(token_part):
                return "bearer_jwt"
            else:
                return "api_key"
        elif auth_token.startswith("Basic "):
            return "basic_auth"
        elif auth_token.startswith("Legacy "):
            return "legacy_token"
        else:
            # Default to API key for simple tokens
            return "api_key"

    def _is_jwt_token(self, token: str) -> bool:
        """Check if token is a JWT"""
        try:
            parts = token.split(".")
            return len(parts) == 3
        except:
            return False

    async def _validate_jwt_token(self, auth_token: str) -> Optional[UserInfo]:
        """Validate JWT token"""
        try:
            # Extract token from Bearer prefix
            token = auth_token.replace("Bearer ", "")

            # For demo purposes, we'll do basic JWT validation
            # In production, you'd validate against your JWT issuer
            decoded = jwt.decode(
                token,
                self.config.jwt_secret_key,
                algorithms=[self.config.jwt_algorithm],
                options={"verify_signature": self.config.jwt_verify_signature}
            )

            return UserInfo(
                user_id=decoded.get("sub", "unknown"),
                username=decoded.get("username", decoded.get("sub", "unknown")),
                roles=decoded.get("roles", ["user"]),
                permissions=decoded.get("permissions", ["predict"]),
                expires_at=datetime.fromtimestamp(decoded.get("exp", time.time() + 3600))
            )

        except jwt.ExpiredSignatureError:
            logger.warning("JWT token expired")
            return None
        except jwt.InvalidTokenError as e:
            logger.warning(f"Invalid JWT token: {str(e)}")
            return None
        except Exception as e:
            logger.error(f"JWT validation error: {str(e)}")
            return None

    async def _validate_api_key(self, auth_token: str) -> Optional[UserInfo]:
        """Validate API key authentication"""
        try:
            # Extract API key
            api_key = auth_token.replace("Bearer ", "").replace("ApiKey ", "")

            # Check against configured API keys
            if api_key in self.config.valid_api_keys:
                key_info = self.config.valid_api_keys[api_key]
                return UserInfo(
                    user_id=key_info.get("user_id", "api_user"),
                    username=key_info.get("username", "api_user"),
                    roles=key_info.get("roles", ["user"]),
                    permissions=key_info.get("permissions", ["predict"]),
                    expires_at=datetime.utcnow() + timedelta(hours=24)
                )

            # If not found in config, check Key Vault
            if self.secret_client:
                try:
                    # Hash the API key for Key Vault lookup
                    key_hash = hashlib.sha256(api_key.encode()).hexdigest()
                    secret_name = f"api-key-{key_hash[:16]}"

                    secret = await self.secret_client.get_secret(secret_name)
                    if secret.value:
                        key_data = json.loads(secret.value)
                        return UserInfo(**key_data)

                except Exception as e:
                    logger.debug(f"API key not found in Key Vault: {str(e)}")

            logger.warning(f"Invalid API key provided")
            return None

        except Exception as e:
            logger.error(f"API key validation error: {str(e)}")
            return None

    async def _validate_basic_auth(self, auth_token: str) -> Optional[UserInfo]:
        """Validate Basic authentication"""
        try:
            # Extract and decode Basic auth
            encoded_credentials = auth_token.replace("Basic ", "")
            decoded_credentials = base64.b64decode(encoded_credentials).decode("utf-8")
            username, password = decoded_credentials.split(":", 1)

            # Check against configured users
            if username in self.config.basic_auth_users:
                user_config = self.config.basic_auth_users[username]
                if user_config["password"] == password:  # In production, use hashed passwords
                    return UserInfo(
                        user_id=username,
                        username=username,
                        roles=user_config.get("roles", ["user"]),
                        permissions=user_config.get("permissions", ["predict"]),
                        expires_at=datetime.utcnow() + timedelta(hours=8)
                    )

            logger.warning(f"Invalid basic auth credentials for user: {username}")
            return None

        except Exception as e:
            logger.error(f"Basic auth validation error: {str(e)}")
            return None

    async def _validate_legacy_token(self, auth_token: str) -> Optional[UserInfo]:
        """Validate legacy system token format"""
        try:
            # Extract legacy token
            legacy_token = auth_token.replace("Legacy ", "")

            # Decrypt if encrypted
            if self.config.encrypt_legacy_tokens:
                try:
                    decrypted_token = self._cipher_suite.decrypt(legacy_token.encode()).decode()
                    legacy_token = decrypted_token
                except Exception as e:
                    logger.warning(f"Failed to decrypt legacy token: {str(e)}")
                    return None

            # Parse legacy token format (customize based on your legacy system)
            # Example format: "userid:timestamp:signature"
            parts = legacy_token.split(":")
            if len(parts) >= 2:
                user_id = parts[0]
                timestamp = int(parts[1])

                # Check if token is not expired (within last 24 hours)
                token_age = time.time() - timestamp
                if token_age < 86400:  # 24 hours
                    return UserInfo(
                        user_id=user_id,
                        username=user_id,
                        roles=["legacy_user"],
                        permissions=["predict"],
                        expires_at=datetime.fromtimestamp(timestamp + 86400)
                    )

            logger.warning("Invalid or expired legacy token")
            return None

        except Exception as e:
            logger.error(f"Legacy token validation error: {str(e)}")
            return None

    async def _get_endpoint_info(self, model_id: str) -> Optional[AzureMLEndpointInfo]:
        """Retrieve Azure ML endpoint information"""
        try:
            # Try to get from Key Vault first
            if self.secret_client:
                secret_name = f"ml-endpoint-{model_id}"
                try:
                    secret = await self.secret_client.get_secret(secret_name)
                    if secret.value:
                        endpoint_data = json.loads(secret.value)
                        return AzureMLEndpointInfo(**endpoint_data)
                except Exception as e:
                    logger.debug(f"Endpoint info not found in Key Vault: {str(e)}")

            # Fall back to configuration
            if model_id in self.config.model_endpoints:
                endpoint_config = self.config.model_endpoints[model_id]
                return AzureMLEndpointInfo(**endpoint_config)

            return None

        except Exception as e:
            logger.error(f"Failed to get endpoint info: {str(e)}")
            return None

    async def _get_azure_ml_api_key(self, user_info: UserInfo) -> str:
        """Get Azure ML API key for user"""
        try:
            # Try to get user-specific API key from Key Vault
            if self.secret_client:
                secret_name = f"azure-ml-key-{user_info.user_id}"
                try:
                    secret = await self.secret_client.get_secret(secret_name)
                    if secret.value:
                        return secret.value
                except Exception as e:
                    logger.debug(f"User-specific API key not found: {str(e)}")

            # Fall back to default Azure ML API key
            if self.config.azure_ml_api_key:
                return self.config.azure_ml_api_key

            # Get from Key Vault default
            if self.secret_client:
                try:
                    secret = await self.secret_client.get_secret("azure-ml-api-key")
                    if secret.value:
                        return secret.value
                except Exception as e:
                    logger.debug(f"Default API key not found in Key Vault: {str(e)}")

            raise ValueError("No Azure ML API key available")

        except Exception as e:
            logger.error(f"Failed to get Azure ML API key: {str(e)}")
            raise

    def _generate_cache_key(self, auth_token: str) -> str:
        """Generate cache key for authentication token"""
        return hashlib.sha256(auth_token.encode()).hexdigest()[:32]

    async def close(self):
        """Clean up resources"""
        try:
            if self.azure_credential:
                await self.azure_credential.close()

            if self.secret_client:
                await self.secret_client.close()

            await self.token_cache.clear()

            logger.info("Authentication bridge closed successfully")

        except Exception as e:
            logger.error(f"Error closing authentication bridge: {str(e)}")


# Example usage for testing
if __name__ == "__main__":
    import asyncio
    from .config import AuthConfig

    async def test_auth_bridge():
        config = AuthConfig()
        bridge = AuthenticationBridge(config)

        await bridge.initialize()

        # Test JWT validation
        test_jwt = "Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.test"
        user_info = await bridge.validate_credentials(test_jwt)
        print(f"JWT validation result: {user_info}")

        await bridge.close()

    # Run test
    # asyncio.run(test_auth_bridge())