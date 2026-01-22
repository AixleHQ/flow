import {
  Box,
  Card,
  FormControl,
  InputLabel,
  MenuItem,
  Select,
  Typography,
} from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { useState } from 'react';

interface ICostDataPoint {
  date: string;
  cost: number;
  tokens: number;
  requests: number;
}

interface ICostBreakdown {
  category: string;
  cost: number;
  percentage: number;
}

interface CostAnalyticsProps {
  period?: '7d' | '30d' | '90d' | '1y';
  projectId?: string;
}

const styles = {
  container: {
    padding: '24px',
  },
  header: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: '24px',
  },
  title: {
    fontSize: '20px',
    fontWeight: 600,
    color: 'text.primary',
  },
  periodSelect: {
    minWidth: '120px',
    '& .MuiOutlinedInput-root': {
      backgroundColor: 'background.elevated',
    },
  },
  statsGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))',
    gap: '16px',
    marginBottom: '32px',
  },
  statCard: {
    padding: '20px',
    backgroundColor: 'background.paper',
    borderRadius: '12px',
    border: '1px solid',
    borderColor: 'divider',
  },
  statLabel: {
    fontSize: '13px',
    color: 'text.secondary',
    marginBottom: '8px',
  },
  statValue: {
    fontSize: '28px',
    fontWeight: 700,
    color: 'text.primary',
    marginBottom: '4px',
  },
  statChange: {
    fontSize: '12px',
    color: 'success.main',
  },
  chartContainer: {
    marginBottom: '32px',
  },
  chartCard: {
    padding: '24px',
    backgroundColor: 'background.paper',
    borderRadius: '12px',
    border: '1px solid',
    borderColor: 'divider',
    minHeight: '300px',
  },
  chartTitle: {
    fontSize: '16px',
    fontWeight: 600,
    color: 'text.primary',
    marginBottom: '20px',
  },
  chartPlaceholder: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    minHeight: '250px',
    color: 'text.secondary',
  },
  chartIcon: {
    fontSize: '48px',
    marginBottom: '16px',
  },
  breakdownCard: {
    padding: '24px',
    backgroundColor: 'background.paper',
    borderRadius: '12px',
    border: '1px solid',
    borderColor: 'divider',
  },
  breakdownTitle: {
    fontSize: '16px',
    fontWeight: 600,
    color: 'text.primary',
    marginBottom: '20px',
  },
  breakdownItem: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: '12px 0',
    borderBottom: '1px solid',
    borderColor: 'divider',
    '&:last-child': {
      borderBottom: 'none',
    },
  },
  breakdownCategory: {
    fontSize: '14px',
    color: 'text.primary',
  },
  breakdownCost: {
    fontSize: '14px',
    fontWeight: 500,
    color: 'text.primary',
  },
  breakdownPercentage: {
    fontSize: '12px',
    color: 'text.secondary',
    marginLeft: '8px',
  },
  progressBar: {
    height: '4px',
    borderRadius: '2px',
    backgroundColor: 'background.elevated',
    marginTop: '8px',
  },
  progressFill: {
    height: '100%',
    borderRadius: '2px',
    backgroundColor: 'primary.main',
  },
} satisfies Record<string, SxProps<Theme>>;

// Mock data generators
const generateMockData = (period: string): ICostDataPoint[] => {
  const days = period === '7d' ? 7 : period === '30d' ? 30 : period === '90d' ? 90 : 365;
  const data: ICostDataPoint[] = [];
  const baseDate = new Date();
  baseDate.setDate(baseDate.getDate() - days);

  for (let i = 0; i < days; i++) {
    const date = new Date(baseDate);
    date.setDate(date.getDate() + i);
    data.push({
      date: date.toISOString().split('T')[0],
      cost: Math.random() * 100 + 50,
      tokens: Math.floor(Math.random() * 100000 + 50000),
      requests: Math.floor(Math.random() * 100 + 50),
    });
  }
  return data;
};

const mockBreakdown: ICostBreakdown[] = [
  { category: 'Claude API', cost: 847.30, percentage: 68 },
  { category: 'OpenAI API', cost: 312.20, percentage: 25 },
  { category: 'Storage (S3)', cost: 88.00, percentage: 7 },
];

const CostAnalytics = ({ period: initialPeriod = '30d', projectId }: CostAnalyticsProps) => {
  const [period, setPeriod] = useState<'7d' | '30d' | '90d' | '1y'>(initialPeriod);
  const data = generateMockData(period);

  const totalCost = data.reduce((sum, d) => sum + d.cost, 0);
  const totalTokens = data.reduce((sum, d) => sum + d.tokens, 0);
  const totalRequests = data.reduce((sum, d) => sum + d.requests, 0);
  const avgDailyCost = totalCost / data.length;

  return (
    <Box sx={styles.container}>
      <Box sx={styles.header}>
        <Typography sx={styles.title}>Cost Analytics</Typography>
        <FormControl size="small" sx={styles.periodSelect}>
          <InputLabel>Period</InputLabel>
          <Select value={period} label="Period" onChange={(e) => setPeriod(e.target.value as any)}>
            <MenuItem value="7d">Last 7 days</MenuItem>
            <MenuItem value="30d">Last 30 days</MenuItem>
            <MenuItem value="90d">Last 90 days</MenuItem>
            <MenuItem value="1y">Last year</MenuItem>
          </Select>
        </FormControl>
      </Box>

      {/* Stats */}
      <Box sx={styles.statsGrid}>
        <Card sx={styles.statCard}>
          <Typography sx={styles.statLabel}>Total Cost</Typography>
          <Typography sx={styles.statValue}>${totalCost.toFixed(2)}</Typography>
          <Typography sx={styles.statChange}>+12.5% vs previous period</Typography>
        </Card>
        <Card sx={styles.statCard}>
          <Typography sx={styles.statLabel}>Total Tokens</Typography>
          <Typography sx={styles.statValue}>{totalTokens.toLocaleString()}</Typography>
          <Typography sx={styles.statChange}>+8.3% vs previous period</Typography>
        </Card>
        <Card sx={styles.statCard}>
          <Typography sx={styles.statLabel}>Total Requests</Typography>
          <Typography sx={styles.statValue}>{totalRequests.toLocaleString()}</Typography>
          <Typography sx={styles.statChange}>+15.2% vs previous period</Typography>
        </Card>
        <Card sx={styles.statCard}>
          <Typography sx={styles.statLabel}>Avg Daily Cost</Typography>
          <Typography sx={styles.statValue}>${avgDailyCost.toFixed(2)}</Typography>
          <Typography sx={styles.statChange}>+5.1% vs previous period</Typography>
        </Card>
      </Box>

      {/* Chart Placeholder */}
      <Box sx={styles.chartContainer}>
        <Card sx={styles.chartCard}>
          <Typography sx={styles.chartTitle}>Cost Over Time</Typography>
          <Box sx={styles.chartPlaceholder}>
            <Typography sx={styles.chartIcon}>📊</Typography>
            <Typography sx={{ fontSize: '14px', color: 'text.secondary' }}>
              Chart visualization would appear here
            </Typography>
            <Typography sx={{ fontSize: '12px', color: 'text.disabled', marginTop: '8px' }}>
              Integrate with a charting library (e.g., recharts, chart.js) to display cost trends
            </Typography>
          </Box>
        </Card>
      </Box>

      {/* Cost Breakdown */}
      <Card sx={styles.breakdownCard}>
        <Typography sx={styles.breakdownTitle}>Cost Breakdown</Typography>
        {mockBreakdown.map((item) => (
          <Box key={item.category} sx={styles.breakdownItem}>
            <Box sx={{ flex: 1 }}>
              <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <Typography sx={styles.breakdownCategory}>{item.category}</Typography>
                <Box sx={{ display: 'flex', alignItems: 'center' }}>
                  <Typography sx={styles.breakdownCost}>${item.cost.toFixed(2)}</Typography>
                  <Typography sx={styles.breakdownPercentage}>({item.percentage}%)</Typography>
                </Box>
              </Box>
              <Box sx={styles.progressBar}>
                <Box sx={{ ...styles.progressFill, width: `${item.percentage}%` }} />
              </Box>
            </Box>
          </Box>
        ))}
        <Box sx={{ ...styles.breakdownItem, marginTop: '8px', paddingTop: '16px', borderTop: '1px solid', borderColor: 'divider' }}>
          <Typography sx={{ ...styles.breakdownCategory, fontWeight: 600 }}>Total</Typography>
          <Typography sx={{ ...styles.breakdownCost, fontWeight: 600 }}>
            ${mockBreakdown.reduce((sum, item) => sum + item.cost, 0).toFixed(2)}
          </Typography>
        </Box>
      </Card>
    </Box>
  );
};

export default CostAnalytics;
