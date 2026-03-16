#!/bin/bash
# Upload a Locust test to an EC2 instance, run it in headless mode, and download the results.
#
# Usage:
#   ./run-locust-on-ec2.sh -k <pem-file> -h <ec2-ip> [-b <s3-bucket>]
#
#   -k  path to the SSH PEM key file
#   -h  public IP or hostname of the EC2 instance
#   -b  S3 bucket to upload results to (optional)
set -e

# Defaults
REMOTE_DIR="/home/ec2-user"
EC2_USER="ec2-user"
S3_BUCKET=""

# Parse command-line options
while getopts "k:h:b:" opt; do
  case $opt in
    k) PEM_FILE="$OPTARG" ;;
    h) EC2_HOST="$OPTARG" ;;
    b) S3_BUCKET="$OPTARG" ;;
    *) echo "Usage: $0 -k <pem> -h <ec2-ip> [-b s3-bucket]"; exit 1 ;;
  esac
done

# Validate required arguments
if [ -z "$PEM_FILE" ] || [ -z "$EC2_HOST" ]; then
  echo "Error: -k (pem file) and -h (EC2 IP) are required."
  echo "Usage: $0 -k ~/.ssh/key.pem -h 1.2.3.4 [-b s3-bucket]"
  exit 1
fi

if [ ! -f "$PEM_FILE" ]; then
  echo "Error: PEM file not found: $PEM_FILE"
  exit 1
fi

SCRIPT_DIR="$(dirname "$0")"

# workloadProfile.csv is read by locustfile.py at startup to drive the
# non-homogeneous Poisson arrival process; the test cannot run without it
if [ ! -f "$SCRIPT_DIR/workloadProfile.csv" ]; then
  echo "Error: workloadProfile.csv not found in $SCRIPT_DIR"
  exit 1
fi

# SSH requires the key file to be owner-read-only
chmod 400 "$PEM_FILE"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
# Store all local outputs under a shared results/ directory next to the script
LOCAL_RESULTS_DIR="$SCRIPT_DIR/../results"
mkdir -p "$LOCAL_RESULTS_DIR"

# Reusable SSH and SCP command prefixes
SSH="ssh -i $PEM_FILE -o StrictHostKeyChecking=no ${EC2_USER}@${EC2_HOST}"
SCP="scp -i $PEM_FILE -o StrictHostKeyChecking=no"

echo ""
echo " VideoSearcher Locust - EC2 Test Run"
echo ""
echo " EC2        : ${EC2_HOST}"
echo " Timestamp  : ${TIMESTAMP}"
echo " S3 Bucket  : ${S3_BUCKET:-"(none, results will only be downloaded locally)"}"
echo ""

# Ensure Locust and its Python dependencies are installed on the remote instance
echo "Installing Locust on EC2"
$SSH 'bash -s' < "$SCRIPT_DIR/ec2-locust-setup.sh"

# Upload both the test script and the workload profile CSV that drives it
echo ""
echo " Uploading test files to EC2"
$SCP "$SCRIPT_DIR/locustfile.py" "${EC2_USER}@${EC2_HOST}:${REMOTE_DIR}/locustfile.py"
$SCP "$SCRIPT_DIR/workloadProfile.csv" "${EC2_USER}@${EC2_HOST}:${REMOTE_DIR}/workloadProfile.csv"

echo ""
echo " Starting Locust test (headless, trace-driven)"
echo "      Duration: approx. 3600s"
echo ""

# --users 1 and --spawn-rate 1 are intentional: locustfile.py schedules all
# requests itself via gevent.spawn_later based on the workload CSV, so only
# one logical user is needed to drive the entire arrival process
$SSH "
  cd ${REMOTE_DIR}
  locust \
    -f locustfile.py \
    --headless \
    --users 1 \
    --spawn-rate 1 \
    --csv locust-results-${TIMESTAMP} \
    2>&1
  echo ''
  echo 'Test complete.'
"

echo ""
echo "Downloading results locally"

LOCAL_PREFIX="${LOCAL_RESULTS_DIR}/locust-${TIMESTAMP}"

# Locust produces four CSV files; 2>/dev/null || true prevents failure if any
# file is missing (e.g. no failures occurred so failures.csv was not written)
$SCP "${EC2_USER}@${EC2_HOST}:${REMOTE_DIR}/locust-results-${TIMESTAMP}_stats.csv"         "${LOCAL_PREFIX}_stats.csv"         2>/dev/null || true
$SCP "${EC2_USER}@${EC2_HOST}:${REMOTE_DIR}/locust-results-${TIMESTAMP}_stats_history.csv" "${LOCAL_PREFIX}_stats_history.csv" 2>/dev/null || true
$SCP "${EC2_USER}@${EC2_HOST}:${REMOTE_DIR}/locust-results-${TIMESTAMP}_failures.csv"      "${LOCAL_PREFIX}_failures.csv"      2>/dev/null || true
# request_timestamps.csv is written by the on_test_stop hook in locustfile.py
$SCP "${EC2_USER}@${EC2_HOST}:${REMOTE_DIR}/request_timestamps.csv"                         "${LOCAL_PREFIX}_request_timestamps.csv" 2>/dev/null || true

# Optionally archive results to S3 for long-term storage or sharing
if [ -n "$S3_BUCKET" ]; then
  echo ""
  echo "Uploading results to S3: s3://${S3_BUCKET}/locust-results/${TIMESTAMP}/"
  aws s3 cp "${LOCAL_PREFIX}_stats.csv"              "s3://${S3_BUCKET}/locust-results/${TIMESTAMP}/stats.csv"              2>/dev/null || true
  aws s3 cp "${LOCAL_PREFIX}_stats_history.csv"      "s3://${S3_BUCKET}/locust-results/${TIMESTAMP}/stats_history.csv"      2>/dev/null || true
  aws s3 cp "${LOCAL_PREFIX}_failures.csv"           "s3://${S3_BUCKET}/locust-results/${TIMESTAMP}/failures.csv"           2>/dev/null || true
  aws s3 cp "${LOCAL_PREFIX}_request_timestamps.csv" "s3://${S3_BUCKET}/locust-results/${TIMESTAMP}/request_timestamps.csv" 2>/dev/null || true
  echo "S3 upload complete."
fi

# Generate HTML report from downloaded results; the script is skipped gracefully
# if matplotlib/pandas are not installed locally
echo ""
REPORT_DIR="${LOCAL_RESULTS_DIR}/locust-${TIMESTAMP}-report"
mkdir -p "$REPORT_DIR"
cp "${LOCAL_PREFIX}_stats_history.csv" "$REPORT_DIR/" 2>/dev/null || true
cp "${LOCAL_PREFIX}_request_timestamps.csv" "$REPORT_DIR/" 2>/dev/null || true

python3 "$SCRIPT_DIR/plot_results.py" \
  "$REPORT_DIR/$(basename ${LOCAL_PREFIX}_stats_history.csv)" \
  "$REPORT_DIR/$(basename ${LOCAL_PREFIX}_request_timestamps.csv)" \
  2>/dev/null || echo "(report generation skipped — install matplotlib/pandas locally)"

echo ""
echo " Finished"
echo " Stats      : ${LOCAL_PREFIX}_stats.csv"
echo " History    : ${LOCAL_PREFIX}_stats_history.csv"
echo " Timestamps : ${LOCAL_PREFIX}_request_timestamps.csv"
echo " HTML Report: ${REPORT_DIR}/report.html"
if [ -n "$S3_BUCKET" ]; then
  echo " S3         : s3://${S3_BUCKET}/locust-results/${TIMESTAMP}/"
fi
