#!/bin/bash

set -e

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="YOUR-REGION"
ECR_URL="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"

export DOCKER_BUILDKIT=1

# Login to ECR
echo "Logging in to ECR"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ECR_URL"
echo ""

STAGES=("ffmpeg-0" "librosa" "ffmpeg-1" "ffmpeg-2" "deepspeech" "ffmpeg-3" "object-detector")

for STAGE in "${STAGES[@]}"; do

    cd "$STAGE"

    LOCAL_IMAGE="videosearcher-$STAGE-new:latest"
    ECR_IMAGE="$ECR_URL/videosearcher-$STAGE-new:latest"

    echo "Building $LOCAL_IMAGE"
    # Build from current directory
    docker buildx build \
        --provenance=false \
        --sbom=false \
        --platform linux/amd64 \
        --tag "$LOCAL_IMAGE" \
        --load \
        .

    echo ""
    echo "Tagging $LOCAL_IMAGE as $ECR_IMAGE"
    docker tag "$LOCAL_IMAGE" "$ECR_IMAGE"

    echo ""
    echo "Pushing $ECR_IMAGE to ECR"
    docker push "$ECR_IMAGE"

    echo ""
    echo "$STAGE completed"
    echo ""

    cd ..
done

echo "All images built and pushed successfully"
echo ""
