#!/bin/bash
# Create IAM role for Lambda functions
set -e

ROLE_NAME="VideoSearcher-Lambda-Role-New"
REGION="YOUR-REGION"

echo "Creating IAM role: $ROLE_NAME"

# Create role with inline policy
ROLE_ARN=$(aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document '{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Service": "lambda.amazonaws.com"
    },
    "Action": "sts:AssumeRole"
  }]
}' \
    --query 'Role.Arn' \
    --output text 2>/dev/null || aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)

echo "Role ARN: $ROLE_ARN"

# Attach AWS managed policies
# AWSLambdaBasicExecutionRole: grants Lambda write access to CloudWatch Logs
echo "Attaching policies"
aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"

# AmazonS3FullAccess: grants Lambda full read/write access to S3
aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn "arn:aws:iam::aws:policy/AmazonS3FullAccess"

echo ""
echo "Waiting 10 seconds for role to propagate"
sleep 10

echo ""
echo "IAM role created successfully"
echo "Finished."
echo ""
echo "Role ARN: $ROLE_ARN"
echo ""
