import { ethers, network } from "hardhat";

async function main() {

  // We get the contract to deploy
  const RAI721FactoryHelper = await ethers.getContractFactory("RAI721FactoryHelper");
  const rai721FactoryHelper = await RAI721FactoryHelper.deploy();

  await rai721FactoryHelper.deployed();

  const initCodeHash = await rai721FactoryHelper.TOKEN_INIT_CODE_HASH();

  console.log(`RAI721 init code hash: ${network.name}/${initCodeHash}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});