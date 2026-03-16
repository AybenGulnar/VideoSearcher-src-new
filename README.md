# VideoSearcher

A serverless video analysis pipeline deployed on AWS Lambda. Given a video file, the pipeline automatically extracts audio, detects speech segments, transcribes speech to text, extracts key frames, and runs object detection on each frame — producing annotated results stored in S3.

---

## How It Works

```
Input Video (S3)
      │
      ▼
Stage 1 ─ ffmpeg-0        Extract full audio track
      │
      ▼
Stage 2 ─ librosa         Detect silence → find natural cut points
      │
      ▼
Stage 3 ─ ffmpeg-1        Segment video into clips at cut points
      │
      ├──────────────────────────────────────┐
      ▼  (Map — parallel per clip)           ▼
Stage 4 ─ ffmpeg-2        Per-clip audio extraction
Stage 5 ─ deepspeech      Speech-to-text transcription
Stage 6 ─ ffmpeg-3        Key frame extraction
Stage 7 ─ object-detector YOLOv4 object detection on frames
      │
      ▼
Results (S3) — annotated frames + transcripts per clip
```

Each stage runs as a containerized AWS Lambda function. AWS Step Functions orchestrates the execution: stages 1–3 run sequentially, then each video clip is processed in parallel through stages 4–7 (Map state, `MaxConcurrency: 2`).

---

## Technology Stack

| Layer | Technology |
|-------|-----------|
| Compute | AWS Lambda (container images, `linux/amd64`) |
| Orchestration | AWS Step Functions |
| Storage | Amazon S3 |
| Container Registry | Amazon ECR |
| HTTP Trigger | API Gateway → Lambda → Step Functions |
| Video / Audio | FFmpeg (static binary) |
| Silence Detection | librosa + numba |
| Speech-to-Text | Mozilla DeepSpeech 0.9.3 |
| Object Detection | YOLOv4 (ONNX Runtime) |
| Load Testing | Apache JMeter 5.6.3, Locust |

---

## Repository Structure

```
VideoSearcher-src/
│
├── aws-lambda-deployment-new/
│   ├── ffmpeg-0/              # Stage 1 — audio extraction
│   ├── librosa/               # Stage 2 — silence detection
│   ├── ffmpeg-1/              # Stage 3 — video segmentation
│   ├── ffmpeg-2/              # Stage 4 — per-clip audio
│   ├── deepspeech/            # Stage 5 — speech-to-text
│   ├── ffmpeg-3/              # Stage 6 — frame extraction
│   ├── object-detector/       # Stage 7 — YOLOv4 inference
│   ├── api-trigger-lambda/    # HTTP entry point (API Gateway → Step Functions)
│   ├── step-functions-definition.json
│   ├── build-and-push.sh      # Build Docker images and push to ECR
│   ├── create-ecr-repos.sh
│   ├── create-lambda-role.sh
│   ├── create-s3-buckets.sh
│   ├── create-lambda-functions.sh
│   ├── create-step-functions.sh
│   └── create-api-gateway.sh
│
├── jmeter-tests/
│   ├── videosearcher-http-test.jmx           # 6-phase stepped load test
│   ├── videosearcher-http-test-constant.jmx  # Constant-rate test
│   ├── videosearcher-simple-5users.jmx       # Smoke test
│   ├── ec2-jmeter-setup.sh                   # JMeter installer for EC2
│   └── run-test-on-ec2.sh                    # Run test remotely on EC2
│
├── locust-tests/
│   ├── locustfile.py          # Trace-driven load generator (Poisson process)
│   ├── workloadProfile.csv    # Per-second RPS trace used by locustfile.py
│   ├── plot_results.py        # Generate charts + HTML report from results
│   ├── ec2-locust-setup.sh    # Locust installer for EC2
│   └── run-locust-on-ec2.sh   # Run test remotely on EC2
│
├── DEPLOYMENT-SUMMARY.md      # Full deployment + load testing guide
└── README.md
```

---

## Prerequisites

- **AWS CLI** configured (`aws configure`) with permissions for: IAM, S3, ECR, Lambda, Step Functions, API Gateway
- **Docker** with BuildKit and `linux/amd64` platform support (use Docker Desktop on Apple Silicon)
- **EC2 instance** (Amazon Linux 2023 or Ubuntu) with SSH access — needed for running JMeter/Locust tests

---

## Deployment

> Full step-by-step instructions with explanations are in [DEPLOYMENT-SUMMARY.md](DEPLOYMENT-SUMMARY.md).

All deployment scripts are in `aws-lambda-deployment-new/`. Before running, set your AWS region in each script by replacing `YOUR-REGION` with your actual region (e.g. `eu-west-1`).

Run the scripts in this order:

```bash
cd aws-lambda-deployment-new

# 1. Create S3 buckets (input, temp, output, jmeter-results)
bash create-s3-buckets.sh

# 2. Create the Lambda IAM role
bash create-lambda-role.sh

# 3. Create ECR repositories (one per stage)
bash create-ecr-repos.sh

# 4. Build Docker images and push to ECR  (~30–60 min on first run)
bash build-and-push.sh

# 5. Create Lambda functions from ECR images
bash create-lambda-functions.sh

# 6. Create the Step Functions state machine
bash create-step-functions.sh

# 7. Create the API Gateway HTTP endpoint
bash create-api-gateway.sh
```

Each script is idempotent — safe to re-run; existing resources are skipped.

---

## Running the Pipeline

Upload a video to the input S3 bucket, then trigger via the API endpoint:

```bash
# Upload a video
aws s3 cp video.mp4 s3://videosearcher-input-new-<account-id>/video.mp4

# Trigger via HTTP (endpoint URL is printed by create-api-gateway.sh)
curl -X POST "https://<api-id>.execute-api.<region>.amazonaws.com/prod/process?video=video.mp4"
```

Or trigger directly through Step Functions:

```bash
aws stepfunctions start-execution \
  --state-machine-arn arn:aws:states:<region>:<account-id>:stateMachine:videosearcher-pipeline-new \
  --input '{
    "input_bucket":  "videosearcher-input-new-<account-id>",
    "input_key":     "video.mp4",
    "temp_bucket":   "videosearcher-temp-new-<account-id>",
    "output_bucket": "videosearcher-output-new-<account-id>"
  }'
```

Monitor progress in the AWS Console under **Step Functions → videosearcher-pipeline-new → Executions**.

Results are written to the output bucket under `<execution-id>/results/`.

---

## Load Testing

### JMeter — Stepped Load Pattern

Runs a 6-phase test (warm-up → ramp-up → peak → ramp-down) with exponential think time.
JMeter is installed automatically on the EC2 instance by `ec2-jmeter-setup.sh`.

```bash
cd jmeter-tests

# Full test — 600 s per phase (~61 min total)
./run-test-on-ec2.sh -k ~/.ssh/key.pem -h <ec2-ip>

# Quick test — 60 s per phase (~7 min), upload results to S3
./run-test-on-ec2.sh -k ~/.ssh/key.pem -h <ec2-ip> -p 60 -b <s3-bucket>
```

Before running, set your API Gateway host in the JMX file:
```xml
<stringProp name="HTTPSampler.domain">YOUR-API-ID.execute-api.YOUR-REGION.amazonaws.com</stringProp>
```

Output: raw `.jtl` results + an auto-generated HTML dashboard, downloaded to `results/`.

### Locust — Trace-Driven Poisson Load

Replays a real-world RPS trace from `workloadProfile.csv` using the Lewis-Shedler thinning algorithm to generate a non-homogeneous Poisson arrival process.

```bash
cd locust-tests

# Run test, download results locally
./run-locust-on-ec2.sh -k ~/.ssh/key.pem -h <ec2-ip>

# With S3 result upload
./run-locust-on-ec2.sh -k ~/.ssh/key.pem -h <ec2-ip> -b <s3-bucket>
```

Before running, set your API Gateway host in `locustfile.py`:
```python
HOST = "YOUR-API-ID.execute-api.YOUR-REGION.amazonaws.com"
```

Generate an HTML report from downloaded results:
```bash
python3 plot_results.py \
  results/locust-<timestamp>_stats_history.csv \
  results/locust-<timestamp>_request_timestamps.csv
```

---

## Lambda Configuration

| Stage | Function Name | Timeout | Memory |
|-------|--------------|---------|--------|
| 1 — Audio Extraction | `videosearcher-ffmpeg-0-new` | 300 s | 2048 MB |
| 2 — Silence Detection | `videosearcher-librosa-new` | 300 s | 3008 MB |
| 3 — Video Segmentation | `videosearcher-ffmpeg-1-new` | 300 s | 3008 MB |
| 4 — Clip Audio | `videosearcher-ffmpeg-2-new` | 300 s | 2048 MB |
| 5 — Transcription | `videosearcher-deepspeech-new` | 900 s | 3008 MB |
| 6 — Frame Extraction | `videosearcher-ffmpeg-3-new` | 300 s | 2048 MB |
| 7 — Object Detection | `videosearcher-object-detector-new` | 300 s | 3008 MB |

## Quick Test Commands

[Test Commands](testcommands.md) contains ready-to-run commands for the most common testing scenarios: opening SSH access to your EC2 instance, running Locust and JMeter tests both remotely (EC2) and locally. Useful as a quick reference after deployment.

---

## Deployment Summary

[DEPLOYMENT-SUMMARY.md](DEPLOYMENT-SUMMARY.md) contains a detailed, step-by-step walkthrough of the entire deployment process — including infrastructure setup, Docker image builds, Lambda configuration, Step Functions orchestration, load testing, and cost/performance observations.
---

## Presentation

A general overview presentation of this project is available at the end of this repository.
