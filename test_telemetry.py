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
cost_counter = meter.create_counter("claude_code_estimated_cost", description="Total cost incurred")
acceptance_counter = meter.create_counter("claude_code_suggestions_accepted", description="Code suggestions accepted")
rejection_counter = meter.create_counter("claude_code_suggestions_rejected", description="Code suggestions rejected")
users = ["brett", "joseph", "alice", "bob", "charlie"]

while True:
    user = random.choice(users)
    tokens = random.randint(200, 1000)
    cost = tokens * (3 / 1_000_000)  # $3 per million tokens, simplified

    token_counter.add(tokens, {"user": user, "model": "claude-sonnet"})
    cost_counter.add(cost, {"user": user, "model": "claude-sonnet"})
    session_counter.add(1, {"user": user, "model": "claude-sonnet"})
    suggestions = random.randint(1, 10)
    accepted = random.randint(0, suggestions)
    rejected = suggestions - accepted

    acceptance_counter.add(accepted, {"user": user, "model": "claude-sonnet"})
    rejection_counter.add(rejected, {"user": user, "model": "claude-sonnet"})
    time.sleep (10)