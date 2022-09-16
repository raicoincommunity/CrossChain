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

  const prevImpl = await upgrades.erc1967.getImplementationAddress(core);
  const BSCTestV5 = await ethers.getContractFactory("BSCTestV5");
  const proxy = await upgrades.upgradeProxy(core, BSCTestV5, { 
    kind: 'uups', useDeployedImplementation: true, call: 'initializeV5',
    unsafeAllowRenames: true
   });
  await proxy.deployTransaction.wait();
  const newImpl = await upgrades.erc1967.getImplementationAddress(core);
  console.log(`BSCTest upgrade V4 to V5: network=${network.name}, core=${core}, \
    previous implementation=${prevImpl}, new implementation=${newImpl}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});