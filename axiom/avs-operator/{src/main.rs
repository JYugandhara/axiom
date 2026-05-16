//! AXIOM AVS Operator Node
//!
//! EigenLayer Actively Validated Service operator.
//! Listens for game compute tasks from the L3 chain,
//! runs pathfinding + AI inference, generates EZKL ZK proofs,
//! and submits signed results to AxiomTaskManager.sol.
//!
//! Architecture:
//!   main → TaskWatcher → TaskDispatcher
//!                           ├─ PathfindingWorker
//!                           ├─ AIInferenceWorker  
//!                           └─ ProverWorker → ChainSubmitter
//!
//! Usage (in WSL terminal):
//!   cargo run -- --env development
//!
//! Or via VS Code launch.json:
//!   Run "⚡ AVS — Operator Node (debug)"

use std::sync::Arc;
use std::time::Duration;

use clap::Parser;
use eyre::Result;
use tracing::{error, info, warn};
use tracing_subscriber::{fmt, prelude::*, EnvFilter};

mod chain;
mod config;
mod metrics;
mod pathfinding;
mod ai_inference;
mod prover;
mod task;
mod types;
mod errors;

use config::OperatorConfig;
use task::TaskDispatcher;
use chain::ChainClient;
use metrics::MetricsServer;

// ─────────────────────────────────────────────────────────────
//  CLI Args
// ─────────────────────────────────────────────────────────────

#[derive(Parser, Debug)]
#[command(
    name        = "avs-operator",
    about       = "AXIOM EigenLayer AVS Operator Node",
    version     = env!("CARGO_PKG_VERSION"),
    long_about  = None,
)]
struct Cli {
    /// Environment: development | testnet | mainnet
    #[arg(long, env = "AXIOM_ENV", default_value = "development")]
    env: String,

    /// Path to config file (overrides env defaults)
    #[arg(long, env = "CONFIG_PATH")]
    config: Option<String>,

    /// Override RPC URL for L3 chain
    #[arg(long, env = "L3_RPC_URL")]
    rpc_url: Option<String>,

    /// Metrics server port (Prometheus)
    #[arg(long, env = "METRICS_PORT", default_value = "9090")]
    metrics_port: u16,

    /// Dry run — compute tasks but do NOT submit on-chain
    #[arg(long, default_value = "false")]
    dry_run: bool,
}

// ─────────────────────────────────────────────────────────────
//  Entry Point
// ─────────────────────────────────────────────────────────────

#[tokio::main]
async fn main() -> Result<()> {
    // ── Logging ──────────────────────────────────────────────
    tracing_subscriber::registry()
        .with(
            fmt::layer()
                .with_target(true)
                .with_thread_ids(false)
                .with_file(true)
                .with_line_number(true),
        )
        .with(EnvFilter::from_env("RUST_LOG").add_directive(
            "avs_operator=info".parse().unwrap(),
        ))
        .init();

    let cli = Cli::parse();

    info!("╔══════════════════════════════════════════╗");
    info!("║   AXIOM AVS Operator Node  v{}       ║", env!("CARGO_PKG_VERSION"));
    info!("╚══════════════════════════════════════════╝");
    info!(env = %cli.env, dry_run = cli.dry_run, "Starting operator");

    // ── Config ───────────────────────────────────────────────
    let mut cfg = OperatorConfig::load(&cli.env, cli.config.as_deref())?;
    if let Some(rpc) = cli.rpc_url {
        cfg.l3_rpc_url = rpc;
    }
    cfg.dry_run = cli.dry_run;

    info!(
        l3_rpc      = %cfg.l3_rpc_url,
        task_manager = %cfg.task_manager_address,
        "Config loaded"
    );

    // ── Metrics server (Prometheus) ──────────────────────────
    let metrics = Arc::new(metrics::Metrics::new());
    let metrics_srv = MetricsServer::new(cli.metrics_port, Arc::clone(&metrics));
    tokio::spawn(async move {
        if let Err(e) = metrics_srv.run().await {
            error!("Metrics server error: {e}");
        }
    });
    info!(port = cli.metrics_port, "Metrics server started");

    // ── Chain client ─────────────────────────────────────────
    let chain = Arc::new(
        ChainClient::new(&cfg).await
            .map_err(|e| eyre::eyre!("Failed to connect to L3: {e}"))?
    );
    info!("Connected to L3 chain ✓");

    // ── Verify operator is registered ────────────────────────
    let operator_addr = chain.operator_address();
    let is_registered = chain.is_operator_registered(operator_addr).await?;
    if !is_registered {
        warn!(
            address = %operator_addr,
            "Operator not registered on EigenLayer — run register-operator first"
        );
        if cfg.env != "development" {
            eyre::bail!("Operator must be registered before running on {}", cfg.env);
        }
    } else {
        info!(address = %operator_addr, "Operator registration verified ✓");
    }

    // ── Load AI model ────────────────────────────────────────
    let ai_worker = Arc::new(
        ai_inference::AIInferenceWorker::new(&cfg.model_path)
            .map_err(|e| eyre::eyre!("Failed to load AI model: {e}"))?
    );
    info!(model = %cfg.model_path, "AI model loaded ✓");

    // ── Task dispatcher ──────────────────────────────────────
    let dispatcher = TaskDispatcher::new(
        Arc::clone(&chain),
        Arc::clone(&ai_worker),
        Arc::clone(&metrics),
        cfg.clone(),
    );

    info!("AVS Operator ready — watching for tasks...");
    info!("Press Ctrl+C to stop\n");

    // ── Graceful shutdown handler ────────────────────────────
    let dispatcher_handle = tokio::spawn(async move {
        dispatcher.run().await
    });

    tokio::select! {
        result = dispatcher_handle => {
            match result {
                Ok(Ok(())) => info!("Dispatcher exited cleanly"),
                Ok(Err(e)) => error!("Dispatcher error: {e}"),
                Err(e)     => error!("Dispatcher panicked: {e}"),
            }
        }
        _ = tokio::signal::ctrl_c() => {
            info!("Received Ctrl+C — shutting down gracefully...");
        }
    }

    info!("AVS Operator stopped.");
    Ok(())
}