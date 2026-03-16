#!/bin/bash
# Create Step Functions state machine and IAM role
set -e

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="YOUR-REGION"

ROLE_NAME="videosearcher-stepfunctions-role-new"
STATE_MACHINE_NAME="videosearcher-pipeline-new"

echo "Creating Step Functions IAM role"

# Create trust policy allowing Step Functions to assume this role
cat > stepfunctions-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "states.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create the role
aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document file://stepfunctions-trust-policy.json \
    2>/dev/null || echo "Role already exists, continuing"

# Create policy allowing Step Functions to invoke Lambda functions and write execution logs
cat > stepfunctions-lambda-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "lambda:InvokeFunction"
      ],
      "Resource": [
        "arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:videosearcher-*-new"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogDelivery",
        "logs:GetLogDelivery",
        "logs:UpdateLogDelivery",
        "logs:DeleteLogDelivery",
        "logs:ListLogDeliveries",
        "logs:PutResourcePolicy",
        "logs:DescribeResourcePolicies",
        "logs:DescribeLogGroups"
      ],
      "Resource": "*"
    }
  ]
}
EOF

# Attach the inline policy to the role
aws iam put-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-name "StepFunctionsLambdaPolicy" \
    --policy-document file://stepfunctions-lambda-policy.json

echo "Waiting for role to propagate"
sleep 10

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

echo ""
echo "Creating Step Functions state machine"

# Create state machine
aws stepfunctions create-state-machine \
    --name "$STATE_MACHINE_NAME" \
    --definition file://step-functions-definition.json \
    --role-arn "$ROLE_ARN" \
    --region "$REGION" \
    2>/dev/null || echo "State machine already exists, updating"

# If already exists, update it
aws stepfunctions update-state-machine \
    --state-machine-arn "arn:aws:states:${REGION}:${ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}" \
    --definition file://step-functions-definition.json \
    --role-arn "$ROLE_ARN" \
    2>/dev/null || true

STATE_MACHINE_ARN="arn:aws:states:${REGION}:${ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}"

# Cleanup temp files
rm -f stepfunctions-trust-policy.json stepfunctions-lambda-policy.json

echo ""
echo "state machine created"
echo ""
echo "State Machine ARN: $STATE_MACHINE_ARN"
echo ""
echo "To run the pipeline, use:"
echo ""
echo "aws stepfunctions start-execution \\"
echo "    --state-machine-arn $STATE_MACHINE_ARN \\"
echo "    --input '{\"input_bucket\": \"YOUR-INPUT-BUCKET\", \"input_key\": \"video.mp4\", \"temp_bucket\": \"YOUR-TEMP-BUCKET\", \"output_bucket\": \"YOUR-OUTPUT-BUCKET\"}'"
echo ""

# Save state machine ARN
echo "$STATE_MACHINE_ARN" > state-machine-arn.txt
echo "State machine ARN saved to: state-machine-arn.txt"
