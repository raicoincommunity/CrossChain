import { ethers, network, upgrades } from "hardhat";
import { INVALID_DEPLOYED_ADDRESS, BSC_TEST_CONTRACTS } from './deployed';

async function main() {
  const { chainId } = await ethers.provider.getNetwork();
  if (chainId !== 97) {
    console.error(`Chain ID mismatch: expected=97, actual=${chainId}`);
    process.exitCode = 1;
    return;
  }

  // We get the contract to deploy
  const BSCTestV5 = await ethers.getContractFactory("BSCTestV5");
  const bscTestV5 = await upgrades.deployImplementation(BSCTestV5, { kind: 'uups' });

  console.log(`BSCTestV5 implementation deployed to: ${network.name}/${bscTestV5}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});