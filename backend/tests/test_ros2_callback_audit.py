import os

import pytest

from ros2_callback_audit import exactly_one_per_callback, instrument


@pytest.mark.parametrize("kind", ["timer", "scan"])
@pytest.mark.parametrize("count,depth,period", [
    (0, 10, .1), (1, 10, .1), (2, 10, .1), (1, 5, .1), (1, 10, .2),
])
def test_callback_counts_real_publications_not_source_calls(kind, count, depth, period):
    class Publisher:
        topic_name = "/cmd_vel"

        def publish(self, message):
            return message

    class Node:
        def create_timer(self, period, callback):
            return callback

        def create_subscription(self, message_type, topic, callback, qos):
            return callback

        def create_publisher(self, message_type, topic, qos):
            return Publisher()

    read_fd, write_fd = os.pipe()
    instrument(Node, Publisher, write_fd, kind, "/cmd_vel", "/scan")
    publisher = Node().create_publisher(object, "/cmd_vel", depth)

    def helper():
        for _ in range(count):
            publisher.publish(object())

    def callback(*args):
        helper()

    node = Node()
    audited = (node.create_timer(period, callback) if kind == "timer"
               else node.create_subscription(object, "/scan", callback, 10))
    try:
        audited()
        audited()
    finally:
        os.close(write_fd)
    assert exactly_one_per_callback(read_fd) is (
        count == 1 and depth == 10 and (kind == "scan" or period == .1)
    )


def test_no_callback_evidence_cannot_pass():
    read_fd, write_fd = os.pipe()
    os.close(write_fd)
    assert not exactly_one_per_callback(read_fd)
