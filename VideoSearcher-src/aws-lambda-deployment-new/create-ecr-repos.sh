#!/bin/bash
# Create new ECR repositories for all stages
set -e

REGION="YOUR-REGION"

STAGES=("ffmpeg-0" "librosa" "ffmpeg-1" "ffmpeg-2" "deepspeech" "ffmpeg-3" "object-detector")

echo "Creating ECR repositories in $REGION"
echo ""

for STAGE in "${STAGES[@]}"; do
    REPO_NAME="videosearcher-$STAGE-new"
    echo "Creating repository: $REPO_NAME"

    aws ecr create-repository \
        --repository-name "$REPO_NAME" \
        --region "$REGION" \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256 \
        2>/dev/null || echo "  (already exists)"
done

echo ""
echo "ECR repositories created"

