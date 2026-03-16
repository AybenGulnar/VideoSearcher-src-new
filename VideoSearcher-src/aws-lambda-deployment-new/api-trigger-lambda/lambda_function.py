import json
import boto3
import os
import time
import uuid

sfn_client = boto3.client('stepfunctions')
s3_client = boto3.client('s3')

# S3 bucket names and the Step Functions ARN are injected via Lambda environment variables
STATE_MACHINE_ARN = os.environ.get('STATE_MACHINE_ARN')
INPUT_BUCKET = os.environ.get('INPUT_BUCKET', 'YOUR-INPUT-BUCKET')
TEMP_BUCKET = os.environ.get('TEMP_BUCKET', 'YOUR-TEMP-BUCKET')
OUTPUT_BUCKET = os.environ.get('OUTPUT_BUCKET', 'YOUR-OUTPUT-BUCKET')

def lambda_handler(event, context):

    print(f"Received event: {json.dumps(event)}")

    try:
        # Accept the video key from three different sources in order of priority:
        # 1) query string  2) JSON request body  3) raw event fields
        video_key = None

        if event.get('queryStringParameters'):
            video_key = event['queryStringParameters'].get('video')

        if not video_key and event.get('body'):
            body = event['body']
            if isinstance(body, str):
                body = json.loads(body)
            video_key = body.get('video') or body.get('input_key')

        if not video_key:
            video_key = event.get('video') or event.get('input_key')

        if not video_key:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': 'Missing video parameter',
                    'usage': 'POST /process?video=filename.mp4 or {"video": "filename.mp4"}'
                })
            }

        # Fail fast with a 404 if the requested video does not exist in the input bucket
        try:
            s3_client.head_object(Bucket=INPUT_BUCKET, Key=video_key)
        except s3_client.exceptions.ClientError as e:
            if e.response['Error']['Code'] == '404':
                return {
                    'statusCode': 404,
                    'headers': {
                        'Content-Type': 'application/json',
                        'Access-Control-Allow-Origin': '*'
                    },
                    'body': json.dumps({
                        'error': f'Video not found: {video_key}',
                        'bucket': INPUT_BUCKET
                    })
                }
            raise

        # Each execution gets a UUID so that parallel requests never share an S3 prefix
        # or collide on the Step Functions execution name
        unique_id = str(uuid.uuid4())
        execution_name = f"http-{int(time.time())}-{unique_id}"

        sfn_input = {
            'input_bucket': INPUT_BUCKET,
            'input_key': video_key,
            'temp_bucket': TEMP_BUCKET,
            'output_bucket': OUTPUT_BUCKET,
            'execution_id': unique_id
        }

        response = sfn_client.start_execution(
            stateMachineArn=STATE_MACHINE_ARN,
            name=execution_name,
            input=json.dumps(sfn_input)
        )

        execution_arn = response['executionArn']

        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'status': 'started',
                'execution_arn': execution_arn,
                'execution_name': execution_name,
                'video': video_key,
                'message': 'Pipeline execution started successfully'
            })
        }

    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': str(e)
            })
        }
