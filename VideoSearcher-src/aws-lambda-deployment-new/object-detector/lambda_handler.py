import json
import boto3
import os
import subprocess
import glob
import tarfile
import shutil

s3_client = boto3.client('s3')

def handler(event, context):
    try:
        input_bucket = event['input_bucket']
        input_key = event['input_key']
        # output_bucket falls back to input_bucket when not explicitly provided by Step Functions
        output_bucket = event.get('output_bucket', input_bucket)
        output_key = event['output_key']

        temp_dir = '/tmp/object-detector'
        frames_dir = f'{temp_dir}/frames'
        annotated_dir = f'{temp_dir}/annotated'

        # Lambda containers are reused across invocations (warm starts); wiping
        # the directory ensures no frames from a previous execution bleed through
        shutil.rmtree(temp_dir, ignore_errors=True)
        os.makedirs(temp_dir, exist_ok=True)
        os.makedirs(frames_dir, exist_ok=True)
        os.makedirs(annotated_dir, exist_ok=True)

        input_path = f'{temp_dir}/input.tar.gz'
        output_path = f'{temp_dir}/output.tar.gz'

        print(f"Downloading {input_bucket}/{input_key} to {input_path}")
        s3_client.download_file(input_bucket, input_key, input_path)

        # The archive from ffmpeg-3 contains one .jpg per sampled frame
        print("Extracting frame images")
        with tarfile.open(input_path, 'r:gz') as tar:
            tar.extractall(frames_dir)

        frame_files = sorted(glob.glob(f'{frames_dir}/*.jpg'))
        if not frame_files:
            raise Exception("No frame images found in tar.gz")

        print(f"Processing {len(frame_files)} frames with object detection")

        # Run YOLOv4 inference on each frame separately; a failed frame is logged
        # as a warning and skipped rather than aborting the entire invocation
        processed_count = 0
        for frame_file in frame_files:
            frame_name = os.path.basename(frame_file).replace('.jpg', '')
            output_file = f'{annotated_dir}/{frame_name}'

            result = subprocess.run([
                'python', 'pipeline_main.py',
                '-i', frame_file,
                '-o', output_file,
                '-y', 'onnx/yolov4.onnx'
            ], capture_output=True, text=True, cwd='/var/task')

            if result.returncode != 0:
                print(f"Warning: Failed to process {frame_file}: {result.stderr}")
            else:
                processed_count += 1
                print(f"Processed: {frame_name}")

        annotated_files = glob.glob(f'{annotated_dir}/*.jpg')
        if not annotated_files:
            raise Exception("No annotated images were generated")

        # Pack annotated frames back into a single archive for the next stage
        print(f"Packaging {len(annotated_files)} annotated images")
        with tarfile.open(output_path, 'w:gz') as tar:
            for ann_file in annotated_files:
                tar.add(ann_file, arcname=os.path.basename(ann_file))

        print(f"Uploading {output_path} to {output_bucket}/{output_key}")
        s3_client.upload_file(output_path, output_bucket, output_key)

        shutil.rmtree(temp_dir, ignore_errors=True)

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'object-detector completed successfully',
                'output_bucket': output_bucket,
                'output_key': output_key,
                'frames_processed': processed_count
            })
        }

    except Exception as e:
        print(f"Error: {str(e)}")
        raise
