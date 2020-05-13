// Just requiring a lot of large libraries to show increased cold start time

const AWSXRay = require('aws-xray-sdk');
const AWS = AWSXRay.captureAWS(require('aws-sdk'));
const uuid = require('uuid/v4')
const stepfunctions = new AWS.StepFunctions();
const s3 = new AWS.S3();

const config = {
  region: 'us-east-1',
  dstBucket: 'justin-demo-data-bucket',
}

async function handler(event) {
  const record = event.Records[0]
  const body = JSON.parse(record.body)

  console.log(`Uploading file to s3 bucket`);
  const s3Params = {
    Bucket: config.dstBucket,
    Key: `${uuid()}-${Date.now()}`,
    Body: JSON.stringify({ ...body, val1: Math.random(), val2: Math.random()}),
    ContentType: "text"
  };

  await s3.putObject(s3Params).promise(); 
  
  const SFNParams = {
    output: "\"Callback task completed successfully.\"",
    taskToken: body.TaskToken
  };
  
  console.log(`Calling Step Functions to complete callback task with params ${JSON.stringify(SFNParams)}`);

  await stepfunctions.sendTaskSuccess(SFNParams).promise();

  console.log('Done')
}

module.exports.handler = handler
