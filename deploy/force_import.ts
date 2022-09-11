import { ethers, network, upgrades } from "hardhat";

async function main() {
  const { chainId } = await ethers.provider.getNetwork();
  if (chainId !== 97) {
    console.error(`Chain ID mismatch: expected=97, actual=${chainId}`);
    process.exitCode = 1;
    return;
  }


  const address = '0x2dD5Dfc76FFf5D857ed7a38C11E27B07f55d0606';
  const BSCTestV2 = await ethers.getContractFactory("BSCTestV2");
  await upgrades.forceImport(address, BSCTestV2,
    { kind: 'uups' });

  console.log(`BSCTest import: network=${network.name}, implementation=${address}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});