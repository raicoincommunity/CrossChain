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
  const BSCTestV4 = await ethers.getContractFactory("BSCTestV4");
  const bscTestV4 = await upgrades.deployImplementation(BSCTestV4, { kind: 'uups' });

  console.log(`BSCTestV4 implementation deployed to: ${network.name}/${bscTestV4}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});