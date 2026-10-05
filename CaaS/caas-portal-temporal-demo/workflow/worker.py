"""Temporal Worker — runs the workflow + activities against the configured
Temporal namespace. Run alongside api/main.py.

This file is intentionally minimal. Production CaaS workers would also
register custom interceptors, observability, and structured logging.
"""

from __future__ import annotations

import asyncio
import logging
import os
import signal

from temporalio.client import Client
from temporalio.worker import Worker

from .activities import (
    apply_policy_baseline,
    apply_to_k8s_stub,
    request_human_approval,
    validate_compliance_and_cost,
)
from .cluster_request import ClusterRequestWorkflow

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
logger = logging.getLogger(__name__)


TEMPORAL_ADDRESS = os.getenv("TEMPORAL_ADDRESS", "temporal:7233")
TEMPORAL_NAMESPACE = os.getenv("TEMPORAL_NAMESPACE", "default")
TASK_QUEUE = os.getenv("TASK_QUEUE", "caas-cluster-request-tq")


async def main() -> None:
    client: Client = await Client.connect(
        target_host=TEMPORAL_ADDRESS,
        namespace=TEMPORAL_NAMESPACE,
    )
    worker = Worker(
        client,
        task_queue=TASK_QUEUE,
        workflows=[ClusterRequestWorkflow],
        activities=[
            validate_compliance_and_cost,
            request_human_approval,
            apply_to_k8s_stub,
            apply_policy_baseline,
        ],
    )

    logger.info("Worker started; task_queue=%s address=%s", TASK_QUEUE, TEMPORAL_ADDRESS)

    stop_event = asyncio.Event()

    def _on_signal(signum: int, frame: object) -> None:  # noqa: ARG001
        logger.info("Received signal %s, shutting down", signum)
        stop_event.set()

    signal.signal(signal.SIGINT, _on_signal)
    signal.signal(signal.SIGTERM, _on_signal)

    await worker.run()
    await stop_event.wait()


if __name__ == "__main__":
    asyncio.run(main())
