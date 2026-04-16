"""Lambda handler for YouTube video download via yt-dlp."""

import json
import os
import subprocess
import tempfile
import uuid

import boto3

S3_BUCKET = os.environ["S3_BUCKET"]
PRESIGN_EXPIRY = 3600  # 1 hour

s3 = boto3.client("s3")


def handler(event, context):
    """POST /download — download a YouTube video and return a presigned S3 URL."""
    try:
        body = json.loads(event.get("body", "{}"))
    except (json.JSONDecodeError, TypeError):
        return _error(400, "Invalid JSON body")

    url = body.get("url", "").strip()
    if not url:
        return _error(400, "Missing 'url' field")

    if "youtube.com" not in url and "youtu.be" not in url:
        return _error(400, "URL must be a YouTube link")

    # Write cookies file if provided (Netscape cookie jar format)
    cookies = body.get("cookies", "")
    cookie_args = []
    if cookies:
        cookie_path = "/tmp/cookies.txt"
        with open(cookie_path, "w") as f:
            f.write(cookies)
        cookie_args = ["--cookies", cookie_path]

    # Get video title first
    title = _get_title(url, cookie_args)

    # Download video to /tmp
    work_dir = tempfile.mkdtemp(dir="/tmp")
    output_template = os.path.join(work_dir, "video.%(ext)s")

    cmd = [
        "yt-dlp",
        "--no-playlist",
        "--no-check-certificates",
        "--remote-components", "ejs:github",
        "-f", "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best",
        "--merge-output-format", "mp4",
        "-o", output_template,
        *cookie_args,
        url,
    ]

    result = subprocess.run(cmd, capture_output=True, text=True, timeout=840)

    if result.returncode != 0:
        return _error(500, f"yt-dlp failed: {result.stderr[:500]}")

    # Find the downloaded file
    video_file = None
    for f in os.listdir(work_dir):
        if f.startswith("video"):
            video_file = os.path.join(work_dir, f)
            break

    if not video_file or not os.path.exists(video_file):
        return _error(500, "Downloaded file not found")

    # Upload to S3
    s3_key = f"downloads/{uuid.uuid4().hex}/{os.path.basename(video_file)}"
    s3.upload_file(video_file, S3_BUCKET, s3_key)

    # Generate presigned URL
    download_url = s3.generate_presigned_url(
        "get_object",
        Params={"Bucket": S3_BUCKET, "Key": s3_key},
        ExpiresIn=PRESIGN_EXPIRY,
    )

    # Clean up /tmp
    try:
        import shutil
        shutil.rmtree(work_dir, ignore_errors=True)
    except Exception:
        pass

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({
            "downloadUrl": download_url,
            "title": title or os.path.basename(video_file),
            "fileName": os.path.basename(video_file),
        }),
    }


def _get_title(url, cookie_args=None):
    """Extract video title using yt-dlp --print title."""
    if cookie_args is None:
        cookie_args = []
    try:
        result = subprocess.run(
            ["yt-dlp", "--no-playlist", "--no-check-certificates", "--remote-components", "ejs:github", *cookie_args, "--print", "title", url],
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except Exception:
        pass
    return None


def _error(status, message):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"error": message}),
    }
