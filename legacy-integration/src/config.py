"""
Configuration management for Legacy Integration Gateway

This module handles all configuration settings for the API gateway,
authentication bridge, and monitoring components.
"""

import os
import json
import logging
from typing import Dict, Any, List, Optional
from dataclasses import dataclass, field
from pathlib import Path

import yaml
from cryptography.fernet import Fernet


logger = logging.getLogger(__name__)


@dataclass
class AuthConfig:
    """Authentication configuration"""
    # JWT Configuration
    jwt_secret_key: str = field(default_factory=lambda: os.getenv("JWT_SECRET_KEY", "your-secret-key"))
    jwt_algorithm: str = "HS256"
    jwt_verify_signature: bool = True
    token_cache_ttl: int = 3600  # 1 hour

    # Azure Configuration
    azure_tenant_id: str = field(default_factory=lambda: os.getenv("AZURE_TENANT_ID", ""))
    azure_client_id: str = field(default_factory=lambda: os.getenv("AZURE_CLIENT_ID", ""))
    azure_client_secret: str = field(default_factory=lambda: os.getenv("AZURE_CLIENT_SECRET", ""))
    use_managed_identity: bool = field(default_factory=lambda: os.getenv("USE_MANAGED_IDENTITY", "false").lower() == "true")

    # Key Vault Configuration
    key_vault_url: str = field(default_factory=lambda: os.getenv("KEY_VAULT_URL", ""))

    # Azure ML Configuration
    azure_ml_api_key: str = field(default_factory=lambda: os.getenv("AZURE_ML_API_KEY", ""))
    default_model_id: str = field(default_factory=lambda: os.getenv("DEFAULT_MODEL_ID", "default"))

    # Legacy System Configuration
    encrypt_legacy_tokens: bool = True
    encryption_key: str = field(default_factory=lambda: os.getenv("ENCRYPTION_KEY", Fernet.generate_key().decode()))

    # API Keys for validation
    valid_api_keys: Dict[str, Dict[str, Any]] = field(default_factory=dict)

    # Basic Auth Users
    basic_auth_users: Dict[str, Dict[str, Any]] = field(default_factory=dict)

    # Model Endpoints Configuration
    model_endpoints: Dict[str, Dict[str, str]] = field(default_factory=dict)

    # Additional Headers
    add_correlation_headers: bool = True


@dataclass
class MonitoringConfig:
    """Monitoring and observability configuration"""
    # Application Insights
    app_insights_connection_string: str = field(default_factory=lambda: os.getenv("APPINSIGHTS_CONNECTION_STRING", ""))
    app_insights_enabled: bool = field(default_factory=lambda: os.getenv("APPINSIGHTS_ENABLED", "false").lower() == "true")

    # Metrics Configuration
    metrics_enabled: bool = True
    metrics_collection_interval: int = 60  # seconds
    metrics_retention_days: int = 30

    # Health Check Configuration
    health_check_interval: int = 30  # seconds
    health_check_timeout: int = 10  # seconds

    # Azure ML Health Check
    azure_ml_health_check_enabled: bool = True
    azure_ml_health_check_endpoint: str = field(default_factory=lambda: os.getenv("AZURE_ML_HEALTH_ENDPOINT", ""))

    # Logging Configuration
    log_level: str = field(default_factory=lambda: os.getenv("LOG_LEVEL", "INFO"))
    structured_logging: bool = True
    log_to_appinsights: bool = field(default_factory=lambda: os.getenv("LOG_TO_APPINSIGHTS", "false").lower() == "true")


@dataclass
class ErrorHandlingConfig:
    """Error handling and resilience configuration"""
    # Circuit Breaker
    circuit_breaker_failure_threshold: int = 5
    circuit_breaker_recovery_timeout: int = 30  # seconds
    circuit_breaker_expected_exception: str = "Exception"

    # Retry Configuration
    max_retry_attempts: int = 3
    retry_backoff_factor: float = 1.5
    retry_max_delay: int = 60  # seconds

    # Timeout Configuration
    request_timeout: int = 30  # seconds
    azure_ml_timeout: int = 25  # seconds

    # Rate Limiting
    rate_limit_enabled: bool = True
    rate_limit_requests_per_minute: int = 1000
    rate_limit_burst_size: int = 100


@dataclass
class GatewayConfig:
    """Main gateway configuration"""
    # Server Configuration
    host: str = field(default_factory=lambda: os.getenv("HOST", "0.0.0.0"))
    port: int = field(default_factory=lambda: int(os.getenv("PORT", "8000")))
    debug_mode: bool = field(default_factory=lambda: os.getenv("DEBUG", "false").lower() == "true")
    log_level: str = field(default_factory=lambda: os.getenv("LOG_LEVEL", "info"))

    # CORS Configuration
    cors_origins: List[str] = field(default_factory=lambda: os.getenv("CORS_ORIGINS", "*").split(","))
    allowed_hosts: List[str] = field(default_factory=lambda: os.getenv("ALLOWED_HOSTS", "*").split(","))

    # Performance Configuration
    max_concurrent_requests: int = field(default_factory=lambda: int(os.getenv("MAX_CONCURRENT_REQUESTS", "100")))
    worker_processes: int = field(default_factory=lambda: int(os.getenv("WORKER_PROCESSES", "1")))

    # Feature Flags
    batch_prediction_enabled: bool = field(default_factory=lambda: os.getenv("BATCH_PREDICTION_ENABLED", "true").lower() == "true")
    metrics_endpoint_enabled: bool = field(default_factory=lambda: os.getenv("METRICS_ENDPOINT_ENABLED", "true").lower() == "true")

    # Sub-configurations
    auth_config: AuthConfig = field(default_factory=AuthConfig)
    monitoring_config: MonitoringConfig = field(default_factory=MonitoringConfig)
    error_handling_config: ErrorHandlingConfig = field(default_factory=ErrorHandlingConfig)


class ConfigManager:
    """Configuration manager for loading and validating settings"""

    def __init__(self, config_file: Optional[str] = None):
        self.config_file = config_file or os.getenv("CONFIG_FILE")
        self.config = GatewayConfig()

    def load_configuration(self) -> GatewayConfig:
        """Load configuration from file and environment variables"""
        try:
            # Load from file if specified
            if self.config_file and Path(self.config_file).exists():
                logger.info(f"Loading configuration from file: {self.config_file}")
                file_config = self._load_config_file(self.config_file)
                self._merge_config(file_config)

            # Load authentication configuration
            self._load_auth_config()

            # Validate configuration
            self._validate_config()

            logger.info("Configuration loaded successfully")
            return self.config

        except Exception as e:
            logger.error(f"Failed to load configuration: {str(e)}")
            raise

    def _load_config_file(self, config_file: str) -> Dict[str, Any]:
        """Load configuration from YAML or JSON file"""
        try:
            with open(config_file, 'r') as f:
                if config_file.endswith('.yaml') or config_file.endswith('.yml'):
                    return yaml.safe_load(f)
                elif config_file.endswith('.json'):
                    return json.load(f)
                else:
                    raise ValueError(f"Unsupported config file format: {config_file}")

        except Exception as e:
            logger.error(f"Failed to load config file {config_file}: {str(e)}")
            raise

    def _merge_config(self, file_config: Dict[str, Any]):
        """Merge file configuration with default configuration"""
        try:
            # Server configuration
            if 'server' in file_config:
                server_config = file_config['server']
                if 'host' in server_config:
                    self.config.host = server_config['host']
                if 'port' in server_config:
                    self.config.port = server_config['port']
                if 'debug_mode' in server_config:
                    self.config.debug_mode = server_config['debug_mode']

            # Authentication configuration
            if 'authentication' in file_config:
                auth_config = file_config['authentication']
                self._merge_auth_config(auth_config)

            # Monitoring configuration
            if 'monitoring' in file_config:
                monitoring_config = file_config['monitoring']
                self._merge_monitoring_config(monitoring_config)

            # Error handling configuration
            if 'error_handling' in file_config:
                error_config = file_config['error_handling']
                self._merge_error_handling_config(error_config)

        except Exception as e:
            logger.error(f"Failed to merge configuration: {str(e)}")
            raise

    def _merge_auth_config(self, auth_config: Dict[str, Any]):
        """Merge authentication configuration"""
        if 'jwt' in auth_config:
            jwt_config = auth_config['jwt']
            if 'algorithm' in jwt_config:
                self.config.auth_config.jwt_algorithm = jwt_config['algorithm']
            if 'verify_signature' in jwt_config:
                self.config.auth_config.jwt_verify_signature = jwt_config['verify_signature']

        if 'azure' in auth_config:
            azure_config = auth_config['azure']
            if 'use_managed_identity' in azure_config:
                self.config.auth_config.use_managed_identity = azure_config['use_managed_identity']

        if 'api_keys' in auth_config:
            self.config.auth_config.valid_api_keys = auth_config['api_keys']

        if 'basic_auth_users' in auth_config:
            self.config.auth_config.basic_auth_users = auth_config['basic_auth_users']

        if 'model_endpoints' in auth_config:
            self.config.auth_config.model_endpoints = auth_config['model_endpoints']

    def _merge_monitoring_config(self, monitoring_config: Dict[str, Any]):
        """Merge monitoring configuration"""
        if 'app_insights_enabled' in monitoring_config:
            self.config.monitoring_config.app_insights_enabled = monitoring_config['app_insights_enabled']

        if 'metrics_enabled' in monitoring_config:
            self.config.monitoring_config.metrics_enabled = monitoring_config['metrics_enabled']

        if 'health_check_interval' in monitoring_config:
            self.config.monitoring_config.health_check_interval = monitoring_config['health_check_interval']

    def _merge_error_handling_config(self, error_config: Dict[str, Any]):
        """Merge error handling configuration"""
        if 'circuit_breaker' in error_config:
            cb_config = error_config['circuit_breaker']
            if 'failure_threshold' in cb_config:
                self.config.error_handling_config.circuit_breaker_failure_threshold = cb_config['failure_threshold']
            if 'recovery_timeout' in cb_config:
                self.config.error_handling_config.circuit_breaker_recovery_timeout = cb_config['recovery_timeout']

        if 'retry' in error_config:
            retry_config = error_config['retry']
            if 'max_attempts' in retry_config:
                self.config.error_handling_config.max_retry_attempts = retry_config['max_attempts']

    def _load_auth_config(self):
        """Load authentication configuration from environment and Key Vault"""
        try:
            # Load API keys from environment variable (JSON format)
            api_keys_json = os.getenv("API_KEYS_CONFIG")
            if api_keys_json:
                try:
                    api_keys = json.loads(api_keys_json)
                    self.config.auth_config.valid_api_keys.update(api_keys)
                except json.JSONDecodeError as e:
                    logger.warning(f"Invalid API_KEYS_CONFIG JSON: {str(e)}")

            # Load basic auth users from environment variable (JSON format)
            basic_auth_json = os.getenv("BASIC_AUTH_USERS")
            if basic_auth_json:
                try:
                    basic_auth_users = json.loads(basic_auth_json)
                    self.config.auth_config.basic_auth_users.update(basic_auth_users)
                except json.JSONDecodeError as e:
                    logger.warning(f"Invalid BASIC_AUTH_USERS JSON: {str(e)}")

            # Load model endpoints from environment variable (JSON format)
            model_endpoints_json = os.getenv("MODEL_ENDPOINTS_CONFIG")
            if model_endpoints_json:
                try:
                    model_endpoints = json.loads(model_endpoints_json)
                    self.config.auth_config.model_endpoints.update(model_endpoints)
                except json.JSONDecodeError as e:
                    logger.warning(f"Invalid MODEL_ENDPOINTS_CONFIG JSON: {str(e)}")

        except Exception as e:
            logger.error(f"Failed to load authentication configuration: {str(e)}")
            raise

    def _validate_config(self):
        """Validate configuration settings"""
        try:
            # Validate required Azure configuration
            if not self.config.auth_config.use_managed_identity:
                if not all([
                    self.config.auth_config.azure_tenant_id,
                    self.config.auth_config.azure_client_id,
                    self.config.auth_config.azure_client_secret
                ]):
                    raise ValueError("Azure service principal configuration is incomplete")

            # Validate at least one authentication method is configured
            has_auth_method = any([
                self.config.auth_config.valid_api_keys,
                self.config.auth_config.basic_auth_users,
                self.config.auth_config.jwt_secret_key != "your-secret-key"
            ])

            if not has_auth_method:
                logger.warning("No authentication methods configured - all requests will be rejected")

            # Validate model endpoints
            if not self.config.auth_config.model_endpoints and not self.config.auth_config.azure_ml_api_key:
                logger.warning("No model endpoints or default Azure ML API key configured")

            # Validate port range
            if not 1 <= self.config.port <= 65535:
                raise ValueError(f"Invalid port number: {self.config.port}")

            # Validate timeout values
            if self.config.error_handling_config.azure_ml_timeout >= self.config.error_handling_config.request_timeout:
                logger.warning("Azure ML timeout should be less than request timeout")

            logger.info("Configuration validation completed successfully")

        except Exception as e:
            logger.error(f"Configuration validation failed: {str(e)}")
            raise

    def save_config_template(self, output_file: str):
        """Save a configuration template file"""
        try:
            template_config = {
                "server": {
                    "host": "0.0.0.0",
                    "port": 8000,
                    "debug_mode": False,
                    "cors_origins": ["*"],
                    "allowed_hosts": ["*"],
                    "max_concurrent_requests": 100
                },
                "authentication": {
                    "jwt": {
                        "algorithm": "HS256",
                        "verify_signature": True
                    },
                    "azure": {
                        "use_managed_identity": True
                    },
                    "api_keys": {
                        "example-api-key": {
                            "user_id": "api_user_1",
                            "username": "api_user_1",
                            "roles": ["user"],
                            "permissions": ["predict"]
                        }
                    },
                    "basic_auth_users": {
                        "legacy_user": {
                            "password": "secure_password",
                            "roles": ["legacy_user"],
                            "permissions": ["predict"]
                        }
                    },
                    "model_endpoints": {
                        "default": {
                            "endpoint_url": "https://your-endpoint.azureml.net/score",
                            "api_key": "your-api-key",
                            "model_name": "your-model",
                            "model_version": "1",
                            "deployment_name": "default"
                        }
                    }
                },
                "monitoring": {
                    "app_insights_enabled": True,
                    "metrics_enabled": True,
                    "health_check_interval": 30,
                    "azure_ml_health_check_enabled": True
                },
                "error_handling": {
                    "circuit_breaker": {
                        "failure_threshold": 5,
                        "recovery_timeout": 30
                    },
                    "retry": {
                        "max_attempts": 3,
                        "backoff_factor": 1.5
                    },
                    "timeouts": {
                        "request_timeout": 30,
                        "azure_ml_timeout": 25
                    }
                }
            }

            with open(output_file, 'w') as f:
                if output_file.endswith('.yaml') or output_file.endswith('.yml'):
                    yaml.dump(template_config, f, default_flow_style=False, indent=2)
                else:
                    json.dump(template_config, f, indent=2)

            logger.info(f"Configuration template saved to: {output_file}")

        except Exception as e:
            logger.error(f"Failed to save configuration template: {str(e)}")
            raise


# Global configuration instance
_config_manager = ConfigManager()
config = _config_manager.load_configuration()


# Export configuration for use in other modules
def get_config() -> GatewayConfig:
    """Get the current configuration"""
    return config


def reload_config(config_file: Optional[str] = None) -> GatewayConfig:
    """Reload configuration from file"""
    global _config_manager, config
    _config_manager = ConfigManager(config_file)
    config = _config_manager.load_configuration()
    return config


# CLI for generating configuration template
if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Legacy Integration Configuration Manager")
    parser.add_argument("--generate-template", type=str, help="Generate configuration template file")
    parser.add_argument("--validate", type=str, help="Validate configuration file")

    args = parser.parse_args()

    if args.generate_template:
        manager = ConfigManager()
        manager.save_config_template(args.generate_template)
        print(f"Configuration template generated: {args.generate_template}")

    elif args.validate:
        try:
            manager = ConfigManager(args.validate)
            config = manager.load_configuration()
            print(f"Configuration file {args.validate} is valid")
        except Exception as e:
            print(f"Configuration validation failed: {str(e)}")
            exit(1)

    else:
        print("Use --generate-template or --validate options")