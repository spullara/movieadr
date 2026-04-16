FROM public.ecr.aws/lambda/python:3.12

# Install ffmpeg
RUN dnf install -y tar xz unzip && \
    curl -L https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-arm64-static.tar.xz -o /tmp/ffmpeg.tar.xz && \
    tar xf /tmp/ffmpeg.tar.xz -C /tmp && \
    cp /tmp/ffmpeg-*/ffmpeg /usr/local/bin/ffmpeg && \
    cp /tmp/ffmpeg-*/ffprobe /usr/local/bin/ffprobe && \
    rm -rf /tmp/ffmpeg* && \
    chmod +x /usr/local/bin/ffmpeg /usr/local/bin/ffprobe

# Install deno (required by yt-dlp for YouTube extraction)
RUN curl -fsSL https://dl.deno.land/release/v2.3.1/deno-aarch64-unknown-linux-gnu.zip -o /tmp/deno.zip && \
    cd /tmp && unzip deno.zip && \
    mv deno /usr/local/bin/deno && \
    chmod +x /usr/local/bin/deno && \
    rm /tmp/deno.zip

# Install yt-dlp
RUN pip install --no-cache-dir yt-dlp boto3

# Copy handler
COPY app.py ${LAMBDA_TASK_ROOT}/

CMD ["app.handler"]
