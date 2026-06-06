// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IEnergyTokenMint {
    function mint(address to, uint256 amount) external;
}
interface ICivStateEnergy {
    struct Data {
        uint256 territory; uint256 energyBalance; uint256 energyPerBlock;
        bytes32 agentModelHash; bool isAutonomous; uint64 moveNonce; uint64 claimNonce;
        uint32 attackPower; uint32 defensePower; uint32 season; address owner;
    }
    function get(uint256 civId) external view returns (Data memory);
}

/// @title EnergySystem
/// @notice Mints $ENERGY per block proportional to each civ's territory.
///         Called by Chainlink Automation on a fixed cadence.
contract EnergySystem {
    IEnergyTokenMint public immutable energyToken;
    ICivStateEnergy  public immutable civState;
    address          public immutable civNFT;
    address          public           automation;

    uint256 public lastProcessedBlock;

    event EnergyDistributed(uint256 blocksDelta, uint256 totalMinted, uint256 civCount);
    event AutomationUpdated(address newAutomation);

    error NotAutomation();

    constructor(address _energy, address _civ, address _nft, address _automation) {
        energyToken        = IEnergyTokenMint(_energy);
        civState           = ICivStateEnergy(_civ);
        civNFT             = _nft;
        automation         = _automation;
        lastProcessedBlock = block.number;
    }

    /// @notice Distribute $ENERGY to the supplied civilizations.
    ///         The active civId list is maintained off-chain and passed in
    ///         to keep gas bounded.
    function distributeEnergy(uint256[] calldata civIds) external {
        if (msg.sender != automation) revert NotAutomation();

        uint256 blocksDelta = block.number - lastProcessedBlock;
        if (blocksDelta == 0) return;

        uint256 totalMinted;
        for (uint256 i = 0; i < civIds.length; i++) {
            ICivStateEnergy.Data memory civ = civState.get(civIds[i]);
            if (civ.territory == 0 || civ.owner == address(0)) continue;

            uint256 toMint = civ.energyPerBlock * blocksDelta;
            energyToken.mint(civ.owner, toMint);
            totalMinted += toMint;
        }

        lastProcessedBlock = block.number;
        emit EnergyDistributed(blocksDelta, totalMinted, civIds.length);
    }

    function setAutomation(address newAutomation) external {
        require(msg.sender == automation, "EnergySystem: not automation");
        automation = newAutomation;
        emit AutomationUpdated(newAutomation);
    }
}
