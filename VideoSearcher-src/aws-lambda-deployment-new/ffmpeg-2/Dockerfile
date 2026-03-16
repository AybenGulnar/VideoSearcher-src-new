# AWS Lambda base image for Python 3.9
FROM public.ecr.aws/lambda/python:3.9

# Install system dependencies needed to download and extract the static ffmpeg build
RUN yum update -y && \
    yum install -y tar gzip xz wget && \
    yum clean all

# Download and install a static ffmpeg build so the Lambda has access to ffmpeg/ffprobe
RUN cd /tmp && \
    wget https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz && \
    tar xf ffmpeg-release-amd64-static.tar.xz && \
    mv ffmpeg-*-amd64-static/ffmpeg /usr/local/bin/ && \
    mv ffmpeg-*-amd64-static/ffprobe /usr/local/bin/ && \
    chmod +x /usr/local/bin/ffmpeg /usr/local/bin/ffprobe && \
    rm -rf /tmp/ffmpeg-*

COPY requirements.txt ${LAMBDA_TASK_ROOT}/
RUN pip install --no-cache-dir -r requirements.txt boto3

COPY aisprint/ ${LAMBDA_TASK_ROOT}/aisprint/

COPY pipeline_main.py ${LAMBDA_TASK_ROOT}/pipeline_main.py

COPY lambda_handler.py ${LAMBDA_TASK_ROOT}/

# Set the Lambda function entry point
CMD [ "lambda_handler.handler" ]
