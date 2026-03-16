#!/bin/bash

set -e

# Configuration
REGION="YOUR-REGION"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
API_NAME="videosearcher-api"
STAGE_NAME="prod"
LAMBDA_NAME="videosearcher-api-trigger"
ROLE_NAME="videosearcher-api-trigger-role"

# Bucket names
INPUT_BUCKET="videosearcher-input-new"
TEMP_BUCKET="videosearcher-temp-new"
OUTPUT_BUCKET="videosearcher-output-new"

# State Machine ARN
STATE_MACHINE_ARN="arn:aws:states:${REGION}:${ACCOUNT_ID}:stateMachine:videosearcher-pipeline-new"

echo "VideoSearcher API Gateway Setup"
echo "Region: $REGION"
echo "Account: $ACCOUNT_ID"
echo ""

# Use local temp directory
TEMP_DIR="./temp-api-setup"
mkdir -p "$TEMP_DIR"

echo "Creating IAM role for API trigger Lambda"

# Trust policy
cat > "$TEMP_DIR/trust-policy.json" << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create role
aws iam create-role \
    --role-name $ROLE_NAME \
    --assume-role-policy-document "file://$TEMP_DIR/trust-policy.json" \
    2>/dev/null || echo "  Role already exists"

# Policy for Lambda
cat > "$TEMP_DIR/lambda-policy.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "states:StartExecution"
      ],
      "Resource": "${STATE_MACHINE_ARN}"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:HeadObject",
        "s3:GetObject"
      ],
      "Resource": "arn:aws:s3:::${INPUT_BUCKET}/*"
    }
  ]
}
EOF

# Attach inline policy
aws iam put-role-policy \
    --role-name $ROLE_NAME \
    --policy-name "api-trigger-policy" \
    --policy-document "file://$TEMP_DIR/lambda-policy.json"

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
echo "  Role ARN: $ROLE_ARN"

# Wait for role to propagate
echo "  Waiting for IAM role to propagate"
sleep 10

echo ""
echo "Creating API trigger Lambda function"

# Package Lambda code
if command -v zip &> /dev/null; then
    cd api-trigger-lambda
    zip -r "../$TEMP_DIR/api-trigger-lambda.zip" lambda_function.py
    cd ..
else
    powershell -Command "Compress-Archive -Path 'api-trigger-lambda/lambda_function.py' -DestinationPath '$TEMP_DIR/api-trigger-lambda.zip' -Force"
fi

# Delete existing function if it exists
aws lambda delete-function --function-name $LAMBDA_NAME 2>/dev/null || true

# Create Lambda function
aws lambda create-function \
    --function-name $LAMBDA_NAME \
    --runtime python3.12 \
    --role $ROLE_ARN \
    --handler lambda_function.lambda_handler \
    --zip-file "fileb://$TEMP_DIR/api-trigger-lambda.zip" \
    --timeout 30 \
    --memory-size 256 \
    --environment "Variables={STATE_MACHINE_ARN=${STATE_MACHINE_ARN},INPUT_BUCKET=${INPUT_BUCKET},TEMP_BUCKET=${TEMP_BUCKET},OUTPUT_BUCKET=${OUTPUT_BUCKET}}"

LAMBDA_ARN="arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:${LAMBDA_NAME}"
echo "  Lambda ARN: $LAMBDA_ARN"
echo ""
echo "Creating API Gateway REST API"

# Delete existing API if it exists
EXISTING_API_ID=$(aws apigateway get-rest-apis --query "items[?name=='${API_NAME}'].id" --output text)
if [ -n "$EXISTING_API_ID" ] && [ "$EXISTING_API_ID" != "None" ]; then
    echo "  Deleting existing API: $EXISTING_API_ID"
    aws apigateway delete-rest-api --rest-api-id $EXISTING_API_ID
    sleep 5
fi

# Create new API
API_ID=$(aws apigateway create-rest-api \
    --name $API_NAME \
    --description "VideoSearcher HTTP endpoint for load testing" \
    --endpoint-configuration types=REGIONAL \
    --query 'id' --output text)

echo "  API ID: $API_ID"

# Get root resource ID
ROOT_ID=$(aws apigateway get-resources \
    --rest-api-id $API_ID \
    --query 'items[?path==`/`].id' --output text)

echo "  Root Resource ID: $ROOT_ID"
echo "Creating /process endpoint"

# Create /process resource
RESOURCE_ID=$(aws apigateway create-resource \
    --rest-api-id $API_ID \
    --parent-id $ROOT_ID \
    --path-part "process" \
    --query 'id' --output text)

echo "  Resource ID: $RESOURCE_ID"

# Create POST method
aws apigateway put-method \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method POST \
    --authorization-type NONE \
    --request-parameters "method.request.querystring.video=false"

echo "  POST method created"

# Create Lambda integration
aws apigateway put-integration \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method POST \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri "arn:aws:apigateway:${REGION}:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations"

echo "  Lambda integration configured"

# Create method response
aws apigateway put-method-response \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method POST \
    --status-code 200 \
    --response-models '{"application/json": "Empty"}'

echo ""
echo "Granting API Gateway permission to invoke Lambda"

aws lambda add-permission \
    --function-name $LAMBDA_NAME \
    --statement-id apigateway-invoke \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:${REGION}:${ACCOUNT_ID}:${API_ID}/*/POST/process" \
    2>/dev/null || echo "  Permission already exists"

echo ""
echo "Deploying API to '$STAGE_NAME' stage"

aws apigateway create-deployment \
    --rest-api-id $API_ID \
    --stage-name $STAGE_NAME \
    --description "Initial deployment"

ENDPOINT_URL="https://${API_ID}.execute-api.${REGION}.amazonaws.com/${STAGE_NAME}/process"

# Save endpoint info to file
cat > api-endpoint.txt << EOF
ENDPOINT_URL=${ENDPOINT_URL}
API_ID=${API_ID}
HOST=${API_ID}.execute-api.${REGION}.amazonaws.com
PORT=443
PATH=/${STAGE_NAME}/process
METHOD=POST
EOF

echo "Endpoint info saved to: api-endpoint.txt"

# Cleanup temp files
rm -rf "$TEMP_DIR"
