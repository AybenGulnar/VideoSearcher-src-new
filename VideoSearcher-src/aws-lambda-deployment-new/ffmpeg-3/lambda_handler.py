import json
import boto3
import os
import subprocess
import glob
import tarfile

s3_client = boto3.client('s3')

def handler(event, context):
    try:
        input_bucket = event['input_bucket']
        input_key = event['input_key']
        # output_bucket falls back to input_bucket when not explicitly provided by Step Functions
        output_bucket = event.get('output_bucket', input_bucket)
        output_key = event['output_key']

        temp_dir = '/tmp/ffmpeg-3'
        os.makedirs(temp_dir, exist_ok=True)

        input_path = f'{temp_dir}/input.tar.gz'
        output_base = f'{temp_dir}/output'
        output_path = f'{output_base}.tar.gz'

        print(f"Downloading {input_bucket}/{input_key} to {input_path}")
        s3_client.download_file(input_bucket, input_key, input_path)

        # The archive produced by ffmpeg-2 contains the video clip; extract it first
        with tarfile.open(input_path, 'r:gz') as tar:
            tar.extractall(temp_dir)

        # pipeline_main.py expects the video at a fixed path regardless of the
        # original filename, so rename it if necessary
        mp4_files = glob.glob(f'{temp_dir}/*.mp4')
        if mp4_files:
            actual_mp4 = mp4_files[0]
            expected_mp4 = f'{temp_dir}/input.mp4'
            if actual_mp4 != expected_mp4:
                os.rename(actual_mp4, expected_mp4)

        # pipeline_main.py samples frames from the clip at a fixed interval
        # and writes each frame as output-<n>.jpg
        print("Running ffmpeg-3")
        result = subprocess.run([
            'python', 'pipeline_main.py',
            '-i', input_path,
            '-o', output_base
        ], capture_output=True, text=True, cwd='/var/task')

        if result.returncode != 0:
            print(f"Pipeline stderr: {result.stderr}")
            raise Exception(f"Pipeline failed: {result.stderr}")

        print(f"Pipeline stdout: {result.stdout}")

        frame_files = sorted(glob.glob(f'{temp_dir}/output-*.jpg'))
        if not frame_files:
            raise Exception("No frame images were generated")

        # Bundle all frames into one archive so the object-detector stage
        # receives a single S3 object rather than many individual files
        print(f"Packaging {len(frame_files)} frames into tar.gz")
        with tarfile.open(output_path, 'w:gz') as tar:
            for frame_file in frame_files:
                tar.add(frame_file, arcname=os.path.basename(frame_file))

        print(f"Uploading {output_path} to {output_bucket}/{output_key}")
        s3_client.upload_file(output_path, output_bucket, output_key)

        # /tmp is limited to 512 MB in Lambda; wipe everything after upload
        for f in glob.glob(f'{temp_dir}/*'):
            try:
                os.remove(f)
            except:
                pass

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'ffmpeg-3 completed successfully',
                'output_bucket': output_bucket,
                'output_key': output_key,
                'frame_count': len(frame_files)
            })
        }

    except Exception as e:
        print(f"Error: {str(e)}")
        raise
