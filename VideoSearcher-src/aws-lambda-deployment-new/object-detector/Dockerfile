# AWS Lambda base image for Python 3.9
FROM public.ecr.aws/lambda/python:3.9

# Install minimal system dependencies for downloading and unpacking archives
RUN yum update -y && \
    yum install -y tar gzip wget && \
    yum clean all

# Install Python dependencies; numpy must be pinned before onnxruntime to avoid conflicts
COPY requirements.txt ${LAMBDA_TASK_ROOT}/

RUN pip install --no-cache-dir numpy==1.26.4 && \
    pip install --no-cache-dir -r requirements.txt

# Copy the YOLOv4 ONNX model weights used for object detection
COPY onnx/ ${LAMBDA_TASK_ROOT}/onnx/

COPY aisprint/ ${LAMBDA_TASK_ROOT}/aisprint/

# Post-processing helper for bounding box decoding
COPY postprocess.py ${LAMBDA_TASK_ROOT}/

COPY pipeline_main.py ${LAMBDA_TASK_ROOT}/pipeline_main.py

COPY lambda_handler.py ${LAMBDA_TASK_ROOT}/

# Set the Lambda function entry point
CMD [ "lambda_handler.handler" ]
