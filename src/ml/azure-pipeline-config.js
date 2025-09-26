/**
 * Azure ML Pipeline Configuration
 * Task 4: Implement Batch Scoring Pipeline - Azure ML Integration
 *
 * Configures Azure ML Pipelines for batch scoring automation
 */

export class AzurePipelineConfig {
  constructor(options = {}) {
    this.config = {
      subscriptionId: options.subscriptionId || process.env.AZURE_SUBSCRIPTION_ID,
      resourceGroup: options.resourceGroup || process.env.AZURE_RESOURCE_GROUP,
      workspaceName: options.workspaceName || process.env.AZURE_ML_WORKSPACE_NAME,
      computeTarget: options.computeTarget || 'batch-scoring-cluster',
      environment: options.environment || 'ml-pipeline-env',
      ...options
    };
  }

  generatePipelineYAML() {
    return {
      $schema: "https://azuremlschemas.azureedge.net/latest/pipelineJob.schema.json",
      type: "pipeline",
      display_name: "Equipment Failure Batch Scoring Pipeline",
      description: "Automated batch scoring pipeline for equipment failure prediction",

      settings: {
        default_compute: this.config.computeTarget,
        default_datastore: "workspaceblobstore",
        continue_on_step_failure: false
      },

      inputs: {
        input_data: {
          type: "uri_folder",
          path: "azureml://datastores/workspaceblobstore/paths/batch-scoring/input/"
        },
        model_path: {
          type: "uri_folder",
          path: "azureml://datastores/workspaceblobstore/paths/models/latest/"
        }
      },

      outputs: {
        predictions: {
          type: "uri_folder",
          path: "azureml://datastores/workspaceblobstore/paths/batch-scoring/predictions/"
        },
        metrics: {
          type: "uri_file",
          path: "azureml://datastores/workspaceblobstore/paths/batch-scoring/metrics.json"
        }
      },

      jobs: {
        data_validation: {
          type: "command",
          command: "python scripts/validate_input_data.py --input ${{inputs.input_data}} --output ${{outputs.validated_data}}",
          environment: `azureml:${this.config.environment}@latest`,
          compute: this.config.computeTarget,
          inputs: {
            input_data: "${{parent.inputs.input_data}}"
          },
          outputs: {
            validated_data: {
              type: "uri_folder"
            }
          }
        },

        batch_scoring: {
          type: "command",
          command: "python scripts/batch_scoring.py --input ${{inputs.validated_data}} --model ${{inputs.model_path}} --output ${{outputs.predictions}} --metrics ${{outputs.metrics}}",
          environment: `azureml:${this.config.environment}@latest`,
          compute: this.config.computeTarget,
          inputs: {
            validated_data: "${{parent.jobs.data_validation.outputs.validated_data}}",
            model_path: "${{parent.inputs.model_path}}"
          },
          outputs: {
            predictions: "${{parent.outputs.predictions}}",
            metrics: "${{parent.outputs.metrics}}"
          }
        },

        onelake_upload: {
          type: "command",
          command: "python scripts/upload_to_onelake.py --predictions ${{inputs.predictions}} --metrics ${{inputs.metrics}}",
          environment: `azureml:${this.config.environment}@latest`,
          compute: this.config.computeTarget,
          inputs: {
            predictions: "${{parent.jobs.batch_scoring.outputs.predictions}}",
            metrics: "${{parent.jobs.batch_scoring.outputs.metrics}}"
          }
        }
      }
    };
  }

  generateScheduleConfig() {
    return {
      name: "nightly-batch-scoring",
      description: "Nightly execution of batch scoring pipeline",
      trigger: {
        type: "schedule",
        schedule: {
          frequency: "Day",
          interval: 1,
          start_time: "2024-01-01T02:00:00",
          time_zone: "UTC"
        }
      },
      pipeline_job: this.generatePipelineYAML(),
      settings: {
        continue_on_step_failure: false,
        default_compute: this.config.computeTarget
      }
    };
  }

  generateComputeConfig() {
    return {
      name: this.config.computeTarget,
      type: "AmlCompute",
      size: "Standard_DS3_v2",
      min_instances: 0,
      max_instances: 4,
      idle_seconds_before_scaledown: 1800, // 30 minutes
      tier: "Dedicated",
      description: "Compute cluster for batch scoring operations"
    };
  }

  generateEnvironmentConfig() {
    return {
      name: this.config.environment,
      description: "ML Pipeline environment for batch scoring",
      conda_file: {
        name: "ml-pipeline-env",
        channels: ["conda-forge", "pytorch"],
        dependencies: [
          "python=3.9",
          "pip",
          {
            pip: [
              "azureml-core>=1.48.0",
              "azureml-dataset-runtime>=1.48.0",
              "scikit-learn>=1.1.0",
              "pandas>=1.5.0",
              "numpy>=1.21.0",
              "joblib>=1.2.0",
              "azure-storage-blob>=12.14.0",
              "azure-identity>=1.12.0",
              "pyarrow>=10.0.0",
              "fastparquet>=0.8.0"
            ]
          }
        ]
      },
      docker: {
        base_image: "mcr.microsoft.com/azureml/openmpi4.1.0-ubuntu20.04:latest"
      }
    };
  }

  generateMonitoringConfig() {
    return {
      application_insights: {
        connection_string: process.env.APPLICATIONINSIGHTS_CONNECTION_STRING
      },
      alerts: [
        {
          name: "Batch Scoring SLA Alert",
          description: "Alert when batch scoring exceeds 30-minute SLA",
          condition: {
            metric: "pipeline_duration_minutes",
            operator: "GreaterThan",
            threshold: 30
          },
          actions: [
            {
              type: "email",
              recipients: ["ml-ops-team@company.com"]
            }
          ]
        },
        {
          name: "Batch Scoring Failure Alert",
          description: "Alert when batch scoring pipeline fails",
          condition: {
            metric: "pipeline_status",
            operator: "Equals",
            threshold: "Failed"
          },
          actions: [
            {
              type: "email",
              recipients: ["ml-ops-team@company.com"]
            },
            {
              type: "webhook",
              uri: process.env.TEAMS_WEBHOOK_URL
            }
          ]
        }
      ]
    };
  }

  exportAzureCLICommands() {
    const commands = [];

    // Create compute cluster
    commands.push({
      description: "Create compute cluster for batch scoring",
      command: `az ml compute create --type AmlCompute --name ${this.config.computeTarget} --size Standard_DS3_v2 --max-instances 4 --min-instances 0 --idle-time-before-scale-down 1800 --resource-group ${this.config.resourceGroup} --workspace-name ${this.config.workspaceName}`
    });

    // Create environment
    commands.push({
      description: "Create ML environment",
      command: `az ml environment create --file environment.yml --resource-group ${this.config.resourceGroup} --workspace-name ${this.config.workspaceName}`
    });

    // Create pipeline schedule
    commands.push({
      description: "Create nightly schedule for batch scoring",
      command: `az ml schedule create --file schedule.yml --resource-group ${this.config.resourceGroup} --workspace-name ${this.config.workspaceName}`
    });

    return commands;
  }

  validateConfiguration() {
    const errors = [];

    if (!this.config.subscriptionId) {
      errors.push("Azure subscription ID not configured");
    }

    if (!this.config.resourceGroup) {
      errors.push("Azure resource group not configured");
    }

    if (!this.config.workspaceName) {
      errors.push("Azure ML workspace name not configured");
    }

    return {
      isValid: errors.length === 0,
      errors
    };
  }
}