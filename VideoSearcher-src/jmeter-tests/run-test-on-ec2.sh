#!/bin/bash
# Upload a JMX test plan to an EC2 instance, run it with JMeter, and download the results.
#
# Usage:
#   ./run-test-on-ec2.sh -k <pem-file> -h <ec2-ip> [-p <phaseduration>] [-t <test.jmx>] [-b <s3-bucket>]
#
#   -k  path to the SSH PEM key file
#   -h  public IP or hostname of the EC2 instance
#   -p  duration of each load phase in seconds (default: 600)
#   -t  path to the JMX test plan (default: videosearcher-http-test.jmx)
#   -b  S3 bucket to upload results to (optional)
set -e

# Defaults
PHASE_DURATION=600
JMX_FILE="$(dirname "$0")/videosearcher-http-test.jmx"
JMETER_VERSION="5.6.3"
REMOTE_DIR="/home/ec2-user"
EC2_USER="ec2-user"
S3_BUCKET=""

# Parse command-line options
while getopts "k:h:p:t:b:" opt; do
  case $opt in
    k) PEM_FILE="$OPTARG" ;;
    h) EC2_HOST="$OPTARG" ;;
    p) PHASE_DURATION="$OPTARG" ;;
    t) JMX_FILE="$OPTARG" ;;
    b) S3_BUCKET="$OPTARG" ;;
    *) echo "Usage: $0 -k <pem> -h <ec2-ip> [-p phaseduration] [-t test.jmx] [-b s3-bucket]"; exit 1 ;;
  esac
done

# Validate required arguments
if [ -z "$PEM_FILE" ] || [ -z "$EC2_HOST" ]; then
  echo "Error: -k (pem file) and -h (EC2 IP) are required."
  echo "Usage: $0 -k ~/.ssh/key.pem -h 1.2.3.4 [-p 60] [-t test.jmx] [-b s3-bucket]"
  exit 1
fi

if [ ! -f "$PEM_FILE" ]; then
  echo "Error: PEM file not found: $PEM_FILE"
  exit 1
fi

if [ ! -f "$JMX_FILE" ]; then
  echo "Error: JMX file not found: $JMX_FILE"
  exit 1
fi

# SSH requires the key file to be owner-read-only
chmod 400 "$PEM_FILE"

JMX_NAME="$(basename "$JMX_FILE")"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REMOTE_RESULT_CSV="results-${TIMESTAMP}.jtl"
REMOTE_REPORT_DIR="report-${TIMESTAMP}"
# Store all local outputs under a shared results/ directory next to the script
LOCAL_RESULTS_DIR="$(dirname "$0")/../results"
mkdir -p "$LOCAL_RESULTS_DIR"

# Reusable SSH and SCP command prefixes
SSH="ssh -i $PEM_FILE -o StrictHostKeyChecking=no ${EC2_USER}@${EC2_HOST}"
SCP="scp -i $PEM_FILE -o StrictHostKeyChecking=no"

# Ensure JMeter is installed on the remote instance before running the test
echo "Installing JMeter on EC2"
$SSH 'bash -s' < "$(dirname "$0")/ec2-jmeter-setup.sh"

echo ""
echo "Uploading JMX file to EC2"
$SCP "$JMX_FILE" "${EC2_USER}@${EC2_HOST}:${REMOTE_DIR}/${JMX_NAME}"

echo ""
echo "Starting test (phaseduration=${PHASE_DURATION}s)"
# Total duration = 6 phases × phaseduration; +1 minute accounts for ramp-up overhead
echo "      Estimated duration: $((PHASE_DURATION * 6 / 60 + 1)) minutes"
echo ""

# Run JMeter in non-GUI mode; -e and -o generate an HTML report alongside the raw CSV
$SSH "
  JMETER_BIN=\$HOME/apache-jmeter-${JMETER_VERSION}/bin/jmeter
  cd ${REMOTE_DIR}

  \$JMETER_BIN -n \
    -t ${JMX_NAME} \
    -l ${REMOTE_RESULT_CSV} \
    -e -o ${REMOTE_REPORT_DIR} \
    -Jphaseduration=${PHASE_DURATION} \
    -Djmeter.save.saveservice.output_format=csv \
    2>&1

  echo ''
  echo 'Finished.'
"

echo ""

LOCAL_CSV="${LOCAL_RESULTS_DIR}/ec2-${TIMESTAMP}-raw.jtl"
LOCAL_REPORT="${LOCAL_RESULTS_DIR}/ec2-${TIMESTAMP}-report"

# Download the raw JTL results and the pre-generated HTML report
$SCP "${EC2_USER}@${EC2_HOST}:${REMOTE_DIR}/${REMOTE_RESULT_CSV}" "$LOCAL_CSV"
$SCP -r "${EC2_USER}@${EC2_HOST}:${REMOTE_DIR}/${REMOTE_REPORT_DIR}" "$LOCAL_REPORT"

# Optionally archive results to S3 for long-term storage or sharing
if [ -n "$S3_BUCKET" ]; then
  echo ""
  echo "Uploading results to S3: s3://${S3_BUCKET}/jmeter-results/${TIMESTAMP}/"
  aws s3 cp "$LOCAL_CSV" "s3://${S3_BUCKET}/jmeter-results/${TIMESTAMP}/raw.jtl"
  aws s3 cp --recursive "$LOCAL_REPORT" "s3://${S3_BUCKET}/jmeter-results/${TIMESTAMP}/report/"
  echo "completed."
fi

echo ""
echo " Finished."
echo " CSV Results : $LOCAL_CSV"
echo " HTML Report : $LOCAL_REPORT/index.html"
if [ -n "$S3_BUCKET" ]; then
  echo " S3 CSV      : s3://${S3_BUCKET}/jmeter-results/${TIMESTAMP}/raw.jtl"
  echo " S3 Report   : s3://${S3_BUCKET}/jmeter-results/${TIMESTAMP}/report/index.html"
fi
echo ""
