# Reads Locust CSV output files and produces two PNG charts plus an HTML report.
#
# Usage:
#   python3 plot_results.py <stats_history.csv> [request_timestamps.csv]
#
#   stats_history.csv      - Locust --csv *_stats_history.csv file (required)
#   request_timestamps.csv - per-request log written by locustfile.py (optional)

import sys
import os
import pandas as pd
import matplotlib

matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.gridspec as gridspec
from datetime import datetime

if len(sys.argv) < 2:
    print("Use as this: python3 plot_results.py <stats_history.csv> [request_timestamps.csv]")
    sys.exit(1)

history_path = sys.argv[1]
timestamps_path = sys.argv[2] if len(sys.argv) > 2 else None
# Output charts and the HTML report to the same directory as the input CSV
out_dir = os.path.dirname(os.path.abspath(history_path))

df = pd.read_csv(history_path)

df = df[df['Name'] == 'Aggregated'].copy()
df = df.sort_values('Timestamp').reset_index(drop=True)
t0 = df['Timestamp'].iloc[0]
df['elapsed'] = df['Timestamp'] - t0

# --- Chart 1: RPS + Response Time Percentiles + Error Rate (3-panel overview) ---
fig = plt.figure(figsize=(14, 12))
fig.suptitle('VideoSearcher Locust Load Test Results', fontsize=16, fontweight='bold', y=0.98)
gs = gridspec.GridSpec(3, 1, hspace=0.45)

# Panel 1: requests per second over time
ax1 = fig.add_subplot(gs[0])
ax1.plot(df['elapsed'], df['Requests/s'], color='#2196F3', linewidth=1.5, label='RPS')
ax1.fill_between(df['elapsed'], df['Requests/s'], alpha=0.15, color='#2196F3')
ax1.set_title('Requests per Second (RPS)', fontweight='bold')
ax1.set_xlabel('Time (s)')
ax1.set_ylabel('RPS')
ax1.grid(True, alpha=0.3)
ax1.legend()

# Panel 2: response time percentiles (p50 / p95 / p99)
ax2 = fig.add_subplot(gs[1])
if '50%' in df.columns:
    ax2.plot(df['elapsed'], df['50%'],  color='#4CAF50', linewidth=1.5, label='p50')
if '95%' in df.columns:
    ax2.plot(df['elapsed'], df['95%'],  color='#FF9800', linewidth=1.5, label='p95')
if '99%' in df.columns:
    ax2.plot(df['elapsed'], df['99%'],  color='#F44336', linewidth=1.5, label='p99')
ax2.set_title('Response Time Percentiles', fontweight='bold')
ax2.set_xlabel('Time (s)')
ax2.set_ylabel('Response Time (ms)')
ax2.grid(True, alpha=0.3)
ax2.legend()

# Panel 3: error rate as a percentage of total requests
ax3 = fig.add_subplot(gs[2])
if 'Failures/s' in df.columns:
    # Replace zero RPS with NaN to avoid division-by-zero; fill NaN with 0 after
    total = df['Requests/s'].replace(0, float('nan'))
    error_pct = (df['Failures/s'] / total * 100).fillna(0)
    ax3.plot(df['elapsed'], error_pct, color='#F44336', linewidth=1.5, label='Error %')
    ax3.fill_between(df['elapsed'], error_pct, alpha=0.15, color='#F44336')
ax3.set_title('Error Rate (%)', fontweight='bold')
ax3.set_xlabel('Time (s)')
ax3.set_ylabel('Error %')
ax3.set_ylim(bottom=0)
ax3.grid(True, alpha=0.3)
ax3.legend()

chart1_path = os.path.join(out_dir, 'locust_chart_overview.png')
plt.savefig(chart1_path, dpi=150, bbox_inches='tight')
plt.close()
print(f"Saved: {chart1_path}")

# --- Chart 2: per-second request rate + response time histogram (optional) ---
# This chart is produced only when request_timestamps.csv is available; it gives
# a higher-resolution view of the actual arrival rate vs the workload profile
chart2_path = None
if timestamps_path and os.path.exists(timestamps_path):
    print(f"Reading: {timestamps_path}")
    ts_df = pd.read_csv(timestamps_path)
    ts_df = ts_df.sort_values('Timestamp').reset_index(drop=True)
    ts_df['elapsed'] = ts_df['Timestamp'] - ts_df['Timestamp'].iloc[0]

    fig2, (ax_a, ax_b) = plt.subplots(2, 1, figsize=(14, 8))
    fig2.suptitle('Request Timestamps Analysis', fontsize=14, fontweight='bold')

    # Bar chart: one bar per second showing how many requests were sent
    ts_df['second'] = ts_df['elapsed'].astype(int)
    rps_actual = ts_df.groupby('second').size()
    ax_a.bar(rps_actual.index, rps_actual.values, color='#2196F3', alpha=0.7, width=1.0)
    ax_a.set_title('Actual Request Rate (per second)', fontweight='bold')
    ax_a.set_xlabel('Time (s)')
    ax_a.set_ylabel('Requests')
    ax_a.grid(True, alpha=0.3)

    # Histogram: distribution of individual response times in milliseconds
    ax_b.hist(ts_df['ResponseTime'], bins=50, color='#4CAF50', alpha=0.7, edgecolor='white')
    ax_b.set_title('Response Time Distribution', fontweight='bold')
    ax_b.set_xlabel('Response Time (ms)')
    ax_b.set_ylabel('Count')
    ax_b.grid(True, alpha=0.3)

    chart2_path = os.path.join(out_dir, 'locust_chart_timestamps.png')
    plt.tight_layout()
    plt.savefig(chart2_path, dpi=150, bbox_inches='tight')
    plt.close()
    print(f"Saved: {chart2_path}")

# --- Compute summary statistics for the HTML report ---
total_req    = int(df['User count'].sum()) if 'User count' in df.columns else 'N/A'
avg_rps      = df['Requests/s'].mean()
max_rps      = df['Requests/s'].max()
p50          = df['50%'].mean()  if '50%'  in df.columns else 'N/A'
p95          = df['95%'].mean()  if '95%'  in df.columns else 'N/A'
p99          = df['99%'].mean()  if '99%'  in df.columns else 'N/A'
duration     = int(df['elapsed'].max())
generated_at = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

# --- Generate self-contained HTML report embedding both charts ---
chart1_rel = os.path.basename(chart1_path)
chart2_rel = os.path.basename(chart2_path) if chart2_path else None

html = f"""<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>VideoSearcher Locust Report</title>
  <style>
    body {{ font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }}
    h1   {{ color: #333; }}
    h2   {{ color: #555; border-bottom: 2px solid #2196F3; padding-bottom: 6px; }}
    .summary {{ display: flex; flex-wrap: wrap; gap: 16px; margin: 20px 0; }}
    .card {{ background: white; border-radius: 8px; padding: 20px 28px; box-shadow: 0 2px 6px rgba(0,0,0,0.1); min-width: 140px; }}
    .card .val {{ font-size: 2em; font-weight: bold; color: #2196F3; }}
    .card .lbl {{ color: #777; font-size: 0.9em; margin-top: 4px; }}
    img  {{ max-width: 100%; border-radius: 8px; box-shadow: 0 2px 6px rgba(0,0,0,0.1); margin: 12px 0; }}
    .footer {{ color: #aaa; font-size: 0.85em; margin-top: 40px; }}
  </style>
</head>
<body>
  <h1>VideoSearcher — Locust Load Test Report</h1>
  <p>Generated: {generated_at} | Duration: {duration}s</p>

  <h2>Summary</h2>
  <div class="summary">
    <div class="card"><div class="val">{avg_rps:.3f}</div><div class="lbl">Avg RPS</div></div>
    <div class="card"><div class="val">{max_rps:.3f}</div><div class="lbl">Peak RPS</div></div>
    <div class="card"><div class="val">{p50 if isinstance(p50, str) else f"{p50:.0f} ms"}</div><div class="lbl">Avg p50</div></div>
    <div class="card"><div class="val">{p95 if isinstance(p95, str) else f"{p95:.0f} ms"}</div><div class="lbl">Avg p95</div></div>
    <div class="card"><div class="val">{p99 if isinstance(p99, str) else f"{p99:.0f} ms"}</div><div class="lbl">Avg p99</div></div>
    <div class="card"><div class="val">{duration}s</div><div class="lbl">Duration</div></div>
  </div>

  <h2>RPS, Response Time & Error Rate</h2>
  <img src="{chart1_rel}" alt="Overview charts">
"""

if chart2_rel:
    html += f"""
  <h2>Request Distribution & Response Time Histogram</h2>
  <img src="{chart2_rel}" alt="Timestamp analysis">
"""

html += """
  <div class="footer">VideoSearcher Locust Load Test &mdash; auto-generated report</div>
</body>
</html>
"""

report_path = os.path.join(out_dir, 'report.html')
with open(report_path, 'w') as f:
    f.write(html)

print(f"\nReport is finished: {report_path}")
