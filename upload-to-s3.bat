@echo off
cd Terraform
FOR /F "tokens=* USEBACKQ" %%F IN (`terraform output -raw s3_bucket_name`) DO (
  SET BUCKET_NAME=%%F
)
cd ..
echo Creating test file...
echo Hello from GitHub Actions > testfile.txt
echo Uploading to bucket: %BUCKET_NAME%
aws s3 cp testfile.txt s3://%BUCKET_NAME%/testfile.txt