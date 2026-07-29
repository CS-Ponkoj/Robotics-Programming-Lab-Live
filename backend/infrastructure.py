import json
from pathlib import Path
from uuid import uuid4

from redis import Redis
from rq import Queue


class ManagedObjectStorage:
    """Local controlled storage with an interface that can later target S3."""

    def __init__(self, root: Path):
        self.root = root.resolve()
        self.root.mkdir(parents=True, exist_ok=True)

    def resolve(self, relative_path: str) -> Path:
        target = (self.root / relative_path).resolve()
        if self.root not in target.parents and target != self.root:
            raise ValueError("Asset path escapes managed storage.")
        return target

    def write_json(self, relative_path: str, value: dict) -> Path:
        target = self.resolve(relative_path)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(value, indent=2), encoding="utf-8")
        return target


class JobQueue:
    def enqueue(self, function, *args, **kwargs) -> str:
        raise NotImplementedError


class InlineJobQueue(JobQueue):
    def enqueue(self, function, *args, **kwargs) -> str:
        job_id = str(uuid4())
        function(*args, **kwargs)
        return job_id


class RedisJobQueue(JobQueue):
    def __init__(self, redis_url: str):
        self.queue = Queue("robotics-lab", connection=Redis.from_url(redis_url))

    def enqueue(self, function, *args, **kwargs) -> str:
        return self.queue.enqueue(function, *args, **kwargs).id
