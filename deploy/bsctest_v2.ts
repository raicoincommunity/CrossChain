import { ethers, network, upgrades } from "hardhat";
import { INVALID_DEPLOYED_ADDRESS, BSC_TEST_CONTRACTS } from './deployed';

async function main() {
  const { chainId } = await ethers.provider.getNetwork();
  if (chainId !== 97) {
    console.error(`Chain ID mismatch: expected=97, actual=${chainId}`);
    process.exitCode = 1;
    return;
  }

  const core = BSC_TEST_CONTRACTS.core;
  if ( core === INVALID_DEPLOYED_ADDRESS) {
    console.error('Core not deployed');
    process.exitCode = 1;
    return;
  }

  // We get the contract to deploy
  const BSCTestV2 = await ethers.getContractFactory("BSCTestV2");
  const bscTestV2 = await upgrades.prepareUpgrade(core, BSCTestV2,
    { kind: 'uups' });

  console.log(`BSCTestV2 implementation deployed to: ${network.name}/${bscTestV2}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});