provider "aws" {
  region = "us-east-1"
}

resource "aws_iam_role" "demo_lambda_role" {
  name = "demo_lambda_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_lambda_function" "demo_lambda" {
  filename      = "${path.module}/empty_function.zip"
  function_name = "demo-lambda-function"
  role          = "${aws_iam_role.demo_lambda_role.arn}"
  handler       = "index.handler"

  runtime = "nodejs10.x"

  depends_on    = ["aws_iam_role_policy_attachment.lambda_logs", "aws_cloudwatch_log_group.lambda_demo"]
}

# This is to optionally manage the CloudWatch Log Group for the Lambda Function.
# If skipping this resource configuration, also add "logs:CreateLogGroup" to the IAM policy below.
resource "aws_cloudwatch_log_group" "lambda_demo" {
  name              = "/aws/lambda/stream-consumer-function"
  retention_in_days = 1
}

# See also the following AWS managed policy: AWSLambdaBasicExecutionRole
resource "aws_iam_policy" "lambda_permissions" {
  name = "lambda_permissions"
  path = "/"
  description = "IAM policy for logging from a lambda"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "kms:Decrypt"
      ],
      "Effect": "Allow",
      "Resource": "arn:aws:kms:us-east-1:619481458632:key/062e26bc-bb94-4c6e-bea1-f4ea87a6afc3"
    },
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*",
      "Effect": "Allow"
    },
    {
      "Action": [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes"
      ],
      "Resource": "${aws_sqs_queue.demo_sfn_queue.arn}",
      "Effect": "Allow"
    },
    {
      "Effect": "Allow",
      "Action":   ["s3:PutObject"],
      "Resource": "arn:aws:s3:::*"
    },
    {
      "Effect": "Allow",
      "Action": [
          "states:SendTaskSuccess"
      ],
      "Resource": [
          "${aws_sfn_state_machine.async_demo_state_machine.id}"
      ]
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role = "${aws_iam_role.demo_lambda_role.name}"
  policy_arn = "${aws_iam_policy.lambda_permissions.arn}"
}

resource "aws_s3_bucket" "code_bucket" {
  bucket = "justin-lambda-code-bucket"
  acl    = "private"

  tags = {
    Name        = "code bucket"
    Environment = "dev"
  }

  force_destroy = true
}

resource "aws_s3_bucket" "data_bucket" {
  bucket = "justin-demo-data-bucket"
  acl    = "private"

  tags = {
    Name        = "data bucket"
    Environment = "dev"
  }

  force_destroy = true
}

resource "aws_sqs_queue" "demo_sfn_queue" {
  name                      = "demo-sfn-queue"
  delay_seconds             = 0
  max_message_size          = 2048
  message_retention_seconds = 60
  receive_wait_time_seconds = 0

  tags = {
    Environment = "production"
  }
}

resource "aws_lambda_event_source_mapping" "example" {
  event_source_arn  = "${aws_sqs_queue.demo_sfn_queue.arn}"
  function_name     = "${aws_lambda_function.demo_lambda.arn}"
  batch_size = 1
}

resource "aws_iam_policy" "iam_for_sfn" {
  name = "iam_for_sfn"
  path = "/"
  description = "IAM policy for demo step function"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "sqs:SendMessage",
        "sqs:GetQueueAttributes"
      ],
      "Resource": "${aws_sqs_queue.demo_sfn_queue.arn}",
      "Effect": "Allow"
    },
    {
      "Effect": "Allow",
      "Action": [
          "states:StartExecution",
          "events:PutTargets",
          "events:PutRule",
          "events:DescribeRule",
          "states:DescribeExecution",
          "states:StopExecution"
      ],
      "Resource": [
          "${aws_sfn_state_machine.async_demo_state_machine.id}"
      ]
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "sfn_policy_attachment" {
  role = "${aws_iam_role.iam_for_sfn.name}"
  policy_arn = "${aws_iam_policy.iam_for_sfn.arn}"
}

resource "aws_iam_role" "iam_for_sfn" {
  name = "iam_for_sfn"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "states.us-east-1.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_sfn_state_machine" "async_demo_state_machine" {
  name     = "async-demo-state-machine"
  role_arn = "${aws_iam_role.iam_for_sfn.arn}"

  definition = <<EOF
{
  "Comment": "Asynchronous step function task demo",
  "StartAt": "RandomDelay",
  "States": {
    "RandomDelay": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sqs:sendMessage.waitForTaskToken",
      "HeartbeatSeconds": 30,
      "Parameters": {
        "QueueUrl": "${aws_sqs_queue.demo_sfn_queue.id}",
        "MessageBody": {
            "Message": "Hello from Step Functions!",
            "TaskToken.$": "$$.Task.Token"
        }
      },
      "Next": "SuccessState"
    },
    "SuccessState": {
      "Type": "Succeed"
    }
  }
}
EOF
}