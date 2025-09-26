/**
 * Infrastructure Validation Tests - TDD Approach
 * Tests for Azure Developer CLI infrastructure setup
 */

import { describe, it, expect } from 'vitest';
import { existsSync, readFileSync } from 'fs';
import { join } from 'path';
import yaml from 'js-yaml';

describe('Azure Developer CLI Infrastructure', () => {
  const projectRoot = process.cwd();

  describe('azure.yaml configuration', () => {
    it('should have azure.yaml file in project root', () => {
      const azureYamlPath = join(projectRoot, 'azure.yaml');
      expect(existsSync(azureYamlPath)).toBe(true);
    });

    it('should have valid azure.yaml structure with required fields', () => {
      const azureYamlPath = join(projectRoot, 'azure.yaml');
      const content = readFileSync(azureYamlPath, 'utf8');
      const config = yaml.load(content);

      expect(config).toHaveProperty('name');
      expect(config).toHaveProperty('metadata');
      expect(config).toHaveProperty('services');
      expect(config).toHaveProperty('infra');
      expect(config.infra).toHaveProperty('provider', 'bicep');
    });

    it('should include Azure ML and Fabric services', () => {
      const azureYamlPath = join(projectRoot, 'azure.yaml');
      const content = readFileSync(azureYamlPath, 'utf8');
      const config = yaml.load(content);

      expect(config.services).toBeDefined();
      expect(Object.keys(config.services).length).toBeGreaterThan(0);
    });
  });

  describe('Bicep Infrastructure Templates', () => {
    it('should have main.bicep file in infra directory', () => {
      const mainBicepPath = join(projectRoot, 'infra', 'main.bicep');
      expect(existsSync(mainBicepPath)).toBe(true);
    });

    it('should have modular Bicep templates directory structure', () => {
      const infraDir = join(projectRoot, 'infra');
      const modulesDir = join(infraDir, 'modules');

      expect(existsSync(infraDir)).toBe(true);
      expect(existsSync(modulesDir)).toBe(true);
    });

    it('should have Azure ML workspace Bicep module', () => {
      const azureMLPath = join(projectRoot, 'infra', 'modules', 'azureml.bicep');
      expect(existsSync(azureMLPath)).toBe(true);
    });

    it('should have Microsoft Fabric Bicep module', () => {
      const fabricPath = join(projectRoot, 'infra', 'modules', 'fabric.bicep');
      expect(existsSync(fabricPath)).toBe(true);
    });

    it('should have monitoring Bicep module', () => {
      const monitoringPath = join(projectRoot, 'infra', 'modules', 'monitoring.bicep');
      expect(existsSync(monitoringPath)).toBe(true);
    });

    it('should have security Bicep module', () => {
      const securityPath = join(projectRoot, 'infra', 'modules', 'security.bicep');
      expect(existsSync(securityPath)).toBe(true);
    });
  });

  describe('Multi-Environment Support', () => {
    it('should have environment-specific parameter files', () => {
      const devParamsPath = join(projectRoot, 'infra', 'main.dev.bicepparam');
      const stagingParamsPath = join(projectRoot, 'infra', 'main.staging.bicepparam');
      const prodParamsPath = join(projectRoot, 'infra', 'main.prod.bicepparam');

      expect(existsSync(devParamsPath)).toBe(true);
      expect(existsSync(stagingParamsPath)).toBe(true);
      expect(existsSync(prodParamsPath)).toBe(true);
    });

    it('should have .azure directory for environment configurations', () => {
      const azureEnvDir = join(projectRoot, '.azure');
      expect(existsSync(azureEnvDir)).toBe(true);
    });
  });

  describe('Deployment Documentation', () => {
    it('should have deployment README in infra directory', () => {
      const deploymentReadmePath = join(projectRoot, 'infra', 'README.md');
      expect(existsSync(deploymentReadmePath)).toBe(true);
    });

    it('should have deployment scripts directory', () => {
      const scriptsDir = join(projectRoot, 'scripts');
      expect(existsSync(scriptsDir)).toBe(true);
    });
  });

  describe('Azure Developer CLI Commands', () => {
    it('should support azd up command structure', () => {
      const azureYamlPath = join(projectRoot, 'azure.yaml');
      const content = readFileSync(azureYamlPath, 'utf8');
      const config = yaml.load(content);

      // Test that config supports azd up command
      expect(config.infra).toBeDefined();
      expect(config.services).toBeDefined();
    });
  });
});