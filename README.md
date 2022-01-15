# creditum-farming

## CONTRACT ADDRESS:
Fantom Network:
* SteakHouseV2: https://ftmscan.com/address/0xe0c43105235c1f18ea15fdb60bb6d54814299938
* xCREDIT: https://ftmscan.com/address/0xd9e28749e80D867d5d14217416BFf0e668C10645

## Development
* run `npm install` to install all node dependencies
* run `npx hardhat compile` to compile

### Run Test With hardhat EVM (as [an independent node](https://hardhat.dev/hardhat-evm/#connecting-to-hardhat-evm-from-wallets-and-other-software))
* Run `npx hardhat node` to setup a local blockchain emulator in one terminal.
* `npx hardhat test --network localhost` run tests in a new terminal.
 **`npx hardhat node` restart required after full test run.** As the blockchain timestamp has changed.

 ## Deploy to Kovan Testnet
* Comment out requirement in Constructor of the Migrator
* Run `npx hardhat run scripts/deploy.js --network kovan`.
* Run `npx hardhat flatten contracts/RulerCore.sol > flat.sol` will flatten all contracts into one
* Ruler Token
`npx hardhat verify --network kovan 0xf687d6176332EF06e75446527900323978449E68`
* Implementation
`npx hardhat verify --network kovan 0x2F2aad0F318A6D79CD763bdA75a0D736E6b3d589`
* Ruler Core
`npx hardhat verify --network kovan 0x891a4296503B2D9F5FE3b6A9998d858337452E87 "0x2F2aad0F318A6D79CD763bdA75a0D736E6b3d589" "0x9E6C4d9DED2Cbaf57979CcB92aDEf1738F0d844f"`
