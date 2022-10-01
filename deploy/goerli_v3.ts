import { ethers, network, upgrades } from "hardhat";

async function main() {
  const { chainId } = await ethers.provider.getNetwork();
  if (chainId !== 5) {
    console.error(`Chain ID mismatch: expected=5, actual=${chainId}`);
    process.exitCode = 1;
    return;
  }

  // We get the contract to deploy
  const GoerliV3 = await ethers.getContractFactory("GoerliV3");
  const goerliV3 = await upgrades.deployImplementation(GoerliV3, { kind: 'uups' });

  console.log(`GoerliV3 implementation deployed to: ${network.name}/${goerliV3}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});