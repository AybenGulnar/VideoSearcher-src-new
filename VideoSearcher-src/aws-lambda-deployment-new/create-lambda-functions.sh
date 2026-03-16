#!/bin/bash
# Create Lambda functions from Docker images

set -e

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="YOUR-REGION"
ECR_URL="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"

# Read role ARN from file
if [ ! -f lambda-role-arn.txt ]; then
    echo "Error: lambda-role-arn.txt not found"
    echo "Run ./create-lambda-role.sh first"
    exit 1
fi

ROLE_ARN=$(cat lambda-role-arn.txt)

echo "Role ARN: $ROLE_ARN"
echo ""

# Stage configurations function
get_config() {
    local stage=$1
    case "$stage" in
        ffmpeg-0)
            echo "300 2048"
            ;;
        librosa)
            echo "300 3008"
            ;;
        ffmpeg-1)
            echo "300 3008"
            ;;
        ffmpeg-2)
            echo "300 2048"
            ;;
        deepspeech)
            echo "900 3008"
            ;;
        ffmpeg-3)
            echo "300 2048"
            ;;
        object-detector)
            echo "300 3008"
            ;;
        *)
            echo "300 3008"
            ;;
    esac
}

STAGES=("ffmpeg-0" "librosa" "ffmpeg-1" "ffmpeg-2" "deepspeech" "ffmpeg-3" "object-detector")

for STAGE in "${STAGES[@]}"; do
    FUNCTION_NAME="videosearcher-${STAGE}-new"
    IMAGE_URI="$ECR_URL/videosearcher-$STAGE-new:latest"

    # config
    CONFIG=$(get_config "$STAGE")
    TIMEOUT=$(echo $CONFIG | cut -d' ' -f1)
    MEMORY=$(echo $CONFIG | cut -d' ' -f2)

    echo "Creating Lambda function: $FUNCTION_NAME"
    echo "  Image: $IMAGE_URI"
    echo "  Timeout: ${TIMEOUT}s, Memory: ${MEMORY}MB"

    # if function already exists
    if aws lambda get-function --function-name "$FUNCTION_NAME" --region "$REGION" >/dev/null 2>&1; then
        echo "  (already exists, skipping)"
    else
        aws lambda create-function \
            --function-name "$FUNCTION_NAME" \
            --package-type Image \
            --code ImageUri="$IMAGE_URI" \
            --role "$ROLE_ARN" \
            --timeout "$TIMEOUT" \
            --memory-size "$MEMORY" \
            --region "$REGION"

        aws lambda wait function-active --function-name "$FUNCTION_NAME" --region "$REGION"
        echo "Finished."
    fi
    echo ""
done

echo ""
echo "Functions created:"
for STAGE in "${STAGES[@]}"; do
    echo "  - videosearcher-${STAGE}-new"
done
echo ""
