import { GraphQLClient } from "graphql-request";

// ─────────────────────────────────────────────────────────────
//  The Graph Client
// ─────────────────────────────────────────────────────────────

const GRAPH_URL = process.env.NEXT_PUBLIC_GRAPH_URL
  ?? "https://api.thegraph.com/subgraphs/name/axiom-world/axiom";

export const graphClient = new GraphQLClient(GRAPH_URL);

// ─────────────────────────────────────────────────────────────
//  Query: Season Leaderboard
// ─────────────────────────────────────────────────────────────

export const LEADERBOARD_QUERY = /* GraphQL */ `
  query Leaderboard($season: Int!, $limit: Int = 20) {
    civilizations(
      where: { season: $season }
      orderBy: territory
      orderDirection: desc
      first: $limit
    ) {
      id
      owner
      name
      territory
      energyBalance
      battlesWon
      battlesLost
      moveCount
      claimCount
      isAutonomous
    }
  }
`;

// ─────────────────────────────────────────────────────────────
//  Query: Civilization Detail
// ─────────────────────────────────────────────────────────────

export const CIV_DETAIL_QUERY = /* GraphQL */ `
  query CivDetail($civId: ID!) {
    civilization(id: $civId) {
      id
      owner
      name
      territory
      energyBalance
      energyPerBlock
      battlesWon
      battlesLost
      moveCount
      claimCount
      isAutonomous
      agentModelHash
      season
      mintedAtBlock
      moves(orderBy: blockNumber, orderDirection: desc, first: 10) {
        id
        fromCommitment
        toCommitment
        blockNumber
        timestamp
      }
      agentActions(orderBy: timestamp, orderDirection: desc, first: 10) {
        id
        actionType
        actionName
        executed
        timestamp
      }
      battlesAsAttacker(orderBy: blockNumber, orderDirection: desc, first: 5) {
        id
        defender { id name }
        attackerWon
        territoryTransferred
        blockNumber
      }
    }
  }
`;

// ─────────────────────────────────────────────────────────────
//  Query: Global Stats
// ─────────────────────────────────────────────────────────────

export const GLOBAL_STATS_QUERY = /* GraphQL */ `
  query GlobalStats {
    globalStats(id: "global") {
      totalCivilizations
      totalMoves
      totalClaims
      totalBattles
      totalEnergyMinted
      currentSeason
      lastUpdatedBlock
    }
  }
`;

// ─────────────────────────────────────────────────────────────
//  Query: Prediction Markets
// ─────────────────────────────────────────────────────────────

export const MARKETS_QUERY = /* GraphQL */ `
  query Markets($season: Int!, $resolved: Boolean = false) {
    predictionMarkets(
      where: { season: $season, resolved: $resolved }
      orderBy: totalBets
      orderDirection: desc
    ) {
      id
      civId
      yesPool
      noPool
      resolved
      outcome
      totalBets
      closesAtBlock
    }
  }
`;

// ─────────────────────────────────────────────────────────────
//  Query: Recent Battles
// ─────────────────────────────────────────────────────────────

export const RECENT_BATTLES_QUERY = /* GraphQL */ `
  query RecentBattles($limit: Int = 20) {
    battles(
      orderBy: blockNumber
      orderDirection: desc
      first: $limit
    ) {
      id
      attacker { id name }
      defender { id name }
      attackerWon
      territoryTransferred
      damageDealt
      blockNumber
      timestamp
    }
  }
`;

// ─────────────────────────────────────────────────────────────
//  Query: User Bets
// ─────────────────────────────────────────────────────────────

export const USER_BETS_QUERY = /* GraphQL */ `
  query UserBets($bettor: Bytes!) {
    predictionBets(where: { bettor: $bettor }) {
      id
      market { id civId resolved outcome }
      isYes
      axmIn
      shares
      claimed
      timestamp
    }
  }
`;

// ─────────────────────────────────────────────────────────────
//  Fetch helpers
// ─────────────────────────────────────────────────────────────

export async function fetchLeaderboard(season: number, limit = 20) {
  return graphClient.request(LEADERBOARD_QUERY, { season, limit });
}

export async function fetchCivDetail(civId: string) {
  return graphClient.request(CIV_DETAIL_QUERY, { civId });
}

export async function fetchGlobalStats() {
  return graphClient.request(GLOBAL_STATS_QUERY);
}

export async function fetchMarkets(season: number, resolved = false) {
  return graphClient.request(MARKETS_QUERY, { season, resolved });
}

export async function fetchRecentBattles(limit = 20) {
  return graphClient.request(RECENT_BATTLES_QUERY, { limit });
}

export async function fetchUserBets(bettor: string) {
  return graphClient.request(USER_BETS_QUERY, { bettor: bettor.toLowerCase() });
}
