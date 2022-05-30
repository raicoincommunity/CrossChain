import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { RAI721Factory, RAI721 } from "../typechain";
import { ADDRESS_ZERO} from './lib/constants';

describe("RAI721Factory", function () {
    let owner: SignerWithAddress;
    let core: SignerWithAddress;
    let addr1: SignerWithAddress;
    let addr2: SignerWithAddress;
    let factoryInstance: RAI721Factory;
    const abiCoder = ethers.utils.defaultAbiCoder;
  
    const deploy = async function () {
        [owner, core, addr1, addr2] = await ethers.getSigners();
        const factory = await ethers.getContractFactory("RAI721Factory");
        factoryInstance = await factory.deploy();
      }

    describe("Deployment", function () {
        before(deploy);

        it("Should set the right deployer", async function () {
            expect(await factoryInstance.deployer()).to.equal(owner.address);
        });

        it("Should init coreContract to 0", async function () {
            expect(await factoryInstance.coreContract()).to.equal(ADDRESS_ZERO);
        });
    });

    describe("Set core contract", function () {
        before(deploy);

        it("Should revert if not set by deployer", async function () {
            await expect(factoryInstance.connect(addr2).setCoreContract(addr1.address)).to.be.revertedWith("NotCalledByDeployer");
        });

        it("Should set the coreContract", async function () {
            const tx = await factoryInstance.connect(owner).setCoreContract(addr1.address);
            await tx.wait();
            expect(await factoryInstance.coreContract()).to.equal(addr1.address);
        });

        it("Should revert if the coreContract has been set", async function () {
            await expect(factoryInstance.setCoreContract(addr2.address)).to.be.revertedWith("CoreContractAreadySet");
        });
    });

    describe("Create", function () {
        before(deploy);

        it("Should revert if coreContract is not set", async function () {
            const tx = factoryInstance.create("", "", "Ethereum", 2, "0x00000000000000000000000057f1887a8bf19b14fc0df6fd9b2acc9af147ea85");
            await expect(tx).to.be.revertedWith("NotCalledByCoreContract");
        });

        it("Should set the coreContract", async function () {
            const tx = await factoryInstance.connect(owner).setCoreContract(core.address);
            await tx.wait();
            expect(await factoryInstance.coreContract()).to.equal(core.address);
        });

        it("Should revert if not called by coreContract", async function () {
            const tx = factoryInstance.connect(addr1).create("", "", "Ethereum", 2, "0x00000000000000000000000057f1887a8bf19b14fc0df6fd9b2acc9af147ea85");
            await expect(tx).to.be.revertedWith("NotCalledByCoreContract");
        });

        let token: RAI721;
        it("Should create a new RAI721 token", async function () {
            const tx = await factoryInstance.connect(core).create("", "", "Ethereum", 2, "0x00000000000000000000000057f1887a8bf19b14fc0df6fd9b2acc9af147ea85");
            const receipt = await tx.wait();
            const tokenAddr = abiCoder.decode(["address"], receipt.logs![0].data!)[0];

            token = await ethers.getContractAt("RAI721", tokenAddr);
            expect(await token.name()).to.equal("");
            expect(await token.symbol()).to.equal("");
            expect(await token.originalChain()).to.equal("Ethereum");
            expect(await token.originalChainId()).to.equal(2);
            expect(await token.originalContract()).to.equal("0x00000000000000000000000057f1887a8bf19b14fc0df6fd9b2acc9af147ea85");
            expect(await token.coreContract()).to.equal(core.address);
        });

        it("Should revert if create with the same chain ID and contract address", async function () {
            const tx = factoryInstance.connect(core).create("", "", "Ethereum", 2, "0x00000000000000000000000057f1887a8bf19b14fc0df6fd9b2acc9af147ea85");
            await expect(tx).to.be.reverted;
        });
    });

    describe("Mint & burn", function () {
        before(deploy);

        it("Should set the coreContract", async function () {
            const tx = await factoryInstance.connect(owner).setCoreContract(core.address);
            await tx.wait();
            expect(await factoryInstance.coreContract()).to.equal(core.address);
        });

        let token: RAI721;
        it("Should create a new RAI721 token", async function () {
            const tx = await factoryInstance.connect(core).create("Ethereum Name Service", "rENS_eth", "Ethereum", 2, "0x00000000000000000000000057f1887a8bf19b14fc0df6fd9b2acc9af147ea85");
            const receipt = await tx.wait();
            const tokenAddr = abiCoder.decode(["address"], receipt.logs![0].data!)[0];
            token = await ethers.getContractAt("RAI721", tokenAddr);
        });

        it("Should revert if not mint by coreContract", async function () {
            const tx = token.connect(owner).mint(owner.address, 1000);
            await expect(tx).to.be.revertedWith("NotCalledByCoreContract");
        });

        it("Should mint success", async function () {
            let tx = await token.connect(core).mint(addr1.address, 1000);
            await tx.wait();
            expect(await token.balanceOf(addr1.address)).to.equal(1);
            expect(await token.totalSupply()).to.equal(1);
            tx = await token.connect(core).mint(addr2.address, 2000);
            await tx.wait();
            expect(await token.balanceOf(addr2.address)).to.equal(1);
            expect(await token.totalSupply()).to.equal(2);
        });

        it("Should revert if not burn by coreContract", async function () {
            const tx = token.connect(addr1).burn(1);
            await expect(tx).to.be.revertedWith("NotCalledByCoreContract");
        });

        it("Should burn success", async function () {
            let tx = await token.connect(addr1).transferFrom(addr1.address, core.address, 1000);
            await tx.wait();
            expect(await token.balanceOf(addr1.address)).to.equal(0);
            expect(await token.totalSupply()).to.equal(2);
            expect(await token.balanceOf(core.address)).to.equal(1);
            expect(await token.ownerOf(1000)).to.equal(core.address);
            tx = await token.connect(core).burn(1000);
            await tx.wait();
            expect(await token.balanceOf(core.address)).to.equal(0);
            expect(await token.totalSupply()).to.equal(1);
        });

        it("Should revert if burn token not owned", async function () {
            const tx = token.connect(core).burn(2000);
            await expect(tx).to.be.revertedWith("TokenIdNotOwned");
        });

        it("Should revert if burn token not existing", async function () {
            const tx = token.connect(core).burn(1000);
            await expect(tx).to.be.revertedWith("ERC721: owner query for nonexistent token");
        });
    });

});