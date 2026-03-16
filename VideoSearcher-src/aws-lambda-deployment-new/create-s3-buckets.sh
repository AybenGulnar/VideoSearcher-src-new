#!/bin/bash
# Create S3 buckets for input, temp, output and JMeter results
set -e

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="YOUR-REGION"

INPUT_BUCKET="videosearcher-input-new-${ACCOUNT_ID}"
TEMP_BUCKET="videosearcher-temp-new-${ACCOUNT_ID}"
OUTPUT_BUCKET="videosearcher-output-new-${ACCOUNT_ID}"
JMETER_BUCKET="videosearcher-jmeter-results-new-${ACCOUNT_ID}"
echo ""

# Create input bucket
echo "Creating: $INPUT_BUCKET"
aws s3api create-bucket \
    --bucket "$INPUT_BUCKET" \
    --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION" \
    2>/dev/null || echo "  (already exists)"

# Create temp bucket
echo "Creating: $TEMP_BUCKET"
aws s3api create-bucket \
    --bucket "$TEMP_BUCKET" \
    --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION" \
    2>/dev/null || echo "  (already exists)"

# Create output bucket
echo "Creating: $OUTPUT_BUCKET"
aws s3api create-bucket \
    --bucket "$OUTPUT_BUCKET" \
    --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION" \
    2>/dev/null || echo "  (already exists)"

# Lifecycle policy to temp bucket : files will be deleted after 7 days
echo ""
# Create jmeter results bucket
echo "Creating: $JMETER_BUCKET"
aws s3api create-bucket \
    --bucket "$JMETER_BUCKET" \
    --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION" \
    2>/dev/null || echo "  (already exists)"

echo ""
echo "Adding lifecycle policy to temp bucket"
aws s3api put-bucket-lifecycle-configuration \
    --bucket "$TEMP_BUCKET" \
    --lifecycle-configuration '{
  "Rules": [{
    "ID": "DeleteOldTempFiles",
    "Status": "Enabled",
    "Filter": {"Prefix": ""},
    "Expiration": {"Days": 7}
  }]
}'

echo ""
echo "Finished"
echo ""
echo "Buckets:"
echo "  Input:   $INPUT_BUCKET"
echo "  Temp:    $TEMP_BUCKET"
echo "  Output:  $OUTPUT_BUCKET"
echo "  JMeter:  $JMETER_BUCKET"
echo ""

# Save bucket names for later use
echo "$INPUT_BUCKET" > input-bucket.txt
echo "$TEMP_BUCKET" > temp-bucket.txt
echo "$OUTPUT_BUCKET" > output-bucket.txt
echo "$JMETER_BUCKET" > jmeter-bucket.txt
