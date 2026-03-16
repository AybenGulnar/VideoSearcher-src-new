import json
import boto3
import os
import subprocess

s3_client = boto3.client('s3')

def handler(event, context):
    try:
        input_bucket = event['input_bucket']
        input_key = event['input_key']
        output_bucket = event['output_bucket']
        output_key = event['output_key']

        temp_dir = '/tmp/ffmpeg-0'
        os.makedirs(temp_dir, exist_ok=True)

        input_path = f'{temp_dir}/input.mp4'
        # pipeline_main.py appends .tar.gz automatically, so only the base path is passed
        output_base = f'{temp_dir}/output'
        output_path = f'{output_base}.tar.gz'

        print(f"Downloading {input_bucket}/{input_key} to {input_path}")
        s3_client.download_file(input_bucket, input_key, input_path)

        # Invoke pipeline_main.py as a subprocess; it extracts the audio track
        # from the video and writes the result as a .tar.gz archive
        print("Running ffmpeg-0 pipeline (audio extraction)")
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
                'message': 'ffmpeg-0 completed successfully',
                'output_bucket': output_bucket,
                'output_key': output_key
            })
        }

    except Exception as e:
        print(f"Error: {str(e)}")
        raise
