const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Counter", function () {
    let Counter, counter;
    let owner, addr1, addr2;

    beforeEach(async function () {
        [owner, addr1, addr2] = await ethers.getSigners();
        Counter = await ethers.getContractFactory("Counter");
        counter = await Counter.deploy(0);
        await counter.deployed();
    });
});