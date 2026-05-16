//! Prometheus metrics for the AXIOM AVS operator.
//! Exposed at http://localhost:9090/metrics

use std::sync::Arc;

use axum::{routing::get, Router};
use eyre::Result;
use prometheus::{
    Counter, Gauge, Histogram, HistogramOpts, IntCounter, Registry,
};
use tracing::info;

// ─────────────────────────────────────────────────────────────
//  Metrics
// ─────────────────────────────────────────────────────────────

#[derive(Clone)]
pub struct Metrics {
    pub registry          : Arc<Registry>,

    // ── Task counters ──────────────────────────────────────────
    pub tasks_completed   : IntCounter,
    pub tasks_failed      : IntCounter,
    pub tasks_timed_out   : IntCounter,
    pub tasks_dropped     : IntCounter,

    // ── Submission counters ───────────────────────────────────
    pub submissions_ok    : IntCounter,
    pub submissions_failed: IntCounter,
    pub rpc_errors        : IntCounter,

    // ── Processing latency ────────────────────────────────────
    pub processing_ms     : Histogram,
    pub proof_ms          : Histogram,

    // ── Operator state ────────────────────────────────────────
    pub active_tasks      : Gauge,
    pub operator_stake    : Gauge,
}

impl Metrics {
    pub fn new() -> Self {
        let registry = Arc::new(Registry::new());

        macro_rules! counter {
            ($name:expr, $help:expr) => {{
                let c = IntCounter::new($name, $help).unwrap();
                registry.register(Box::new(c.clone())).unwrap();
                c
            }};
        }

        macro_rules! gauge {
            ($name:expr, $help:expr) => {{
                let g = Gauge::new($name, $help).unwrap();
                registry.register(Box::new(g.clone())).unwrap();
                g
            }};
        }

        macro_rules! histogram {
            ($name:expr, $help:expr, $buckets:expr) => {{
                let h = Histogram::with_opts(
                    HistogramOpts::new($name, $help).buckets($buckets)
                ).unwrap();
                registry.register(Box::new(h.clone())).unwrap();
                h
            }};
        }

        Self {
            registry: Arc::clone(&registry),

            tasks_completed   : counter!("axiom_tasks_completed_total",    "Total tasks completed"),
            tasks_failed      : counter!("axiom_tasks_failed_total",       "Total tasks failed"),
            tasks_timed_out   : counter!("axiom_tasks_timed_out_total",    "Total tasks timed out"),
            tasks_dropped     : counter!("axiom_tasks_dropped_total",      "Total tasks dropped (queue full)"),
            submissions_ok    : counter!("axiom_submissions_ok_total",     "On-chain submissions succeeded"),
            submissions_failed: counter!("axiom_submissions_failed_total", "On-chain submissions failed"),
            rpc_errors        : counter!("axiom_rpc_errors_total",         "RPC call errors"),

            processing_ms: histogram!(
                "axiom_task_processing_ms",
                "Task end-to-end processing time in milliseconds",
                vec![100.0, 500.0, 1000.0, 3000.0, 5000.0, 10000.0, 30000.0, 60000.0]
            ),

            proof_ms: histogram!(
                "axiom_proof_generation_ms",
                "EZKL proof generation time in milliseconds",
                vec![500.0, 1000.0, 3000.0, 5000.0, 10000.0, 30000.0, 60000.0, 120000.0]
            ),

            active_tasks  : gauge!("axiom_active_tasks",    "Tasks currently being processed"),
            operator_stake: gauge!("axiom_operator_stake",  "Operator stake in ETH (from EigenLayer)"),
        }
    }
}

// ─────────────────────────────────────────────────────────────
//  Metrics HTTP Server
// ─────────────────────────────────────────────────────────────

pub struct MetricsServer {
    port   : u16,
    metrics: Arc<Metrics>,
}

impl MetricsServer {
    pub fn new(port: u16, metrics: Arc<Metrics>) -> Self {
        Self { port, metrics }
    }

    pub async fn run(&self) -> Result<()> {
        let metrics = Arc::clone(&self.metrics);

        let app = Router::new()
            .route("/metrics", get(move || {
                let m = Arc::clone(&metrics);
                async move {
                    use prometheus::Encoder;
                    let encoder  = prometheus::TextEncoder::new();
                    let families = m.registry.gather();
                    let mut buf  = vec![];
                    encoder.encode(&families, &mut buf).unwrap_or_default();
                    String::from_utf8(buf).unwrap_or_default()
                }
            }))
            .route("/health", get(|| async { "OK" }))
            .route("/ready",  get(|| async { "READY" }));

        let addr = format!("0.0.0.0:{}", self.port);
        info!(addr = %addr, "Metrics server listening");

        axum::Server::bind(&addr.parse()?)
            .serve(app.into_make_service())
            .await?;

        Ok(())
    }
}