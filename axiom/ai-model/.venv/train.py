"""
AXIOM — Faction Strategy Model Training
=======================================
Trains a lightweight transformer that learns optimal faction strategy
from simulated game state data.

Input  : Game state tensor (territory, energy, threats, resources)
Output : Action probability distribution over 8 possible moves

Usage (in WSL terminal):
    source .venv/bin/activate
    python train.py --epochs 100 --batch-size 64 --output faction_model.pt

Or via VS Code launch.json:
    Run "🧠 AI — Train faction model"
"""

import argparse
import json
import os
import time
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim
from sklearn.model_selection import train_test_split
from torch.utils.data import DataLoader, TensorDataset
from tqdm import tqdm

# ─────────────────────────────────────────────
#  Config
# ─────────────────────────────────────────────

# Game state input dimensions
STATE_DIM = 32        # Feature vector size per game state
ACTION_DIM = 8        # Number of possible actions:
                      #   0=expand_north, 1=expand_east, 2=expand_south,
                      #   3=expand_west, 4=attack, 5=defend, 6=harvest, 7=idle

HIDDEN_DIM = 64       # Transformer hidden size (small = faster ZK proving)
NUM_HEADS = 4         # Attention heads
NUM_LAYERS = 2        # Transformer encoder layers
SEQ_LEN = 8          # Last N game states (history window)
DROPOUT = 0.1

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")


# ─────────────────────────────────────────────
#  Game State Features (what the model sees)
# ─────────────────────────────────────────────
#
# Index  Feature
# ─────  ──────────────────────────────────────
#  0-3   territory_counts (N/E/S/W quadrant)
#  4     total_territory
#  5     energy_balance
#  6     energy_per_block
#  7     nearest_enemy_distance
#  8     enemy_territory_count
#  9     threat_level (0.0-1.0)
# 10     alliance_count
# 11     season_progress (0.0-1.0)
# 12-15  adjacent_tiles (empty/enemy/ally/blocked)
# 16-19  resource_density (N/E/S/W)
# 20     defense_strength
# 21     attack_power
# 22     staked_axm_normalized
# 23     prediction_market_confidence
# 24-31  (reserved for future game features)

FEATURE_NAMES = [
    "territory_n", "territory_e", "territory_s", "territory_w",
    "total_territory", "energy_balance", "energy_per_block",
    "nearest_enemy_dist", "enemy_territory", "threat_level",
    "alliance_count", "season_progress",
    "adj_empty", "adj_enemy", "adj_ally", "adj_blocked",
    "resource_n", "resource_e", "resource_s", "resource_w",
    "defense_strength", "attack_power",
    "staked_axm_norm", "prediction_confidence",
    "reserved_0", "reserved_1", "reserved_2", "reserved_3",
    "reserved_4", "reserved_5", "reserved_6", "reserved_7",
]

ACTION_NAMES = [
    "expand_north", "expand_east", "expand_south", "expand_west",
    "attack", "defend", "harvest", "idle"
]


# ─────────────────────────────────────────────
#  Model Architecture
# ─────────────────────────────────────────────

class FactionStrategyNet(nn.Module):
    """
    Lightweight transformer for faction strategy.

    Kept intentionally small so EZKL can compile it into
    a ZK circuit with reasonable proof generation time (~3-5s).

    Architecture:
        Input → Linear Projection → Positional Encoding
        → Transformer Encoder (2 layers, 4 heads)
        → Mean Pool → MLP Head → Action Logits
    """

    def __init__(
        self,
        state_dim: int = STATE_DIM,
        action_dim: int = ACTION_DIM,
        hidden_dim: int = HIDDEN_DIM,
        num_heads: int = NUM_HEADS,
        num_layers: int = NUM_LAYERS,
        seq_len: int = SEQ_LEN,
        dropout: float = DROPOUT,
    ):
        super().__init__()

        self.state_dim = state_dim
        self.action_dim = action_dim
        self.hidden_dim = hidden_dim
        self.seq_len = seq_len

        # Project input features to hidden dim
        self.input_proj = nn.Linear(state_dim, hidden_dim)

        # Learned positional encoding (not sinusoidal — simpler for ZK)
        self.pos_embedding = nn.Embedding(seq_len, hidden_dim)

        # Transformer encoder
        encoder_layer = nn.TransformerEncoderLayer(
            d_model=hidden_dim,
            nhead=num_heads,
            dim_feedforward=hidden_dim * 2,
            dropout=dropout,
            activation="relu",        # relu > gelu for ZK compatibility
            batch_first=True,
            norm_first=True,          # Pre-LN is more stable
        )
        self.transformer = nn.TransformerEncoder(
            encoder_layer,
            num_layers=num_layers,
        )

        # Classification head
        self.head = nn.Sequential(
            nn.Linear(hidden_dim, hidden_dim // 2),
            nn.ReLU(),
            nn.Dropout(dropout),
            nn.Linear(hidden_dim // 2, action_dim),
        )

        self._init_weights()

    def _init_weights(self):
        """Xavier init for stable training."""
        for module in self.modules():
            if isinstance(module, nn.Linear):
                nn.init.xavier_uniform_(module.weight)
                if module.bias is not None:
                    nn.init.zeros_(module.bias)
            elif isinstance(module, nn.Embedding):
                nn.init.normal_(module.weight, std=0.02)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        """
        Args:
            x: (batch, seq_len, state_dim) — history of game states

        Returns:
            logits: (batch, action_dim) — unnormalized action scores
        """
        batch_size, seq_len, _ = x.shape

        # Project to hidden dim
        x = self.input_proj(x)                           # (B, T, H)

        # Add positional encoding
        positions = torch.arange(seq_len, device=x.device)
        x = x + self.pos_embedding(positions)            # (B, T, H)

        # Transformer encoder
        x = self.transformer(x)                          # (B, T, H)

        # Mean pool over sequence
        x = x.mean(dim=1)                                # (B, H)

        # Action logits
        logits = self.head(x)                            # (B, A)

        return logits

    def predict_action(self, state_history: torch.Tensor) -> int:
        """Greedy action selection for inference."""
        self.eval()
        with torch.no_grad():
            logits = self.forward(state_history.unsqueeze(0))
            return logits.argmax(dim=-1).item()

    def count_parameters(self) -> int:
        return sum(p.numel() for p in self.parameters() if p.requires_grad)


# ─────────────────────────────────────────────
#  Synthetic Game Data Generator
# ─────────────────────────────────────────────

class GameDataGenerator:
    """
    Generates synthetic game state → action pairs.

    In production, replace this with real game logs
    collected from the on-chain MUD world events via The Graph.
    The format stays the same — just swap the source.
    """

    def __init__(self, seed: int = 42):
        self.rng = np.random.default_rng(seed)

    def _generate_state(self, strategy: str) -> np.ndarray:
        """Generate a plausible game state vector."""
        state = np.zeros(STATE_DIM, dtype=np.float32)

        # Territory (0-4)
        total = self.rng.integers(1, 100)
        split = self.rng.dirichlet([1, 1, 1, 1]) * total
        state[0:4] = split.astype(np.float32)
        state[4] = float(total)

        # Energy (5-6)
        state[5] = float(self.rng.integers(0, 10000))
        state[6] = float(self.rng.uniform(0.5, 10.0))

        # Threat (7-9)
        state[7] = float(self.rng.integers(1, 50))
        state[8] = float(self.rng.integers(0, 150))
        state[9] = float(self.rng.uniform(0.0, 1.0))

        # Diplomacy + time (10-11)
        state[10] = float(self.rng.integers(0, 5))
        state[11] = float(self.rng.uniform(0.0, 1.0))

        # Adjacent tiles (12-15)
        adj = self.rng.dirichlet([1, 1, 1, 1]) * 4
        state[12:16] = adj.astype(np.float32)

        # Resource density (16-19)
        state[16:20] = self.rng.uniform(0, 1, 4).astype(np.float32)

        # Combat stats (20-21)
        state[20] = float(self.rng.uniform(0.0, 1.0))
        state[21] = float(self.rng.uniform(0.0, 1.0))

        # Economic (22-23)
        state[22] = float(self.rng.uniform(0.0, 1.0))
        state[23] = float(self.rng.uniform(0.0, 1.0))

        return state

    def _state_to_action(self, state: np.ndarray, strategy: str) -> int:
        """
        Rule-based optimal action for a given state and strategy.
        This teaches the model domain knowledge before ZK compilation.

        Strategies:
            aggressive  — prioritize attacking and expanding
            defensive   — prioritize defending and harvesting
            balanced    — adaptive based on game state
        """
        threat = state[9]
        energy = state[5]
        total_territory = state[4]
        season_progress = state[11]
        defense = state[20]
        attack = state[21]

        if strategy == "aggressive":
            if energy > 500 and threat < 0.6:
                return 4                # attack
            elif total_territory < 20:
                return int(np.argmax(state[0:4]))  # expand weakest direction
            else:
                return 4                # attack

        elif strategy == "defensive":
            if threat > 0.7 or defense < 0.3:
                return 5                # defend
            elif energy < 200:
                return 6                # harvest
            else:
                direction = int(np.argmax(state[16:20]))  # expand highest resource
                return direction

        else:  # balanced
            if threat > 0.8:
                return 5                # defend — critical threat
            elif energy < 100:
                return 6                # harvest — low energy
            elif season_progress > 0.8 and total_territory < 30:
                return 4                # attack — end of season push
            elif total_territory < 15:
                return int(np.argmax(state[16:20]))  # expand resources
            else:
                return 4 if attack > defense else 5

    def generate_dataset(
        self,
        n_samples: int = 50000,
        seq_len: int = SEQ_LEN,
    ):
        """
        Generate (state_history, action) pairs.

        Returns:
            X: np.ndarray of shape (n_samples, seq_len, state_dim)
            y: np.ndarray of shape (n_samples,) — action labels
        """
        strategies = ["aggressive", "defensive", "balanced"]
        X = np.zeros((n_samples, seq_len, STATE_DIM), dtype=np.float32)
        y = np.zeros(n_samples, dtype=np.int64)

        for i in tqdm(range(n_samples), desc="Generating game data"):
            strategy = strategies[i % len(strategies)]
            history = np.stack([
                self._generate_state(strategy) for _ in range(seq_len)
            ])
            X[i] = history
            y[i] = self._state_to_action(history[-1], strategy)

        return X, y


# ─────────────────────────────────────────────
#  Training Loop
# ─────────────────────────────────────────────

class Trainer:
    def __init__(
        self,
        model: FactionStrategyNet,
        lr: float = 1e-3,
        weight_decay: float = 1e-4,
    ):
        self.model = model.to(DEVICE)
        self.criterion = nn.CrossEntropyLoss()
        self.optimizer = optim.AdamW(
            model.parameters(),
            lr=lr,
            weight_decay=weight_decay,
        )
        self.scheduler = optim.lr_scheduler.CosineAnnealingLR(
            self.optimizer,
            T_max=100,
            eta_min=1e-5,
        )
        self.history = {
            "train_loss": [], "val_loss": [],
            "train_acc": [], "val_acc": [],
        }

    def _run_epoch(self, loader: DataLoader, train: bool = True):
        self.model.train(train)
        total_loss, correct, total = 0.0, 0, 0

        with torch.set_grad_enabled(train):
            for X_batch, y_batch in loader:
                X_batch = X_batch.to(DEVICE)
                y_batch = y_batch.to(DEVICE)

                logits = self.model(X_batch)
                loss = self.criterion(logits, y_batch)

                if train:
                    self.optimizer.zero_grad()
                    loss.backward()
                    torch.nn.utils.clip_grad_norm_(self.model.parameters(), 1.0)
                    self.optimizer.step()

                total_loss += loss.item() * len(y_batch)
                preds = logits.argmax(dim=-1)
                correct += (preds == y_batch).sum().item()
                total += len(y_batch)

        return total_loss / total, correct / total

    def train(
        self,
        train_loader: DataLoader,
        val_loader: DataLoader,
        epochs: int = 100,
        output_path: Path = Path("faction_model.pt"),
    ):
        print(f"\n{'─'*60}")
        print(f"  AXIOM Faction Strategy Model Training")
        print(f"  Device  : {DEVICE}")
        print(f"  Params  : {self.model.count_parameters():,}")
        print(f"  Epochs  : {epochs}")
        print(f"{'─'*60}\n")

        best_val_acc = 0.0
        start = time.time()

        for epoch in range(1, epochs + 1):
            train_loss, train_acc = self._run_epoch(train_loader, train=True)
            val_loss, val_acc = self._run_epoch(val_loader, train=False)
            self.scheduler.step()

            self.history["train_loss"].append(train_loss)
            self.history["val_loss"].append(val_loss)
            self.history["train_acc"].append(train_acc)
            self.history["val_acc"].append(val_acc)

            # Save best model
            if val_acc > best_val_acc:
                best_val_acc = val_acc
                torch.save({
                    "epoch": epoch,
                    "model_state_dict": self.model.state_dict(),
                    "optimizer_state_dict": self.optimizer.state_dict(),
                    "val_acc": val_acc,
                    "val_loss": val_loss,
                    "config": {
                        "state_dim": self.model.state_dim,
                        "action_dim": self.model.action_dim,
                        "hidden_dim": self.model.hidden_dim,
                        "seq_len": self.model.seq_len,
                    },
                }, output_path)
                tag = " ✓ saved"
            else:
                tag = ""

            if epoch % 10 == 0 or epoch == 1:
                elapsed = time.time() - start
                print(
                    f"  Epoch {epoch:3d}/{epochs} | "
                    f"Loss {train_loss:.4f}/{val_loss:.4f} | "
                    f"Acc {train_acc:.3f}/{val_acc:.3f} | "
                    f"{elapsed:.0f}s{tag}"
                )

        elapsed = time.time() - start
        print(f"\n  Training complete in {elapsed:.1f}s")
        print(f"  Best val accuracy : {best_val_acc:.4f}")
        print(f"  Saved to          : {output_path}\n")

        return self.history

    def plot(self, save_path: Path = Path("training_curves.png")):
        """Save training curves as PNG."""
        fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 4))

        ax1.plot(self.history["train_loss"], label="Train", color="#4C8BF5")
        ax1.plot(self.history["val_loss"], label="Val", color="#F5834C")
        ax1.set_title("Loss")
        ax1.set_xlabel("Epoch")
        ax1.legend()
        ax1.grid(alpha=0.3)

        ax2.plot(self.history["train_acc"], label="Train", color="#4C8BF5")
        ax2.plot(self.history["val_acc"], label="Val", color="#F5834C")
        ax2.set_title("Accuracy")
        ax2.set_xlabel("Epoch")
        ax2.legend()
        ax2.grid(alpha=0.3)

        plt.suptitle("AXIOM Faction Strategy Model", fontweight="bold")
        plt.tight_layout()
        plt.savefig(save_path, dpi=150)
        print(f"  Curves saved to: {save_path}")


# ─────────────────────────────────────────────
#  Entry Point
# ─────────────────────────────────────────────

def parse_args():
    parser = argparse.ArgumentParser(description="Train AXIOM faction strategy model")
    parser.add_argument("--epochs", type=int, default=100)
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument("--lr", type=float, default=1e-3)
    parser.add_argument("--n-samples", type=int, default=50000)
    parser.add_argument("--output", type=str, default="faction_model.pt")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--no-plot", action="store_true")
    return parser.parse_args()


def main():
    args = parse_args()
    torch.manual_seed(args.seed)
    np.random.seed(args.seed)

    # 1. Generate data
    print("\n[1/4] Generating game state dataset...")
    generator = GameDataGenerator(seed=args.seed)
    X, y = generator.generate_dataset(n_samples=args.n_samples)
    print(f"      X shape : {X.shape}")
    print(f"      y shape : {y.shape}")
    print(f"      Actions : {dict(zip(ACTION_NAMES, np.bincount(y)))}")

    # 2. Split
    print("\n[2/4] Splitting train/val (80/20)...")
    X_train, X_val, y_train, y_val = train_test_split(
        X, y, test_size=0.2, random_state=args.seed, stratify=y
    )

    train_ds = TensorDataset(torch.from_numpy(X_train), torch.from_numpy(y_train))
    val_ds = TensorDataset(torch.from_numpy(X_val), torch.from_numpy(y_val))

    train_loader = DataLoader(train_ds, batch_size=args.batch_size, shuffle=True, num_workers=2)
    val_loader = DataLoader(val_ds, batch_size=args.batch_size, shuffle=False, num_workers=2)

    # 3. Train
    print(f"\n[3/4] Training on {DEVICE}...")
    model = FactionStrategyNet()
    trainer = Trainer(model, lr=args.lr)
    history = trainer.train(
        train_loader,
        val_loader,
        epochs=args.epochs,
        output_path=Path(args.output),
    )

    # 4. Plot + save metadata
    print("[4/4] Saving artifacts...")
    if not args.no_plot:
        trainer.plot()

    # Save training metadata for EZKL pipeline
    meta = {
        "model_path": args.output,
        "state_dim": STATE_DIM,
        "action_dim": ACTION_DIM,
        "hidden_dim": HIDDEN_DIM,
        "seq_len": SEQ_LEN,
        "num_heads": NUM_HEADS,
        "num_layers": NUM_LAYERS,
        "feature_names": FEATURE_NAMES,
        "action_names": ACTION_NAMES,
        "best_val_acc": max(history["val_acc"]),
        "total_params": model.count_parameters(),
    }
    with open("model_meta.json", "w") as f:
        json.dump(meta, f, indent=2)
    print(f"      Metadata saved to: model_meta.json")
    print("\n  Next step → run: python export.py\n")


if __name__ == "__main__":
    main()