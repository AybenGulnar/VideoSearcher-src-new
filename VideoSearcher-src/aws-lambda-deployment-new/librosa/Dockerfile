# AWS Lambda base image for Python 3.9
FROM public.ecr.aws/lambda/python:3.9

# Install build tools and audio codec libraries required to compile libsndfile from source
RUN yum update -y && \
    yum install -y tar gzip bzip2 xz wget gcc gcc-c++ make autoconf automake libtool cmake pkgconfig flac-devel libogg-devel libvorbis-devel && \
    yum clean all

# Build and install libsndfile from source; the yum package is too old for SoundFile/librosa
RUN cd /tmp && \
    wget https://github.com/libsndfile/libsndfile/releases/download/1.0.31/libsndfile-1.0.31.tar.bz2 && \
    tar xf libsndfile-1.0.31.tar.bz2 && \
    cd libsndfile-1.0.31 && \
    ./configure --prefix=/usr/local && \
    make && \
    make install && \
    cd / && \
    rm -rf /tmp/libsndfile-*

# Make the newly installed libsndfile visible to the dynamic linker
ENV LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH

RUN pip install --upgrade pip
RUN pip install setuptools==69.0.3 wheel

# Install audio/ML dependencies in a specific order to avoid version conflicts:
# numpy must come before librosa; soxr requires a pre-built wheel
COPY requirements.txt ${LAMBDA_TASK_ROOT}/
RUN pip install --no-cache-dir numpy==1.26.4 && \
    pip install --no-cache-dir soxr==0.3.7 --only-binary=:all: && \
    pip install --no-cache-dir SoundFile==0.12.1 boto3==1.26.137 && \
    pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir librosa==0.10.0 && \
    pip install --no-cache-dir --force-reinstall setuptools==69.0.3 && \
    python -c "from pkg_resources import resource_filename; print('✓ pkg_resources working')"

COPY aisprint/ ${LAMBDA_TASK_ROOT}/aisprint/

COPY pipeline_main.py ${LAMBDA_TASK_ROOT}/pipeline_main.py

COPY lambda_handler.py ${LAMBDA_TASK_ROOT}/

# Point numba and other tools to writable temp directories inside Lambda
ENV NUMBA_CACHE_DIR=/tmp/numba_cache
ENV HOME=/tmp
ENV XDG_CACHE_HOME=/tmp

# Set the Lambda function entry point
CMD [ "lambda_handler.handler" ]
