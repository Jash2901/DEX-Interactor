// scripts/deploy.js
const { ethers } = require("hardhat");

async function main() {
  // Get the first signer/account from Hardhat
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);

  // Get balance via provider (Ethers v6)
  const balance = await deployer.getAddress().then(addr => ethers.provider.getBalance(addr));
  console.log("Account balance:", balance.toString());

  // Get the contract factory and deploy
  const HelloWorld = await ethers.getContractFactory("HelloWorld");
  const hello = await HelloWorld.deploy();

  // Wait for deployment to finish
  await hello.waitForDeployment(); // v6 uses waitForDeployment() instead of deployed()

  console.log("HelloWorld deployed to:", await hello.getAddress());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
