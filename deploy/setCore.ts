import { ethers, network } from "hardhat";
import { INVALID_DEPLOYED_ADDRESS, DeployedContracts, BSC_TEST_CONTRACTS,
  GOERLI_CONTRACTS } from './deployed';

async function main() {
  let contracts: DeployedContracts | undefined;
  if (network.name === 'bsctest') {
    contracts = BSC_TEST_CONTRACTS;
  } else if (network.name === 'goerli') {
    contracts = GOERLI_CONTRACTS;
  } else {
    console.error(`Unsupported network: ${network.name}`);
    process.exitCode = 1;
    return;
  }
  
  const validatorManager = contracts.validatorManager;
  if ( validatorManager === INVALID_DEPLOYED_ADDRESS) {
    console.error('ValidatorManager not deployed');
    process.exitCode = 1;
    return;
  }

  const rai20Factory = contracts.rai20Factory;
  if (rai20Factory === INVALID_DEPLOYED_ADDRESS) {
    console.error('ERC20Factory not deployed');
    process.exitCode = 1;
    return;
  }

  const rai721Factory = contracts.rai721Factory;
  if (rai721Factory === INVALID_DEPLOYED_ADDRESS) {
    console.error('ERC721Factory not deployed');
    process.exitCode = 1;
    return;
  }

  const core = contracts.core;
  if (core === INVALID_DEPLOYED_ADDRESS) {
    console.error('Core not deployed');
    process.exitCode = 1;
    return;
  }

  const validatorManagerContract = await ethers.getContractAt("ValidatorManager", validatorManager);
  let existing = await validatorManagerContract.coreContract();
  if (existing === INVALID_DEPLOYED_ADDRESS) {
    await validatorManagerContract.setCoreContract(core);
    console.log(`[${network.name}] ValidatorManager.setCoreContract to: ${core}`);
  } else {
    console.log(`[${network.name}] ValidatorManager.setCoreContract skip: existing = ${existing}`);
  }

  const rai20FactoryContract = await ethers.getContractAt("RAI20Factory", rai20Factory);
  existing = await rai20FactoryContract.coreContract();
  if (existing === INVALID_DEPLOYED_ADDRESS) {
    await rai20FactoryContract.setCoreContract(core);
    console.log(`[${network.name}] RAI20Factory.setCoreContract to: ${core}`);  
  } else {
    console.log(`[${network.name}] RAI20Factory.setCoreContract skip: existing = ${existing}`);
  }

  const rai721FactoryContract = await ethers.getContractAt("RAI721Factory", rai721Factory);
  existing = await rai721FactoryContract.coreContract();
  if (existing === INVALID_DEPLOYED_ADDRESS) {
    await rai721FactoryContract.setCoreContract(core);
    console.log(`[${network.name}] RAI721Factory.setCoreContract to: ${core}`);
  } else {
    console.log(`[${network.name}] RAI721Factory.setCoreContract skip: existing = ${existing}`);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});