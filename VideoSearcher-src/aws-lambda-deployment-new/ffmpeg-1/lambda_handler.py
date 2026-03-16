import json
import boto3
import os
import glob

s3_client = boto3.client('s3')

def handler(event, context):

    try:
        input_bucket = event['input_bucket']
        input_key = event['input_key']
        output_bucket = event['output_bucket']
        # output_prefix is the S3 folder that will hold all generated clips for this execution
        output_prefix = event['output_prefix']

        input_path = '/tmp/input.tar.gz'
        output_base = '/tmp/output'

        os.makedirs(output_base, exist_ok=True)

        print(f"Downloading s3://{input_bucket}/{input_key}")
        s3_client.download_file(input_bucket, input_key, input_path)

        # pipeline_main is imported at runtime to avoid loading it before the
        # environment is fully set up inside the Lambda container
        from pipeline_main import main
        args = {
            'input': input_path,
            'output': os.path.join(output_base, 'clip')
        }

        print("Running video segmentation pipeline")
        main(args)

        # Clips are written as clip_0.mp4, clip_1.mp4, … by pipeline_main
        clip_files = sorted(glob.glob(os.path.join(output_base, 'clip_*.mp4')))

        if not clip_files:
            raise Exception("No video clips were generated")

        print(f"Found {len(clip_files)} video clips")

        # Upload every clip individually and record its S3 key so that downstream
        # stages (ffmpeg-2, ffmpeg-3, deepspeech) can be fanned out in parallel
        clips_metadata = []
        for i, clip_file in enumerate(clip_files):
            clip_filename = os.path.basename(clip_file)
            output_key = f"{output_prefix}/{clip_filename}"

            print(f"Uploading {clip_filename} to s3://{output_bucket}/{output_key}")
            s3_client.upload_file(clip_file, output_bucket, output_key)

            clips_metadata.append({
                "temp_bucket": output_bucket,
                "output_bucket": event.get('output_bucket', output_bucket),
                "clip_key": output_key,
                "clip_index": i
            })

        os.remove(input_path)
        for clip_file in clip_files:
            os.remove(clip_file)

        return {
            'statusCode': 200,
            'clips': clips_metadata,
            'clip_count': len(clips_metadata)
        }

    except Exception as e:
        print(f"Error: {str(e)}")
        raise
