import { ethers, network } from "hardhat";

async function main() {

  // We get the contract to deploy
  const RAI721Factory = await ethers.getContractFactory("RAI721Factory");
  const rai721Factory = await RAI721Factory.deploy();

  await rai721Factory.deployed();

  const RAI721 = await ethers.getContractFactory("RAI721");

  console.log(`RAI721Factory deployed to: ${network.name}/${rai721Factory.address}, RAI721 init code hash=${ethers.utils.keccak256(RAI721.bytecode)}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});