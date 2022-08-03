import { ethers, network, upgrades } from "hardhat";
import { INVALID_DEPLOYED_ADDRESS, BSC_TEST_CONTRACTS } from './deployed';

async function main() {

  const validatorManager = BSC_TEST_CONTRACTS.validatorManager;
  if ( validatorManager === INVALID_DEPLOYED_ADDRESS) {
    console.error('ValidatorManager not deployed');
    process.exitCode = 1;
    return;
  }

  const rai20Factory = BSC_TEST_CONTRACTS.rai20Factory;
  if (rai20Factory === INVALID_DEPLOYED_ADDRESS) {
    console.error('ERC20Factory not deployed');
    process.exitCode = 1;
    return;
  }

  const rai721Factory = BSC_TEST_CONTRACTS.rai721Factory;
  if (rai721Factory === INVALID_DEPLOYED_ADDRESS) {
    console.error('ERC721Factory not deployed');
    process.exitCode = 1;
    return;
  }

  const { chainId } = await ethers.provider.getNetwork();
  if (chainId !== 97) {
    console.error(`Chain ID mismatch: expected=97, actual=${chainId}`);
    process.exitCode = 1;
    return;
  }

  // We get the contract to deploy
  const BSCTest = await ethers.getContractFactory("BSCTest");
  const bscTest = await upgrades.deployProxy(BSCTest,
    [validatorManager, rai20Factory, rai721Factory],
    { kind: 'uups' });

  await bscTest.deployed();

  console.log(`BSCTest core deployed to: ${network.name}/${bscTest.address}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});