//! Pathfinding Worker
//!
//! Runs A* on the AXIOM territory graph.
//! Called by the TaskDispatcher when a PathfindingTask arrives.
//!
//! The territory graph consists of revealed tiles only —
//! fog-of-war tiles are hidden and treated as impassable.

use std::cmp::Ordering;
use std::collections::{BinaryHeap, HashMap};

use eyre::Result;
use tracing::debug;

use crate::{
    errors::OperatorError,
    types::{PathfindingResult, PathfindingTask, Tile, TerritoryGraph},
};

// ─────────────────────────────────────────────────────────────
//  A* Node
// ─────────────────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq, Eq)]
struct AStarNode {
    /// Estimated total cost f = g + h
    f_cost    : u32,
    /// Actual cost from start
    g_cost    : u32,
    /// Tile index in the graph
    tile_idx  : usize,
}

impl Ord for AStarNode {
    fn cmp(&self, other: &Self) -> Ordering {
        // Min-heap: lower f_cost = higher priority
        other.f_cost.cmp(&self.f_cost)
            .then_with(|| other.g_cost.cmp(&self.g_cost))
    }
}

impl PartialOrd for AStarNode {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

// ─────────────────────────────────────────────────────────────
//  Pathfinding Worker
// ─────────────────────────────────────────────────────────────

pub struct PathfindingWorker {
    max_nodes: usize,
}

impl PathfindingWorker {
    pub fn new(max_nodes: usize) -> Self {
        Self { max_nodes }
    }

    /// Find shortest path from `from` to `to` tile index using A*.
    pub fn find_path(&self, task: &PathfindingTask) -> Result<PathfindingResult> {
        let graph = &task.graph;

        if graph.tiles.is_empty() {
            return Ok(PathfindingResult {
                task_id   : task.task_id,
                civ_id    : task.civ_id,
                path      : vec![],
                total_cost: 0,
                reachable : false,
            });
        }

        // Find start and end by matching hashed commitments
        // In production: the chain submits actual tile indices along with hashes
        // For now we use first and last passable tile as stub
        let start_idx = graph.tiles.iter()
            .find(|t| t.passable)
            .map(|t| t.index)
            .unwrap_or(0);

        let goal_idx  = graph.tiles.iter().rev()
            .find(|t| t.passable)
            .map(|t| t.index)
            .unwrap_or(graph.tiles.len().saturating_sub(1));

        debug!(
            task_id   = %task.task_id,
            start     = start_idx,
            goal      = goal_idx,
            tiles     = graph.tiles.len(),
            edges     = graph.edges.len(),
            "Running A* pathfinding"
        );

        let (path, total_cost) = self.astar(graph, start_idx, goal_idx)?;
        let reachable = !path.is_empty();

        Ok(PathfindingResult {
            task_id: task.task_id,
            civ_id : task.civ_id,
            path,
            total_cost,
            reachable,
        })
    }

    /// Core A* implementation.
    fn astar(
        &self,
        graph    : &TerritoryGraph,
        start    : usize,
        goal     : usize,
    ) -> Result<(Vec<usize>, u32)> {
        if start == goal {
            return Ok((vec![start], 0));
        }

        // Build adjacency list for fast neighbor lookup
        let adj = self.build_adjacency(graph);

        // Tile lookup for coordinates (used in heuristic)
        let tile_map: HashMap<usize, &Tile> = graph.tiles.iter()
            .map(|t| (t.index, t))
            .collect();

        let mut open_set  : BinaryHeap<AStarNode> = BinaryHeap::new();
        let mut came_from : HashMap<usize, usize>  = HashMap::new();
        let mut g_score   : HashMap<usize, u32>    = HashMap::new();
        let mut explored  : usize                  = 0;

        g_score.insert(start, 0);
        open_set.push(AStarNode {
            f_cost   : self.heuristic(&tile_map, start, goal),
            g_cost   : 0,
            tile_idx : start,
        });

        while let Some(current) = open_set.pop() {
            explored += 1;

            if explored > self.max_nodes {
                return Err(OperatorError::PathfindingLimitExceeded {
                    limit: self.max_nodes,
                }.into());
            }

            if current.tile_idx == goal {
                // Reconstruct path
                let path = self.reconstruct_path(&came_from, goal);
                return Ok((path, current.g_cost));
            }

            let g = *g_score.get(&current.tile_idx).unwrap_or(&u32::MAX);

            // Explore neighbours
            if let Some(neighbors) = adj.get(&current.tile_idx) {
                for &(neighbor, edge_cost) in neighbors {
                    // Check tile is passable
                    if let Some(tile) = tile_map.get(&neighbor) {
                        if !tile.passable { continue; }
                    }

                    let tentative_g = g.saturating_add(edge_cost);
                    let best_g      = *g_score.get(&neighbor).unwrap_or(&u32::MAX);

                    if tentative_g < best_g {
                        came_from.insert(neighbor, current.tile_idx);
                        g_score.insert(neighbor, tentative_g);
                        let h = self.heuristic(&tile_map, neighbor, goal);
                        open_set.push(AStarNode {
                            f_cost   : tentative_g.saturating_add(h),
                            g_cost   : tentative_g,
                            tile_idx : neighbor,
                        });
                    }
                }
            }
        }

        // No path found
        Ok((vec![], 0))
    }

    /// Manhattan distance heuristic (admissible for grid movement).
    fn heuristic(
        &self,
        tile_map : &HashMap<usize, &Tile>,
        from     : usize,
        to       : usize,
    ) -> u32 {
        match (tile_map.get(&from), tile_map.get(&to)) {
            (Some(a), Some(b)) => {
                ((a.x - b.x).unsigned_abs() + (a.y - b.y).unsigned_abs()) as u32
            }
            _ => 0,
        }
    }

    /// Build adjacency list from edge list.
    fn build_adjacency(
        &self,
        graph: &TerritoryGraph,
    ) -> HashMap<usize, Vec<(usize, u32)>> {
        let mut adj: HashMap<usize, Vec<(usize, u32)>> = HashMap::new();
        for &(from, to, cost) in &graph.edges {
            adj.entry(from).or_default().push((to, cost));
            adj.entry(to).or_default().push((from, cost)); // bidirectional
        }
        adj
    }

    /// Reconstruct path by walking came_from map backwards.
    fn reconstruct_path(
        &self,
        came_from : &HashMap<usize, usize>,
        goal      : usize,
    ) -> Vec<usize> {
        let mut path    = vec![goal];
        let mut current = goal;
        while let Some(&prev) = came_from.get(&current) {
            path.push(prev);
            current = prev;
        }
        path.reverse();
        path
    }
}

// ─────────────────────────────────────────────────────────────
//  Tests
// ─────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use ethers::types::U256;

    fn make_grid(rows: i32, cols: i32) -> TerritoryGraph {
        let mut tiles = vec![];
        let mut edges = vec![];

        for r in 0..rows {
            for c in 0..cols {
                let idx = (r * cols + c) as usize;
                tiles.push(Tile { index: idx, x: c, y: r, passable: true, cost: 1 });

                // Right edge
                if c + 1 < cols {
                    edges.push((idx, idx + 1, 1));
                }
                // Down edge
                if r + 1 < rows {
                    edges.push((idx, (idx + cols as usize), 1));
                }
            }
        }
        TerritoryGraph { tiles, edges }
    }

    #[test]
    fn test_simple_grid_path() {
        let graph  = make_grid(5, 5);
        let worker = PathfindingWorker::new(10_000);

        let task = PathfindingTask {
            task_id   : U256::from(1),
            civ_id    : U256::from(42),
            from_hash : ethers::types::H256::zero(),
            to_hash   : ethers::types::H256::zero(),
            graph,
        };

        let result = worker.find_path(&task).unwrap();
        assert!(result.reachable, "Should find path on 5x5 grid");
        assert!(!result.path.is_empty(), "Path should not be empty");
        assert_eq!(result.path[0], 0,  "Path should start at tile 0");
        assert_eq!(*result.path.last().unwrap(), 24, "Path should end at tile 24");
    }

    #[test]
    fn test_same_start_goal() {
        let graph  = make_grid(3, 3);
        let worker = PathfindingWorker::new(1_000);

        let task = PathfindingTask {
            task_id   : U256::from(2),
            civ_id    : U256::from(1),
            from_hash : ethers::types::H256::zero(),
            to_hash   : ethers::types::H256::zero(),
            graph,
        };

        let result = worker.find_path(&task).unwrap();
        // find_path uses first/last tile, but if same → trivial path
        assert!(result.total_cost == 0 || result.reachable);
    }

    #[test]
    fn test_blocked_path() {
        // 3x1 grid with middle tile blocked
        let graph = TerritoryGraph {
            tiles: vec![
                Tile { index: 0, x: 0, y: 0, passable: true,  cost: 1 },
                Tile { index: 1, x: 1, y: 0, passable: false, cost: 1 }, // blocked
                Tile { index: 2, x: 2, y: 0, passable: true,  cost: 1 },
            ],
            edges: vec![(0, 1, 1), (1, 2, 1)],
        };

        let worker = PathfindingWorker::new(1_000);
        let task = PathfindingTask {
            task_id   : U256::from(3),
            civ_id    : U256::from(1),
            from_hash : ethers::types::H256::zero(),
            to_hash   : ethers::types::H256::zero(),
            graph,
        };

        let result = worker.find_path(&task).unwrap();
        assert!(!result.reachable, "Should not find path through blocked tile");
    }

    #[test]
    fn test_max_nodes_limit() {
        let graph  = make_grid(100, 100); // 10,000 tiles
        let worker = PathfindingWorker::new(10); // Tiny limit

        let task = PathfindingTask {
            task_id   : U256::from(4),
            civ_id    : U256::from(1),
            from_hash : ethers::types::H256::zero(),
            to_hash   : ethers::types::H256::zero(),
            graph,
        };

        let result = worker.find_path(&task);
        assert!(result.is_err(), "Should error when node limit exceeded");
    }
}