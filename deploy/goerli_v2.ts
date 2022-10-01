import { ethers, network, upgrades } from "hardhat";

async function main() {
  const { chainId } = await ethers.provider.getNetwork();
  if (chainId !== 5) {
    console.error(`Chain ID mismatch: expected=5, actual=${chainId}`);
    process.exitCode = 1;
    return;
  }

  // We get the contract to deploy
  const GoerliV2 = await ethers.getContractFactory("GoerliV2");
  const goerliV2 = await upgrades.deployImplementation(GoerliV2, { kind: 'uups' });

  console.log(`GoerliV2 implementation deployed to: ${network.name}/${goerliV2}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});