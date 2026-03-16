# AWS Lambda base image for Python 3.9
FROM public.ecr.aws/lambda/python:3.9

# Install tar/gzip to unpack the input .tar.gz archive,
# and sox for WAV format conversion (required by DeepSpeech)
RUN yum update -y && \
    yum install -y tar gzip sox && \
    yum clean all

# Install Python dependencies; boto3 is added explicitly because
# it is not listed in requirements.txt but is required for S3 access
COPY requirements.txt ${LAMBDA_TASK_ROOT}/
RUN pip install --no-cache-dir -r requirements.txt boto3

# Embed pre-trained DeepSpeech model files into the image.
# These files are typically hundreds of MB; bundling them avoids
# downloading them on every cold start.
COPY models/ ${LAMBDA_TASK_ROOT}/models/

COPY aisprint/ ${LAMBDA_TASK_ROOT}/aisprint/

COPY pipeline_main.py ${LAMBDA_TASK_ROOT}/pipeline_main.py

COPY lambda_handler.py ${LAMBDA_TASK_ROOT}/

# Set the Lambda function entry point
CMD [ "lambda_handler.handler" ]
