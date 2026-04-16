FROM public.ecr.aws/lambda/python:3.12

# Install ffmpeg
RUN dnf install -y ffmpeg && dnf clean all

# Install yt-dlp
RUN pip install --no-cache-dir yt-dlp boto3

# Copy handler
COPY app.py ${LAMBDA_TASK_ROOT}/

CMD ["app.handler"]
