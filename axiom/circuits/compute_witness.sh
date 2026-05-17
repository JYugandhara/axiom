#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  AXIOM Circuits — Witness Computation Helper
#  File: circuits/compute_witness.sh
#
#  Computes Poseidon2 commitments for Prover.toml files.
#  Run this before `nargo prove` to generate valid commitment values.
#
#  Usage:
#    chmod +x compute_witness.sh
#    ./compute_witness.sh
#
#  Prerequisites:
#    nargo installed (noirup)
#    Fill in your actual coordinate and secret values below
# ─────────────────────────────────────────────────────────────

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  AXIOM — Circuit Witness Generator       ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
echo ""

# ── Check nargo is installed ─────────────────────────────────
if ! command -v nargo &> /dev/null; then
    echo -e "${RED}✗ nargo not found${NC}"
    echo "  Install it with: noirup"
    exit 1
fi
echo -e "${GREEN}✓ nargo $(nargo --version 2>/dev/null || echo 'found')${NC}"

# ─────────────────────────────────────────────────────────────
#  FOG OF WAR — Compute commitments
# ─────────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}── Fog of War Circuit ──────────────────────${NC}"

cd fog_of_war

# Write a temporary Noir program just to compute the hash
cat > /tmp/compute_fog_hash.nr << 'NOIR'
use dep::std::hash::poseidon2::Poseidon2;

fn main() {
    // ── EDIT THESE VALUES ──
    let from_x: Field    = 1000100;   // world X + 1_000_000
    let from_y: Field    = 1000200;   // world Y + 1_000_000
    let to_x: Field      = 1000101;
    let to_y: Field      = 1000200;
    let player_secret: Field = 99999; // your private salt
    // ──────────────────────

    let from_c = Poseidon2::hash([from_x, from_y, player_secret], 3);
    let to_c   = Poseidon2::hash([to_x,   to_y,   player_secret], 3);

    // These will print when you run `nargo execute`
    dep::std::println(f"from_commitment = {from_c}");
    dep::std::println(f"to_commitment   = {to_c}");
}
NOIR

echo "  Running nargo execute to compute commitments..."
echo -e "  ${YELLOW}Edit the values in this script before running!${NC}"
echo ""
echo "  Commitments for fog_of_war/Prover.toml:"
echo "  ─────────────────────────────────────────"

# Run nargo test to compute and print hashes
nargo test 2>&1 | grep -E "(from_commitment|to_commitment|PASS|FAIL)" || true

echo ""
echo "  After getting values, paste them into fog_of_war/Prover.toml"
echo "  Then run: nargo prove"

cd ..

# ─────────────────────────────────────────────────────────────
#  TERRITORY CLAIM — Compute commitments
# ─────────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}── Territory Claim Circuit ─────────────────${NC}"

cd territory_claim

echo "  Running nargo test to compute commitments..."
echo ""

nargo test 2>&1 | grep -E "(claim_commitment|anchor_commitment|civ_id_hash|PASS|FAIL)" || true

echo ""
echo "  After getting values, paste them into territory_claim/Prover.toml"
echo "  Then run: nargo prove"

cd ..

# ─────────────────────────────────────────────────────────────
#  Run all tests
# ─────────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}── Running all circuit tests ───────────────${NC}"
echo ""

TESTS_PASSED=0
TESTS_FAILED=0

for circuit in fog_of_war territory_claim; do
    echo -n "  Testing $circuit... "
    cd $circuit
    if nargo test --silence-warnings 2>&1 | grep -q "All tests passed"; then
        echo -e "${GREEN}✓ PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗ FAIL${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        nargo test --silence-warnings 2>&1 | tail -5
    fi
    cd ..
done

echo ""
echo -e "  Results: ${GREEN}${TESTS_PASSED} passed${NC}, ${RED}${TESTS_FAILED} failed${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All circuits are working correctly!${NC}"
    echo ""
    echo "  Next steps:"
    echo "  1. Fill in Prover.toml for each circuit with real values"
    echo "  2. cd fog_of_war && nargo prove"
    echo "  3. cd fog_of_war && nargo codegen-verifier"
    echo "     → copy output to contracts/src/zk/FogVerifier.sol"
    echo "  4. cd territory_claim && nargo prove"
    echo "  5. cd territory_claim && nargo codegen-verifier"
    echo "     → copy output to contracts/src/zk/TerritoryVerifier.sol"
else
    echo -e "${RED}✗ Some tests failed — check errors above${NC}"
    exit 1
fi
echo ""