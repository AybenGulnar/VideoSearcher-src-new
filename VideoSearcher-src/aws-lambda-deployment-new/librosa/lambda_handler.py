import os
from pathlib import Path

# numba (used internally by librosa) tries to write compiled bytecode to disk.
# In Lambda the only writable location is /tmp, so these must be set before
# any librosa or numba import happens.
os.environ.setdefault("NUMBA_CACHE_DIR", "/tmp/numba_cache")
os.environ.setdefault("HOME", "/tmp")
os.environ.setdefault("XDG_CACHE_HOME", "/tmp")

Path(os.environ["NUMBA_CACHE_DIR"]).mkdir(parents=True, exist_ok=True)

import json
import subprocess
import boto3

s3_client = boto3.client('s3')

def handler(event, context):
    try:
        input_bucket = event['input_bucket']
        input_key = event['input_key']
        output_bucket = event['output_bucket']
        output_key = event['output_key']

        temp_dir = '/tmp/librosa'
        os.makedirs(temp_dir, exist_ok=True)

        input_path = f'{temp_dir}/input.tar.gz'
        output_base = f'{temp_dir}/output'
        output_path = f'{output_base}.tar.gz'

        print(f"Downloading {input_bucket}/{input_key} to {input_path}")
        s3_client.download_file(input_bucket, input_key, input_path)

        # pipeline_main.py loads the audio with librosa, detects silent segments,
        # and writes silence timestamps to a JSON file inside the output archive
        print("Running librosa pipeline (silence detection)")
        result = subprocess.run([
            'python',
            'pipeline_main.py',
            '-i', input_path,
            '-o', output_base
        ], capture_output=True, text=True, cwd='/var/task')

        if result.returncode != 0:
            print(f"Pipeline stderr: {result.stderr}")
            raise Exception(f"Pipeline failed: {result.stderr}")

        print(f"Pipeline stdout: {result.stdout}")

        print(f"Uploading {output_path} to {output_bucket}/{output_key}")
        s3_client.upload_file(output_path, output_bucket, output_key)

        # /tmp is limited to 512 MB in Lambda; remove processed files immediately
        os.remove(input_path)
        os.remove(output_path)

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'librosa completed successfully',
                'output_bucket': output_bucket,
                'output_key': output_key
            })
        }

    except Exception as e:
        print(f"Error: {str(e)}")
        raise
