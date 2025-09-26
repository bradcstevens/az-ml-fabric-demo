# Power BI Dashboard Deployment Guide

This guide provides step-by-step instructions for deploying the ML Predictions Dashboard to Power BI Service.

## Prerequisites Checklist

- [ ] Power BI Premium license assigned
- [ ] Azure OneLake access permissions
- [ ] Power BI Desktop installed (latest version)
- [ ] Admin access to Power BI Service workspace
- [ ] OneLake connection string and credentials

## Deployment Steps

### Phase 1: Environment Preparation

#### 1.1 Verify Power BI License
```powershell
# Check Power BI license status
Get-PowerBIWorkspace -Scope User | Select-Object Name, IsOnDedicatedCapacity
```

#### 1.2 Create Power BI Workspace
1. Navigate to Power BI Service (app.powerbi.com)
2. Click **Workspaces** → **Create a workspace**
3. Name: `ML Predictions Analytics`
4. Description: `Azure ML batch predictions reporting`
5. Select **Premium** capacity
6. Click **Save**

#### 1.3 Configure Workspace Permissions
```json
{
  "workspacePermissions": [
    {
      "role": "Admin",
      "users": ["mleng-admin@company.com"]
    },
    {
      "role": "Member",
      "users": ["data-analysts@company.com"]
    },
    {
      "role": "Viewer",
      "users": ["business-users@company.com"]
    }
  ]
}
```

### Phase 2: Data Source Configuration

#### 2.1 OneLake Connection Setup
1. Open Power BI Desktop
2. **Get Data** → **More** → **OneLake (Beta)**
3. Enter OneLake URL: `https://onelake.dfs.fabric.microsoft.com/`
4. Navigate to workspace: `{your-fabric-workspace}`
5. Select lakehouse: `ml-predictions-lakehouse`

#### 2.2 Authenticate with Azure
```bash
# Ensure Azure CLI is logged in
az login
az account show

# Verify Fabric permissions
az rest --method GET --url "https://api.fabric.microsoft.com/v1/workspaces"
```

#### 2.3 Import Prediction Tables
Select the following tables from OneLake:
- `batch_predictions`
- `model_metrics`
- `feature_importance`

### Phase 3: Data Model Implementation

#### 3.1 Import Data Model Configuration
1. Copy content from `templates/data_model.json`
2. In Power BI Desktop, go to **Model** view
3. Create relationships as specified:
   - `Predictions[model_version]` → `ModelMetrics[model_version]`
   - `FeatureImportance[model_version]` → `ModelMetrics[model_version]`

#### 3.2 Create Calculated Measures
```dax
-- Total Predictions
Total Predictions = COUNT(Predictions[prediction_id])

-- Average Confidence
Average Confidence = AVERAGE(Predictions[confidence_score])

-- Prediction Accuracy
Prediction Accuracy =
CALCULATE(
    AVERAGE(ModelMetrics[metric_value]),
    ModelMetrics[metric_name] = "accuracy"
)

-- Latest Prediction Time
Latest Prediction Time = MAX(Predictions[timestamp])
```

#### 3.3 Add Calculated Columns
```dax
-- Confidence Category
Confidence Category =
IF(
    Predictions[confidence_score] >= 0.8, "High",
    IF(Predictions[confidence_score] >= 0.6, "Medium", "Low")
)

-- Prediction Date
Prediction Date =
DATE(
    YEAR(Predictions[timestamp]),
    MONTH(Predictions[timestamp]),
    DAY(Predictions[timestamp])
)
```

### Phase 4: Dashboard Creation

#### 4.1 Build Overview Page
1. **Create new page**: "Overview"
2. **Add visualizations** per `templates/dashboard_layout.json`:
   - Summary cards (3): Total Predictions, Avg Confidence, Model Accuracy
   - Line chart: Predictions Over Time
   - Donut chart: Confidence Distribution
   - Bar chart: Feature Importance

#### 4.2 Configure Visualizations
```json
{
  "predictionsSummaryCard": {
    "visualization": "Card",
    "field": "Total Predictions",
    "filter": "Predictions[Prediction Date] = TODAY()"
  },
  "predictionsTimeline": {
    "visualization": "Line Chart",
    "xAxis": "Predictions[timestamp]",
    "yAxis": "Total Predictions",
    "legend": "Predictions[model_version]"
  }
}
```

#### 4.3 Build Detailed Analysis Page
1. **Create new page**: "Detailed Analysis"
2. **Add visualizations**:
   - Table: Recent Predictions
   - Line chart: Model Performance Trends
   - Matrix: Prediction Heatmap

#### 4.4 Add Interactive Filters
1. **Date Range Slicer**: `Predictions[timestamp]`
2. **Model Version Filter**: `Predictions[model_version]`
3. **Confidence Threshold**: `Predictions[confidence_score]`

### Phase 5: Refresh Configuration

#### 5.1 Configure Scheduled Refresh
1. In Power BI Desktop: **File** → **Options** → **Data Load**
2. Set refresh schedule:
   ```json
   {
     "refreshSchedule": {
       "frequency": "Daily",
       "time": "06:00",
       "timezone": "UTC",
       "enabled": true
     }
   }
   ```

#### 5.2 Enable Incremental Refresh
1. **Table Tools** → **Incremental Refresh**
2. Configure parameters:
   - Archive data: 2 years
   - Incremental data: 7 days
   - Only refresh complete days: True

### Phase 6: Deployment to Service

#### 6.1 Publish Dashboard
1. **Home** → **Publish**
2. Select workspace: `ML Predictions Analytics`
3. Choose **Replace** if updating existing dashboard
4. Click **Open 'ML_Predictions_Dashboard.pbix' in Power BI**

#### 6.2 Configure Data Source Credentials
1. In Power BI Service, go to **Settings** → **Datasets**
2. Select `ML_Predictions_Dashboard`
3. **Data source credentials** → **Edit credentials**
4. Select **OAuth2** authentication method
5. **Sign in** with service account

#### 6.3 Set Up Refresh Schedule
1. **Datasets** → **ML_Predictions_Dashboard** → **Schedule refresh**
2. Configure schedule:
   ```json
   {
     "refreshSettings": {
       "frequency": "Daily",
       "times": ["06:00"],
       "timezone": "UTC",
       "sendFailureNotifications": true,
       "notifyUsers": ["admin@company.com"]
     }
   }
   ```

### Phase 7: Testing and Validation

#### 7.1 Data Connectivity Test
```powershell
# Test OneLake connection
Test-NetConnection -ComputerName "onelake.dfs.fabric.microsoft.com" -Port 443

# Verify data refresh
Invoke-PowerBIRestMethod -Url "datasets/{dataset-id}/refreshes" -Method GET
```

#### 7.2 Dashboard Functionality Test
- [ ] All visualizations load correctly
- [ ] Filters work as expected
- [ ] Data refreshes successfully
- [ ] Real-time updates function (if enabled)
- [ ] Export capabilities work
- [ ] Mobile view renders properly

#### 7.3 Performance Validation
- [ ] Dashboard loads within 10 seconds
- [ ] Queries execute within 5 seconds
- [ ] Large dataset handling performs adequately
- [ ] Concurrent user access works smoothly

### Phase 8: User Access and Training

#### 8.1 Configure Row-Level Security (Optional)
```dax
-- Create RLS filter
[UserEmail] = USERPRINCIPALNAME()
```

#### 8.2 Share Dashboard
1. **Share** → **Grant access**
2. Add user emails with appropriate permissions
3. Configure sharing settings:
   ```json
   {
     "shareSettings": {
       "allowRecipients": {
         "reshare": false,
         "buildContent": false
       },
       "requireRecipients": {
         "outlook": true,
         "sharepoint": false
       }
     }
   }
   ```

#### 8.3 Create User Documentation
- Dashboard navigation guide
- Filter usage instructions
- Interpretation of metrics
- Contact information for support

## Post-Deployment Monitoring

### Performance Metrics to Track
- Dashboard load times
- Query execution duration
- Refresh success rate
- User engagement metrics
- Data quality indicators

### Maintenance Schedule
- **Weekly**: Monitor refresh logs
- **Monthly**: Review performance metrics
- **Quarterly**: Update dashboard based on user feedback
- **Annually**: Comprehensive security review

## Rollback Procedure

If deployment issues occur:

1. **Immediate**: Revert to previous dashboard version
2. **Data Issues**: Switch to backup data source
3. **Performance**: Enable DirectQuery mode temporarily
4. **Access Issues**: Reset workspace permissions

## Support and Troubleshooting

### Common Deployment Issues

| Issue | Cause | Solution |
|-------|-------|---------|
| Connection failed | Authentication | Re-authenticate OneLake credentials |
| Slow performance | Large dataset | Enable incremental refresh |
| Refresh errors | Permission changes | Update service account permissions |
| Visual errors | Missing data | Validate data model relationships |

### Contact Information
- **Deployment Support**: deployment-team@company.com
- **Power BI Admin**: powerbi-admin@company.com
- **Emergency Escalation**: +1-555-EMERGENCY

## Compliance and Security

### Data Privacy
- All PII data masked in dashboards
- Audit logging enabled for data access
- GDPR compliance for EU users

### Security Controls
- Multi-factor authentication required
- Regular access reviews
- Encrypted data transmission
- Secure credential storage

This deployment guide ensures a smooth and secure rollout of the ML Predictions Dashboard to production environments.