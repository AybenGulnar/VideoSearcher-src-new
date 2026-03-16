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

        temp_dir = '/tmp/deepspeech'
        os.makedirs(temp_dir, exist_ok=True)

        input_path = f'{temp_dir}/input.tar.gz'
        output_base = f'{temp_dir}/output'
        output_path = f'{output_base}.tar.gz'

        s3_client.download_file(input_bucket, input_key, input_path)

        # The archive produced by ffmpeg-2 bundles the .wav audio and the .mp4
        # clip together; both are needed by pipeline_main.py
        with tarfile.open(input_path, 'r:gz') as tar:
            tar.extractall(temp_dir)

        # pipeline_main.py looks for the audio at a fixed path (input.wav),
        # so rename whatever filename came out of the archive
        wav_files = glob.glob(f'{temp_dir}/*.wav')
        if wav_files:
            actual_wav = wav_files[0]
            expected_wav = f'{temp_dir}/input.wav'
            if actual_wav != expected_wav:
                os.rename(actual_wav, expected_wav)

        # Same fixed-path convention applies to the video file
        mp4_files = glob.glob(f'{temp_dir}/*.mp4')
        if mp4_files:
            actual_mp4 = mp4_files[0]
            expected_mp4 = f'{temp_dir}/input.mp4'
            if actual_mp4 != expected_mp4:
                os.rename(actual_mp4, expected_mp4)

        # pipeline_main.py is launched as a child process so that DeepSpeech's
        # native libraries are isolated from the Lambda runtime process
        result = subprocess.run([
            'python', 'pipeline_main.py',
            '-i', input_path,
            '-o', output_base
        ], capture_output=True, text=True, cwd='/var/task')

        if result.returncode != 0:
            print(f"Pipeline stderr: {result.stderr}")
            raise Exception(f"Pipeline failed: {result.stderr}")

        print(f"Pipeline stdout: {result.stdout}")

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
                'message': 'deepspeech completed successfully',
                'output_bucket': output_bucket,
                'output_key': output_key
            })
        }

    except Exception as e:
        print(f"Error: {str(e)}")
        raise
