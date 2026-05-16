# ─────────────────────────────────────────────────────────────
#  AXIOM AVS Operator Node — Dockerfile
#
#  Multi-stage build:
#    Stage 1: builder  — compiles Rust binary
#    Stage 2: runtime  — minimal image with binary + EZKL CLI
#
#  Build:
#    docker build -t axiom-avs-operator .
#
#  Run:
#    docker run -d \
#      --env-file .env \
#      -p 9090:9090 \
#      axiom-avs-operator
# ─────────────────────────────────────────────────────────────

# ── Stage 1: Rust builder ─────────────────────────────────────
FROM rust:1.77-slim-bookworm AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Cache dependencies — copy manifests first
COPY Cargo.toml Cargo.lock ./

# Dummy src to cache deps
RUN mkdir src && echo "fn main() {}" > src/main.rs
RUN cargo build --release 2>/dev/null || true
RUN rm -rf src

# Copy real source and build
COPY src ./src
RUN cargo build --release

# ── Stage 2: Runtime ──────────────────────────────────────────
FROM debian:bookworm-slim AS runtime

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    python3 \
    python3-pip \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install EZKL CLI
RUN pip3 install ezkl --break-system-packages

# Create non-root operator user
RUN useradd -m -u 1001 operator
USER operator
WORKDIR /home/operator

# Copy compiled binary
COPY --from=builder /app/target/release/avs-operator /usr/local/bin/avs-operator

# Copy circuit artifacts (mounted via volume in production)
# In production: mount these from a secrets manager, not baked into image
RUN mkdir -p circuits ai-model

# Expose Prometheus metrics port
EXPOSE 9090

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD curl -f http://localhost:9090/health || exit 1

# Environment defaults (override via --env-file)
ENV AXIOM_ENV=development \
    RUST_LOG=info \
    METRICS_PORT=9090 \
    MAX_CONCURRENT_TASKS=4 \
    POLL_INTERVAL_MS=500

ENTRYPOINT ["avs-operator"]
CMD ["--env", "development"]