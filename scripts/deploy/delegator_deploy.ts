export {};
const hre = require("hardhat");
const ethers = hre.ethers;


const delegator_name = ''


async function main() {

  console.log('Deploying a new Delegator : ' + delegator_name + '  ...')

  const deployer = (await hre.ethers.getSigners())[0];

  const Delegator = await ethers.getContractFactory(delegator_name);

  const delegator = await Delegator.deploy();
  await delegator.deployed();

  console.log('New ' + delegator_name + ' : ')
  console.log(delegator.address)

  await delegator.deployTransaction.wait(5);

  await hre.run("verify:verify", {
    address: delegator.address,
    constructorArguments: [],
  });
  
}


main()
.then(() => {
  process.exit(0);
})
.catch(error => {
  console.error(error);
  process.exit(1);
});