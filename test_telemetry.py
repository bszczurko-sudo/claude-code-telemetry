import random
import time
from opentelemetry import metrics
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter

exporter = OTLPMetricExporter(endpoint="http://localhost:4317", insecure=True)
reader = PeriodicExportingMetricReader(exporter, export_interval_millis=5000)
provider = MeterProvider(metric_readers=[reader])
metrics.set_meter_provider(provider)

meter = metrics.get_meter("claude-code-test")
token_counter = meter.create_counter("claude_code_tokens_used", description="Total tokens consumed")
session_counter = meter.create_counter("claude_code_sessions", description="Total sessions initiated")

users = ["brett", "joseph", "alice", "bob", "charlie"]

while True:
    user = random.choice(users)
    token_counter.add(random.randint(200, 1000), {"user": user, "model": "claude-sonnet"})
    session_counter.add(1, {"user": user, "model": "claude-sonnet"})
    time.sleep(10)