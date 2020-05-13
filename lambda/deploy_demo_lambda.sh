cd demo_lambda
zip -rqq demo-lambda-function.zip index.js node_modules
mv demo-lambda-function.zip ../demo-lambda-function.zip
cd ..

aws s3 cp demo-lambda-function.zip s3://justin-lambda-code-bucket/

aws lambda update-function-code --function-name demo-lambda-function --s3-bucket justin-lambda-code-bucket --s3-key demo-lambda-function.zip --region us-east-1