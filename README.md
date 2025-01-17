# Abstract

MomentFactory

Build: npx hardhat compile
Deploy: npx hardhat deploy-zksync --script <deploy.js>
Verify: npx hardhat verify <contract-address>

Upgrade:
npx hardhat upgrade-zksync:proxy --contract-name MomentPayMaster --proxy-address 0xea1BDA89B4c3F7A47888dCd63169B5F8cf3dDCa3


f = await ethers.getContractFactory("MomentPayMaster")
t = await f.attach("0x5bCa693Ca2ADC0cCe5886b92f8300C904F4E4c36")