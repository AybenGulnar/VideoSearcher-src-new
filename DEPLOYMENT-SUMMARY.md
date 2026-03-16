# VideoSearcher AWS Lambda Deployment - Complete Guide

**A Comprehensive Guide to Deploying a 7-Stage Video Processing Pipeline to AWS Lambda**

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture](#2-architecture)
3. [Folder Structure](#3-folder-structure)
4. [Technical Challenges & Solutions](#4-technical-challenges--solutions)
5. [Deployment Steps](#5-deployment-steps)
6. [Running the Pipeline](#6-running-the-pipeline)
7. [Viewing Results](#7-viewing-results)
8. [Cost & Cleanup](#8-cost--cleanup)
---

## 1. Project Overview

### 1.1 What is VideoSearcher?

A 7-stage video processing pipeline that:
1. Extracts audio from video
2. Detects silence/speech segments
3. Splits video into clips based on speech
4. Compresses each clip
5. Transcribes speech to text (DeepSpeech)
6. Extracts frames from video
7. Detects objects in frames (YOLOv4)

**Result:** Searchable video content with transcripts and annotated frames

### 1.2 Technology Stack

| Component | Technology |
|-----------|------------|
| Compute | AWS Lambda (Container Images) |
| Orchestration | AWS Step Functions |
| Storage | Amazon S3 |
| Container Registry | Amazon ECR |
| Video Processing | FFmpeg |
| Audio Analysis | librosa |
| Speech-to-Text | Mozilla DeepSpeech |
| Object Detection | YOLOv4 (ONNX Runtime) |

### 1.3 Key Constraints

- **Lambda Memory Limit:** 3008 MB (default account limit)
- **Lambda Timeout:** 15 minutes max
- **Container Image Size:** 10 GB max
- **Writable Storage:** `/tmp` only (up to 10 GB)

---

## 2. Architecture

### 2.1 Pipeline Flow

```
Input Video (.mp4)
       │
       ▼
┌─────────────────┐
│ Stage 1: ffmpeg-0│  Extract audio.wav + video.mp4
└────────┬────────┘
         ▼
┌─────────────────┐
│ Stage 2: librosa │  Detect silence → timestamps.txt
└────────┬────────┘
         ▼
┌─────────────────┐
│ Stage 3: ffmpeg-1│  Split video → clip_0.mp4, clip_1.mp4, ...
└────────┬────────┘
         │
    ┌────┴────┬─────────┬─────────┐
    ▼         ▼         ▼         ▼
┌───────┐ ┌───────┐ ┌───────┐ ┌───────┐
│clip_0 │ │clip_1 │ │clip_2 │ │clip_N │  (Parallel Processing)
└───┬───┘ └───┬───┘ └───┬───┘ └───┬───┘
    │         │         │         │
    ▼         ▼         ▼         ▼
┌─────────────────────────────────────┐
│ Stage 4: ffmpeg-2 (Compression)     │
│ Stage 5: deepspeech (Transcription) │
│ Stage 6: ffmpeg-3 (Frame Extract)   │
│ Stage 7: object-detector (YOLO)     │
└─────────────────────────────────────┘
         │
         ▼
    Output Results
    (Annotated frames + Transcripts)
```

### 2.2 AWS Resources Created

| Resource | Name | Purpose |
|----------|------|---------|
| ECR Repos (7) | `videosearcher-{stage}-new` | Store Docker images |
| Lambda Functions (7) | `videosearcher-{stage}-new` | Run processing stages |
| S3 Buckets (3) | `videosearcher-{input/temp/output}-new-{account-id}` | Store data |
| Step Functions | `videosearcher-pipeline-new` | Orchestrate workflow |
| IAM Roles (2) | Lambda + Step Functions execution roles | Permissions |

---

## 3. Folder Structure

```
aws-lambda-deployment-new/
│
├── ffmpeg-0/                    # Stage 1: Audio Extraction
│   ├── Dockerfile
│   ├── lambda_handler.py
│   ├── pipeline_main.py         # Original instructor code
│   ├── requirements.txt
│   └── aisprint/                # Minimal AI-SPRINT stubs
│
├── librosa/                     # Stage 2: Silence Detection
│   ├── Dockerfile               # Includes libsndfile compilation
│   ├── lambda_handler.py
│   ├── pipeline_main.py
│   ├── requirements.txt
│   └── aisprint/
│
├── ffmpeg-1/                    # Stage 3: Video Segmentation
│   ├── Dockerfile
│   ├── lambda_handler.py
│   ├── pipeline_main.py
│   ├── requirements.txt
│   └── aisprint/
│
├── ffmpeg-2/                    # Stage 4: Compression
│   ├── Dockerfile
│   ├── lambda_handler.py
│   ├── pipeline_main.py
│   ├── requirements.txt
│   └── aisprint/
│
├── deepspeech/                  # Stage 5: Transcription (~1.9GB image)
│   ├── Dockerfile
│   ├── lambda_handler.py        
│   ├── pipeline_main.py         
│   ├── requirements.txt
│   ├── models/                  # DeepSpeech model files (1.1GB)
│   │   ├── deepspeech-0.9.3-models.pbmm
│   │   └── deepspeech-0.9.3-models.scorer
│   └── aisprint/
│
├── ffmpeg-3/                    # Stage 6: Frame Extraction
│   ├── Dockerfile
│   ├── lambda_handler.py        
│   ├── pipeline_main.py
│   ├── requirements.txt
│   └── aisprint/
│
├── object-detector/             # Stage 7: Object Detection (~1.5GB image)
│   ├── Dockerfile               
│   ├── lambda_handler.py       
│   ├── pipeline_main.py
│   ├── postprocess.py
│   ├── requirements.txt
│   ├── onnx/
│   │   ├── yolov4.onnx          # YOLO model (246MB)
│   │   └── coco.names
│   └── aisprint/
│       ├── __init__.py
│       ├── annotations/
│       └── onnx_inference.py    # Custom ONNX inference wrapper
│
├── api-trigger-lambda/          # HTTP trigger Lambda for JMeter
│   └── lambda_function.py       # Starts Step Functions via HTTP POST
│
├── build-and-push.sh            # Build all images & push to ECR
├── rebuild-fixed-stages.sh      # Rebuild only the 3 fixed stages
├── create-ecr-repos.sh          # Create ECR repositories
├── create-lambda-role.sh        # Create Lambda IAM role
├── create-lambda-functions.sh   # Create all Lambda functions
├── create-s3-buckets.sh         # Create S3 buckets
├── create-step-functions.sh     # Create Step Functions state machine
├── create-api-gateway.sh        # Create API Gateway + trigger Lambda
├── test-api-endpoint.sh         # Test the HTTP endpoint
├── api-endpoint.txt             # Stores endpoint URL (auto-generated)
├── run-pipeline.sh              # Run pipeline with test video
├── step-functions-definition.json  # State machine definition
└── README.md

jmeter-tests/
├── videosearcher-http-test.jmx  # JMeter HTTP test plan (recommended)
├── run-http-load-test.sh        # HTTP-based load testing script
├── videosearcher-load-test.jmx  # JMeter AWS CLI test plan (legacy)
├── run-load-test.sh             # CLI load testing (legacy)
├── JMETER-GUIDE.md              # Setup instructions
├── README.md                    # Load testing documentation
└── results/                     # Test results
```

---

## 4. Technical Challenges & Solutions

### 4.1 AI-SPRINT Framework Not Available

**Problem:** Original code imports `from aisprint.annotations import annotation`

**Solution:** Created minimal stub modules (~50KB) instead of full framework (~1.67GB)

```python
# aisprint/annotations.py
def annotation(config):
    def decorator(func):
        return func  # Just return function unchanged
    return decorator
```

### 4.2 librosa + soxr Compilation Failure

**Problem:** soxr requires C++17, Amazon Linux 2 has old GCC

**Solution:** Use pre-built wheel with `--only-binary`:
```dockerfile
RUN pip install --no-cache-dir soxr==0.3.7 --only-binary=:all:
```

### 4.3 DeepSpeech Model Path

**Problem:** Models not found when running in Lambda

**Solution:** Added `models/` prefix to paths in pipeline_main.py:
```python
# LAMBDA DEPLOYMENT FIX: Add 'models/' prefix
model = "models/deepspeech-0.9.3-models.pbmm"
scorer = "models/deepspeech-0.9.3-models.scorer"
```

## 5. Deployment Steps

### 5.1 Prerequisites

- Docker Desktop installed and running
- AWS CLI configured (`aws configure`)
- Git Bash (Windows) or Terminal (macOS/Linux)

### 5.2 Deployment Order

```bash
cd aws-lambda-deployment-new

# 1. Create ECR repositories
./create-ecr-repos.sh

# 2. Create Lambda IAM role
./create-lambda-role.sh

# 3. Create S3 buckets
./create-s3-buckets.sh

# 4. Build and push all Docker images (takes 30-60 min)
./build-and-push.sh

# 5. Create Lambda functions
./create-lambda-functions.sh

# 6. Create Step Functions state machine
./create-step-functions.sh

# 7. Create API Gateway HTTP endpoint (for JMeter load testing)
./create-api-gateway.sh

# 8. Test the HTTP endpoint
./test-api-endpoint.sh 1.mp4
```

### 5.3 Verify Deployment

```bash
# List Lambda functions
aws lambda list-functions --query "Functions[?starts_with(FunctionName, 'videosearcher')].FunctionName" --output table

# List S3 buckets
aws s3 ls | grep videosearcher

# Check Step Functions
aws stepfunctions list-state-machines --query "stateMachines[?contains(name, 'videosearcher')]"
```

---

## 6. Running the Pipeline

### 6.1 Using the Helper Script

```bash
./run-pipeline.sh /path/to/your/video.mp4
```

### 6.2 Manual Execution (AWS CLI)

```bash
# 1. Upload video to S3
aws s3 cp video.mp4 s3://videosearcher-input-new-{ACCOUNT_ID}/video.mp4

# 2. Start pipeline
aws stepfunctions start-execution \
    --state-machine-arn arn:aws:states:us-east-1:{ACCOUNT_ID}:stateMachine:videosearcher-pipeline-new \
    --input '{"input_bucket": "videosearcher-input-new-{ACCOUNT_ID}", "input_key": "video.mp4", "temp_bucket": "videosearcher-temp-new-{ACCOUNT_ID}", "output_bucket": "videosearcher-output-new-{ACCOUNT_ID}"}'
```

### 6.3 HTTP Execution (Recommended for Load Testing)

After running `./create-api-gateway.sh`, you can trigger the pipeline via HTTP:

```bash
# Simple curl command
curl -X POST "https://{API_ID}.execute-api.us-east-1.amazonaws.com/prod/process?video=1.mp4"

# Response
{
  "status": "started",
  "execution_arn": "arn:aws:states:us-east-1:...",
  "video": "1.mp4",
  "message": "Pipeline execution started successfully"
}
```

**Why HTTP is Better for Load Testing:**
- JMeter can send HTTP requests directly (no AWS SDK needed)
- Supports think time (20 seconds between requests)
- Measures throughput and response times natively
- Industry-standard load testing approach

### 6.4 Monitor Progress

**AWS Console:**
- Go to Step Functions → videosearcher-pipeline-new → Executions
- Click on your execution to see real-time progress graph

**CLI:**
```bash
aws stepfunctions describe-execution --execution-arn {EXECUTION_ARN}
```

---

## 7. Viewing Results

### 7.1 List Results

```bash
aws s3 ls s3://videosearcher-output-new-{ACCOUNT_ID}/results/
```

### 7.2 Download Results

```bash
# Download all results
aws s3 sync s3://videosearcher-output-new-{ACCOUNT_ID}/results/ ./results/

# Extract a specific clip's results
mkdir -p results/clip_0
tar -xzf results/clip_0_detected.tar.gz -C results/clip_0
```

### 7.3 What's in the Results

Each `clip_N_detected.tar.gz` contains:
- Frame images with bounding boxes drawn on detected objects
- Objects labeled (person, car, dog, etc.)

**Transcripts** are in the temp bucket (stage 5 output):
```bash
aws s3 ls s3://videosearcher-temp-new-{ACCOUNT_ID}/stage5/
```

---

## 8. Cost & Cleanup

### 8.1 Estimated Costs

| Service | Monthly Cost (Light Use) |
|---------|-------------------------|
| ECR Storage (~10GB) | ~$1.00 |
| Lambda Compute | ~$0.50-2.00 per video |
| S3 Storage | ~$0.023/GB |
| Step Functions | ~$0.025 per 1000 transitions |

**Total:** ~$5-10/month for development/testing

### 8.2 Cleanup Commands

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Delete Step Functions
aws stepfunctions delete-state-machine \
    --state-machine-arn arn:aws:states:us-east-1:$ACCOUNT_ID:stateMachine:videosearcher-pipeline-new

# Delete Lambda functions
for stage in ffmpeg-0 librosa ffmpeg-1 ffmpeg-2 deepspeech ffmpeg-3 object-detector; do
    aws lambda delete-function --function-name videosearcher-${stage}-new
done

# Delete ECR repositories
for stage in ffmpeg-0 librosa ffmpeg-1 ffmpeg-2 deepspeech ffmpeg-3 object-detector; do
    aws ecr delete-repository --repository-name videosearcher-${stage}-new --force
done

# Delete S3 buckets (empty them first)
for bucket in input temp output; do
    aws s3 rm s3://videosearcher-${bucket}-new-$ACCOUNT_ID --recursive
    aws s3 rb s3://videosearcher-${bucket}-new-$ACCOUNT_ID
done

# Delete IAM roles
aws iam delete-role-policy --role-name videosearcher-lambda-role-new --policy-name LambdaS3Policy
aws iam delete-role --role-name videosearcher-lambda-role-new
aws iam delete-role-policy --role-name videosearcher-stepfunctions-role-new --policy-name StepFunctionsLambdaPolicy
aws iam delete-role --role-name videosearcher-stepfunctions-role-new

# Delete API Gateway resources
aws lambda delete-function --function-name videosearcher-api-trigger
aws iam delete-role-policy --role-name videosearcher-api-trigger-role --policy-name api-trigger-policy
aws iam delete-role --role-name videosearcher-api-trigger-role
# Note: API Gateway deletion via CLI requires the API ID
```

---

## 8.3 Load Testing with JMeter

### Files

| File | Purpose |
|------|---------|
| `videosearcher-http-test.jmx` | 6-phase stepped load test with exponential think time (main test) |
| `videosearcher-http-test-constant.jmx` | Constant-rate load test (fixed RPS, no ramp) |
| `videosearcher-simple-5users.jmx` | Lightweight 5-user smoke test to verify the endpoint |
| `ec2-jmeter-setup.sh` | Installs Java 17 + JMeter 5.6.3 on an EC2 instance (Amazon Linux or Ubuntu) |
| `run-test-on-ec2.sh` | Uploads the JMX plan to EC2, runs the test, downloads results |

### 6-Phase Load Pattern (`videosearcher-http-test.jmx`)

The main test ramps load up and down across 6 phases. Each phase duration is controlled by the `-Jphaseduration` parameter (default 600 s):

| Phase | Users | Think Time |
|-------|-------|------------|
| 1 – Warm-up | 1 | Exponential (mean = phaseduration) |
| 2 – Low | 2 | Exponential |
| 3 – Medium | 4 | Exponential |
| 4 – Peak | 8 | Exponential |
| 5 – Step-down | 4 | Exponential |
| 6 – Cool-down | 1 | Exponential |

Total estimated duration: `6 × phaseduration` + ~1 min ramp overhead.

### Before Running

Edit the `servername` field in the JMX file to point to your API Gateway host:

```xml
<!-- In videosearcher-http-test.jmx -->
<stringProp name="HTTPSampler.domain">YOUR-API-ID.execute-api.YOUR-REGION.amazonaws.com</stringProp>
```

Also make sure the target video file (`video_cut.mp4` by default) exists in the input S3 bucket.

### Running the Test

```bash
cd jmeter-tests

# Full test — 600 s per phase (~61 min total), results saved locally
./run-test-on-ec2.sh -k ~/.ssh/your-key.pem -h <ec2-public-ip>

# Short test — 60 s per phase (~7 min), upload results to S3
./run-test-on-ec2.sh -k ~/.ssh/your-key.pem -h <ec2-public-ip> -p 60 -b <s3-bucket>

# Use a different JMX plan
./run-test-on-ec2.sh -k ~/.ssh/your-key.pem -h <ec2-public-ip> -t videosearcher-simple-5users.jmx
```

**Parameters:**

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `-k` | yes | — | Path to SSH PEM key file |
| `-h` | yes | — | EC2 public IP or hostname |
| `-p` | no | 600 | Duration of each load phase in seconds |
| `-t` | no | `videosearcher-http-test.jmx` | JMX test plan to use |
| `-b` | no | — | S3 bucket to archive results (optional) |

### Output

The script downloads results to `results/` next to the script:

```
results/
├── ec2-<timestamp>-raw.jtl       # Raw JMeter results (CSV format)
└── ec2-<timestamp>-report/       # Auto-generated HTML dashboard
    └── index.html                # Open in browser to view charts
```

If `-b` is given, the same files are also uploaded to `s3://<bucket>/jmeter-results/<timestamp>/`.

---

## 8.4 Load Testing with Locust

Locust is used for trace-driven load testing using a real-world arrival process.

### Files

| File | Purpose |
|------|---------|
| `locustfile.py` | Load generator — reads `workloadProfile.csv`, schedules requests via Lewis-Shedler thinning |
| `workloadProfile.csv` | Input workload trace — one row per second, column `RPS` defines the arrival rate |
| `plot_results.py` | Reads Locust CSV output and generates PNG charts + a self-contained HTML report |
| `ec2-locust-setup.sh` | Installs Python 3, pip, locust, numpy, pandas, matplotlib on an EC2 instance |
| `run-locust-on-ec2.sh` | Uploads test files to EC2, runs Locust headlessly, downloads results |

### Before Running

Edit the `HOST` variable in `locustfile.py`:

```python
HOST = "YOUR-API-ID.execute-api.YOUR-REGION.amazonaws.com"
```

Also make sure `workloadProfile.csv` is present in the `locust-tests/` folder with a semicolon-separated `RPS` column:

```csv
Second;RPS
0;0.05
1;0.08
2;0.12
...
```

### Running the Test

```bash
cd locust-tests

# Run test, download results locally
./run-locust-on-ec2.sh -k ~/.ssh/your-key.pem -h <ec2-public-ip>

# Run test and upload results to S3
./run-locust-on-ec2.sh -k ~/.ssh/your-key.pem -h <ec2-public-ip> -b <s3-bucket>
```

**Parameters:**

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `-k` | yes | — | Path to SSH PEM key file |
| `-h` | yes | — | EC2 public IP or hostname |
| `-b` | no | — | S3 bucket to archive results (optional) |

### Output

Results are downloaded to `results/` next to the script:

```
results/
├── locust-<timestamp>_stats.csv                # Per-endpoint aggregate stats
├── locust-<timestamp>_stats_history.csv        # RPS / response time over time
├── locust-<timestamp>_failures.csv             # Failed requests (may be absent)
└── locust-<timestamp>_request_timestamps.csv   # Raw timestamp + response time per request
```

### Generating the HTML Report Locally

```bash
python3 plot_results.py \
  results/locust-<timestamp>_stats_history.csv \
  results/locust-<timestamp>_request_timestamps.csv
```
`plot_results.py` produces:
- `chart1.png` — RPS, P50/P95/P99 response time, error rate over time
- `chart2.png` (optional) — per-second request rate and response time distribution
- `report.html` — self-contained HTML report with both charts and a summary statistics table

> Requires `matplotlib` and `pandas` installed locally (`pip install matplotlib pandas`).

