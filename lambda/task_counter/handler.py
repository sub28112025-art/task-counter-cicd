import json
import boto3
import os

dynamodb = boto3.resource('dynamodb')
table_name = os.environ.get('DYNAMODB_TABLE_NAME')
table = dynamodb.Table(table_name)

def lambda_handler(event, context):
    try:
        http_method = event.get('httpMethod', 'GET')
        
        if http_method == 'GET':
            response = table.get_item(Key={'id': 'counter'})
            count = int(response.get('Item', {}).get('count', 0))
            
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'count': count,
                    'environment': os.environ.get('ENVIRONMENT', 'unknown')
                })
            }
        
        elif http_method == 'POST':
            response = table.update_item(
                Key={'id': 'counter'},
                UpdateExpression='ADD #count :inc',
                ExpressionAttributeNames={'#count': 'count'},
                ExpressionAttributeValues={':inc': 1},
                ReturnValues='UPDATED_NEW'
            )
            
            new_count = int(response['Attributes']['count'])
            
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'count': new_count,
                    'environment': os.environ.get('ENVIRONMENT', 'unknown'),
                    'message': 'Counter incremented'
                })
            }
        
        else:
            return {
                'statusCode': 405,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Method not allowed'})
            }
            
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e)})
        }