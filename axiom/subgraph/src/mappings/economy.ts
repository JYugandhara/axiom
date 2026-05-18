import { BigInt, Bytes } from "@graphprotocol/graph-ts"
import { Staked, Unstaked, Claimed } from "../../generated/Staking/Staking"
import { BetPlaced, MarketResolved, MarketCreated } from "../../generated/PredictionMarket/PredictionMarket"
import { StakingPosition, PredictionMarket, PredictionBet, GlobalStats } from "../../generated/schema"

// ─────────────────────────────────────────────────────────────
//  Staking Handlers
// ─────────────────────────────────────────────────────────────

export function handleStaked(event: Staked): void {
  let id  = event.params.user.toHex() + "-" + event.params.posId.toString()
  let pos = new StakingPosition(id)
  pos.owner         = event.params.user
  pos.amount        = event.params.amount
  pos.lockedAt      = event.block.timestamp
  pos.unlockAt      = event.params.unlockAt
  pos.multiplierBps = 0 // updated separately if needed
  pos.active        = true
  pos.totalClaimed  = BigInt.fromI32(0)
  pos.save()
}

export function handleUnstaked(event: Unstaked): void {
  let id  = event.params.user.toHex() + "-" + event.params.posId.toString()
  let pos = StakingPosition.load(id)
  if (pos != null) {
    pos.active = false
    pos.save()
  }
}

export function handleClaimed(event: Claimed): void {
  let id  = event.params.user.toHex() + "-" + event.params.posId.toString()
  let pos = StakingPosition.load(id)
  if (pos != null) {
    pos.totalClaimed = pos.totalClaimed.plus(event.params.energyReward)
    pos.save()
  }

  let stats = GlobalStats.load("global")
  if (stats != null) {
    stats.totalEnergyMinted = stats.totalEnergyMinted.plus(event.params.energyReward)
    stats.save()
  }
}

// ─────────────────────────────────────────────────────────────
//  Prediction Market Handlers
// ─────────────────────────────────────────────────────────────

export function handleMarketCreated(event: MarketCreated): void {
  let market = new PredictionMarket(event.params.id.toString())
  market.season        = event.params.season.toI32()
  market.civId         = event.params.civId
  market.yesPool       = BigInt.fromI32(0)
  market.noPool        = BigInt.fromI32(0)
  market.resolved      = false
  market.closesAtBlock = event.params.closesAt
  market.totalBets     = 0
  market.save()
}

export function handleBetPlaced(event: BetPlaced): void {
  let marketId = event.params.marketId.toString()
  let market   = PredictionMarket.load(marketId)
  if (market == null) return

  if (event.params.isYes) {
    market.yesPool = market.yesPool.plus(event.params.axmIn)
  } else {
    market.noPool = market.noPool.plus(event.params.axmIn)
  }
  market.totalBets++
  market.save()

  let betId = marketId + "-" + event.transaction.hash.toHex() + "-" + event.logIndex.toString()
  let bet   = new PredictionBet(betId)
  bet.market    = marketId
  bet.bettor    = event.params.user
  bet.isYes     = event.params.isYes
  bet.axmIn     = event.params.axmIn
  bet.shares    = event.params.shares
  bet.claimed   = false
  bet.timestamp = event.block.timestamp
  bet.save()
}

export function handleMarketResolved(event: MarketResolved): void {
  let market = PredictionMarket.load(event.params.marketId.toString())
  if (market == null) return
  market.resolved = true
  market.outcome  = event.params.outcome
  market.save()
}