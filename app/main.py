import os
import random
from datetime import datetime, timezone
from pathlib import Path

import boto3


def env(name: str, default: str | None = None) -> str:
    v = os.getenv(name, default)
    if v is None or v == "":
        raise RuntimeError(f"Missing required env var: {name}")
    return v


def main() -> None:
    bucket = env("S3_BUCKET")
    prefix = os.getenv("S3_PREFIX", "").strip("/")
    region = os.getenv("AWS_REGION")  # optional; boto3 can infer
    out_dir = Path(os.getenv("OUT_DIR", "/tmp"))

    out_dir.mkdir(parents=True, exist_ok=True)

    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    value = random.randint(0, 1_000_000_000)
    filename = f"random-{ts}.txt"
    filepath = out_dir / filename

    filepath.write_text(f"{value}\n", encoding="utf-8")

    key = f"{prefix}/{filename}" if prefix else filename

    session = boto3.session.Session(region_name=region)
    s3 = session.client("s3")
    s3.upload_file(str(filepath), bucket, key)

    print(f"Uploaded s3://{bucket}/{key} value={value}")


if __name__ == "__main__":
    main()
