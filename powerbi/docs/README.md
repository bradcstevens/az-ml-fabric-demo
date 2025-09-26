# Power BI Reporting Dashboard

This directory contains the Power BI dashboard configuration for visualizing Azure ML batch predictions from OneLake.

## Overview

The Power BI dashboard provides interactive business intelligence reporting for machine learning predictions, featuring:

- Real-time data visualization from OneLake
- Interactive drill-down capabilities
- Model performance monitoring
- Prediction confidence analysis
- Feature importance insights

## Architecture

```
OneLake (Data Lake) → Power BI Premium → Interactive Dashboards
                   ↓
            Batch Predictions Data
                   ↓
           Power BI Data Model
                   ↓
          Interactive Visualizations
```

## Components

### 1. Data Model (`templates/data_model.json`)
- **Predictions Table**: Core prediction data with timestamps, values, and confidence scores
- **ModelMetrics Table**: Model performance metrics over time
- **FeatureImportance Table**: Feature importance scores for model interpretability
- **Calculated Measures**: KPIs for dashboard summarization
- **Relationships**: Normalized data model for efficient querying

### 2. Dashboard Layout (`templates/dashboard_layout.json`)
- **Overview Page**: High-level summary cards and trend visualizations
- **Detailed Analysis Page**: Drill-down tables and advanced analytics
- **Interactive Filters**: Date range, model version, and confidence threshold controls

### 3. Power BI Template (`templates/ML_Predictions_Dashboard.pbix`)
- Pre-configured dashboard template
- Ready-to-deploy with OneLake connection
- Optimized for Power BI Premium features

## Prerequisites

1. **Power BI Premium License** - Required for OneLake connectivity
2. **Azure OneLake Access** - Permissions to read batch prediction data
3. **Power BI Desktop** - For template customization
4. **Power BI Service Account** - For dashboard deployment

## Setup Instructions

### Step 1: Configure OneLake Connection

1. Open Power BI Desktop
2. Go to **Get Data** → **More** → **OneLake**
3. Enter your OneLake workspace URL
4. Authenticate with Azure AD credentials
5. Select the batch predictions dataset

### Step 2: Import Data Model

1. Import the data model configuration from `templates/data_model.json`
2. Verify table relationships are properly established
3. Validate calculated measures and columns
4. Test data refresh functionality

### Step 3: Build Dashboard

1. Open `templates/ML_Predictions_Dashboard.pbix` in Power BI Desktop
2. Update data source connections to your OneLake instance
3. Customize visualizations based on `templates/dashboard_layout.json`
4. Configure automatic refresh schedules

### Step 4: Deploy to Power BI Service

1. Publish dashboard to Power BI Service
2. Configure workspace permissions
3. Set up scheduled data refresh
4. Share with stakeholders

## Data Sources

### OneLake Tables

- **batch_predictions**: Primary prediction results
  - `prediction_id`: Unique identifier
  - `timestamp`: Prediction generation time
  - `prediction_value`: Model output value
  - `confidence_score`: Prediction confidence (0-1)
  - `model_version`: ML model version used

- **model_metrics**: Model performance tracking
  - `metric_id`: Unique metric identifier
  - `model_version`: Associated model version
  - `metric_name`: Performance metric name (accuracy, precision, recall)
  - `metric_value`: Metric score
  - `timestamp`: Metric calculation time

- **feature_importance**: Model interpretability data
  - `feature_id`: Unique feature identifier
  - `feature_name`: Input feature name
  - `importance_score`: Feature importance weight
  - `model_version`: Associated model version

## Key Measures

- **Total Predictions**: Count of all predictions in selected time range
- **Average Confidence**: Mean confidence score across predictions
- **Prediction Accuracy**: Latest model accuracy metric
- **Latest Prediction Time**: Most recent prediction timestamp

## Visualizations

### Overview Page
- **Summary Cards**: Total predictions, average confidence, model accuracy
- **Trend Analysis**: Predictions over time by model version
- **Confidence Distribution**: Pie chart of high/medium/low confidence predictions
- **Feature Importance**: Bar chart of top contributing features

### Detailed Analysis Page
- **Predictions Table**: Detailed list of recent predictions with drill-down
- **Performance Trends**: Model metrics over time
- **Prediction Heatmap**: Volume analysis by time of day and date

## Refresh Configuration

### Scheduled Refresh
- **Frequency**: Daily at 6:00 AM
- **Incremental Refresh**: Enabled (7 days incremental, 2 years archive)
- **Failure Notifications**: Configured for admin users

### Real-time Updates
- **DirectQuery**: For live dashboard updates (optional)
- **Streaming**: For real-time prediction monitoring
- **Push Datasets**: For immediate metric updates

## Security and Permissions

### Data Access
- Row-level security based on user roles
- OneLake permissions inherited
- Sensitive data masking for non-privileged users

### Dashboard Sharing
- **Viewers**: Read-only access to dashboards
- **Contributors**: Can modify visualizations
- **Admins**: Full access including data source configuration

## Monitoring and Maintenance

### Performance Optimization
- Monitor query performance using Power BI metrics
- Optimize data model for large datasets
- Implement partitioning for historical data

### Data Quality
- Validate data freshness indicators
- Monitor for data anomalies
- Set up alerts for missing predictions

## Troubleshooting

### Common Issues

1. **Connection Failures**
   - Verify OneLake permissions
   - Check network connectivity
   - Validate authentication credentials

2. **Slow Performance**
   - Review data model complexity
   - Optimize DAX calculations
   - Consider DirectQuery vs Import mode

3. **Data Inconsistencies**
   - Validate source data quality
   - Check refresh schedules
   - Review filter configurations

### Support Contacts
- **Power BI Admin**: [admin@company.com]
- **Data Engineering**: [dataeng@company.com]
- **ML Engineering**: [mleng@company.com]

## Version History

- **v1.0**: Initial dashboard with basic prediction visualization
- **v1.1**: Added model performance tracking
- **v1.2**: Implemented feature importance analysis
- **v1.3**: Enhanced real-time capabilities

## Related Documentation

- [Azure ML Pipeline Documentation](../docs/ml-pipeline.md)
- [OneLake Configuration Guide](../docs/onelake-setup.md)
- [Data Governance Policies](../docs/governance.md)