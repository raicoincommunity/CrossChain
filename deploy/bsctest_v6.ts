import { ethers, network, upgrades } from "hardhat";

async function main() {
  const { chainId } = await ethers.provider.getNetwork();
  if (chainId !== 97) {
    console.error(`Chain ID mismatch: expected=97, actual=${chainId}`);
    process.exitCode = 1;
    return;
  }

  // We get the contract to deploy
  const BSCTestV6 = await ethers.getContractFactory("BSCTestV6");
  const bscTestV6 = await upgrades.deployImplementation(BSCTestV6, { kind: 'uups' });

  console.log(`BSCTestV6 implementation deployed to: ${network.name}/${bscTestV6}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});