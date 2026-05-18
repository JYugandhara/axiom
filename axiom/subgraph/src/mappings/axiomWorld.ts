import {
  BigInt, Bytes, Address, log
} from "@graphprotocol/graph-ts"
import {
  Moved, TileClaimed, BattleRecorded,
  CivilizationMinted, AgentActionExecuted, SeasonAdvanced
} from "../../generated/AxiomWorld/MoveSystem"
import {
  Civilization, Move, TileClaim, Battle,
  AgentAction, GlobalStats, SeasonResult, DailySnapshot
} from "../../generated/schema"

// ─────────────────────────────────────────────────────────────
//  Helpers
// ─────────────────────────────────────────────────────────────

function getOrCreateCiv(id: BigInt): Civilization {
  let civ = Civilization.load(id.toString())
  if (civ == null) {
    civ = new Civilization(id.toString())
    civ.owner = Bytes.empty()
    civ.name = ""
    civ.territory = BigInt.fromI32(0)
    civ.energyBalance = BigInt.fromI32(0)
    civ.energyPerBlock = BigInt.fromI32(0)
    civ.agentModelHash = Bytes.empty()
    civ.isAutonomous = false
    civ.season = 1
    civ.mintedAtBlock = BigInt.fromI32(0)
    civ.moveCount = BigInt.fromI32(0)
    civ.claimCount = BigInt.fromI32(0)
    civ.battlesWon = BigInt.fromI32(0)
    civ.battlesLost = BigInt.fromI32(0)
  }
  return civ as Civilization
}

function getOrCreateGlobal(): GlobalStats {
  let stats = GlobalStats.load("global")
  if (stats == null) {
    stats = new GlobalStats("global")
    stats.totalCivilizations = 0
    stats.totalMoves = BigInt.fromI32(0)
    stats.totalClaims = BigInt.fromI32(0)
    stats.totalBattles = BigInt.fromI32(0)
    stats.totalEnergyMinted = BigInt.fromI32(0)
    stats.currentSeason = 1
    stats.lastUpdatedBlock = BigInt.fromI32(0)
  }
  return stats as GlobalStats
}

function getActionName(actionType: i32): string {
  const names = [
    "expand_north", "expand_east", "expand_south", "expand_west",
    "attack", "defend", "harvest", "idle"
  ]
  return actionType < names.length ? names[actionType] : "unknown"
}

// ─────────────────────────────────────────────────────────────
//  Event Handlers
// ─────────────────────────────────────────────────────────────

export function handleCivilizationMinted(event: CivilizationMinted): void {
  let civ = getOrCreateCiv(event.params.tokenId)
  civ.owner = event.params.owner
  civ.mintedAtBlock = event.block.number
  civ.season = 1
  civ.save()

  let stats = getOrCreateGlobal()
  stats.totalCivilizations++
  stats.lastUpdatedBlock = event.block.number
  stats.save()
}

export function handleMoved(event: Moved): void {
  let civId = event.params.civId
  let civ   = getOrCreateCiv(civId)
  civ.moveCount = civ.moveCount.plus(BigInt.fromI32(1))
  civ.save()

  let id   = event.transaction.hash.toHex() + "-" + event.logIndex.toString()
  let move = new Move(id)
  move.civ            = civId.toString()
  move.fromCommitment = event.params.fromCommitment
  move.toCommitment   = event.params.toCommitment
  move.nonce          = event.params.nonce
  move.blockNumber    = event.block.number
  move.timestamp      = event.block.timestamp
  move.transactionHash = event.transaction.hash
  move.save()

  let stats = getOrCreateGlobal()
  stats.totalMoves = stats.totalMoves.plus(BigInt.fromI32(1))
  stats.lastUpdatedBlock = event.block.number
  stats.save()
}

export function handleTileClaimed(event: TileClaimed): void {
  let civId = event.params.civId
  let civ   = getOrCreateCiv(civId)
  civ.territory  = civ.territory.plus(BigInt.fromI32(1))
  civ.claimCount = civ.claimCount.plus(BigInt.fromI32(1))
  civ.save()

  let id    = event.transaction.hash.toHex() + "-" + event.logIndex.toString()
  let claim = new TileClaim(id)
  claim.civ             = civId.toString()
  claim.claimCommitment  = event.params.claimCommitment
  claim.anchorCommitment = event.params.anchorCommitment
  claim.blockNumber      = event.block.number
  claim.timestamp        = event.block.timestamp
  claim.transactionHash  = event.transaction.hash
  claim.save()

  let stats = getOrCreateGlobal()
  stats.totalClaims = stats.totalClaims.plus(BigInt.fromI32(1))
  stats.save()
}

export function handleBattleRecorded(event: BattleRecorded): void {
  let battle = new Battle(event.params.battleId.toString())
  battle.attacker             = event.params.attackerId.toString()
  battle.defender             = event.params.defenderId.toString()
  battle.attackerWon          = event.params.attackerWon
  battle.territoryTransferred = 0
  battle.damageDealt          = 0
  battle.vrfSeed              = Bytes.empty()
  battle.blockNumber          = event.block.number
  battle.timestamp            = event.block.timestamp
  battle.save()

  let atk = getOrCreateCiv(event.params.attackerId)
  let def = getOrCreateCiv(event.params.defenderId)
  if (event.params.attackerWon) {
    atk.battlesWon  = atk.battlesWon.plus(BigInt.fromI32(1))
    def.battlesLost = def.battlesLost.plus(BigInt.fromI32(1))
  } else {
    def.battlesWon  = def.battlesWon.plus(BigInt.fromI32(1))
    atk.battlesLost = atk.battlesLost.plus(BigInt.fromI32(1))
  }
  atk.save(); def.save()

  let stats = getOrCreateGlobal()
  stats.totalBattles = stats.totalBattles.plus(BigInt.fromI32(1))
  stats.save()
}

export function handleAgentAction(event: AgentActionExecuted): void {
  let action = new AgentAction(event.params.taskId.toString())
  action.civ              = event.params.civId.toString()
  action.actionType       = event.params.action
  action.actionName       = getActionName(event.params.action)
  action.executed         = true
  action.submittedAtBlock = event.block.number
  action.timestamp        = event.block.timestamp
  action.save()
}

export function handleSeasonAdvanced(event: SeasonAdvanced): void {
  let result = new SeasonResult(event.params.oldSeason.toString())
  result.totalBattles = 0
  result.totalMoves   = 0
  result.totalClaims  = 0
  result.startBlock   = event.block.number
  result.save()

  let stats = getOrCreateGlobal()
  stats.currentSeason = event.params.newSeason
  stats.save()
}