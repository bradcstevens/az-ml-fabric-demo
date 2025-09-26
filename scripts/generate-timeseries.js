/**
 * Generate synthetic time-series data with seasonal patterns
 */

function generateTimeSeriesData() {
  const data = []
  const startDate = new Date('2024-01-01')
  const days = 400 // More than 365 to meet test requirement

  for (let i = 0; i < days; i++) {
    const date = new Date(startDate)
    date.setDate(date.getDate() + i)

    // Create seasonal pattern (yearly cycle)
    const dayOfYear = Math.floor((date - new Date(date.getFullYear(), 0, 0)) / 86400000)
    const seasonalComponent = Math.sin((dayOfYear / 365) * 2 * Math.PI) * 20

    // Base trend with noise
    const baseValue = 100 + (i * 0.05) + (Math.random() - 0.5) * 10
    const value = baseValue + seasonalComponent

    data.push({
      date: date.toISOString().split('T')[0],
      value: Math.round(value * 100) / 100,
      seasonal_component: Math.round(seasonalComponent * 100) / 100,
      trend: Math.round(baseValue * 100) / 100,
      day_of_year: dayOfYear
    })
  }

  return data
}

export { generateTimeSeriesData }