"use client";

import { useEffect, useRef, useState, useCallback } from "react";
import { Canvas, useFrame, useThree } from "@react-three/fiber";
import { OrbitControls, Text } from "@react-three/drei";
import * as THREE from "three";

// ─────────────────────────────────────────────────────────────
//  Types
// ─────────────────────────────────────────────────────────────

interface TileData {
  commitment: string;
  owner: number;  // 0 = unclaimed, civId = owned
  x: number;
  y: number;
}

interface WorldMapProps {
  onTileClick?: (tile: { commitment: string; owner: number }) => void;
}

// ─────────────────────────────────────────────────────────────
//  Tile colors by ownership
// ─────────────────────────────────────────────────────────────

const COLORS = {
  unclaimed : new THREE.Color("#21262D"),
  owned     : new THREE.Color("#1F6FEB"),
  enemy     : new THREE.Color("#F85149"),
  fog       : new THREE.Color("#0D1117"),
  hover     : new THREE.Color("#58A6FF"),
};

// ─────────────────────────────────────────────────────────────
//  Grid of tiles
// ─────────────────────────────────────────────────────────────

function TileGrid({ tiles, onTileClick }: { tiles: TileData[]; onTileClick?: WorldMapProps["onTileClick"] }) {
  const meshRef  = useRef<THREE.InstancedMesh>(null);
  const [hovered, setHovered] = useState<number | null>(null);

  const TILE_SIZE = 0.9;
  const geometry = new THREE.PlaneGeometry(TILE_SIZE, TILE_SIZE);
  const material = new THREE.MeshBasicMaterial({ vertexColors: true });

  useEffect(() => {
    if (!meshRef.current || tiles.length === 0) return;
    const mesh  = meshRef.current;
    const dummy = new THREE.Object3D();
    const color = new THREE.Color();

    tiles.forEach((tile, i) => {
      dummy.position.set(tile.x, tile.y, 0);
      dummy.updateMatrix();
      mesh.setMatrixAt(i, dummy.matrix);

      if (tile.owner === 0)      color.copy(COLORS.unclaimed);
      else if (tile.owner === 1) color.copy(COLORS.owned);    // player civ
      else                       color.copy(COLORS.enemy);

      mesh.setColorAt(i, color);
    });

    mesh.instanceMatrix.needsUpdate = true;
    if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
  }, [tiles]);

  return (
    <instancedMesh
      ref={meshRef}
      args={[geometry, material, tiles.length]}
      onClick={e => {
        e.stopPropagation();
        const tile = tiles[e.instanceId!];
        if (tile && onTileClick) onTileClick({ commitment: tile.commitment, owner: tile.owner });
      }}
    />
  );
}

// ─────────────────────────────────────────────────────────────
//  Scene
// ─────────────────────────────────────────────────────────────

function WorldScene({ onTileClick }: WorldMapProps) {
  // Generate a demo grid — replace with MUD store-sync data from useWorldSync hook
  const GRID = 30;
  const tiles: TileData[] = [];

  for (let x = -GRID; x <= GRID; x++) {
    for (let y = -GRID; y <= GRID; y++) {
      tiles.push({
        commitment: `0x${Math.abs(x * 1000 + y).toString(16).padStart(64, "0")}`,
        owner: Math.random() < 0.1 ? 1 : Math.random() < 0.08 ? 2 : 0,
        x, y,
      });
    }
  }

  return (
    <>
      <ambientLight intensity={0.5} />
      <TileGrid tiles={tiles} onTileClick={onTileClick} />
      <OrbitControls
        enableRotate={false}
        enablePan={true}
        enableZoom={true}
        minDistance={5}
        maxDistance={80}
        zoomSpeed={0.8}
        panSpeed={0.8}
      />

      {/* Grid lines overlay */}
      <gridHelper args={[120, 120, "#21262D", "#21262D"]} rotation={[Math.PI / 2, 0, 0]} position={[0, 0, -0.01]} />
    </>
  );
}

// ─────────────────────────────────────────────────────────────
//  Main export — Three.js canvas wrapper
// ─────────────────────────────────────────────────────────────

export default function WorldMap({ onTileClick }: WorldMapProps) {
  return (
    <Canvas
      orthographic
      camera={{ zoom: 20, position: [0, 0, 100] }}
      style={{ background: "#0D1117", width: "100%", height: "100%" }}
      gl={{ antialias: true }}
    >
      <WorldScene onTileClick={onTileClick} />
    </Canvas>
  );
}
