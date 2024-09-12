require("dotenv").config()
require("hardhat-deploy")
require("hardhat-contract-sizer")
require("@nomiclabs/hardhat-ethers")

// Set your preferred authentication method
//
// If you prefer using a mnemonic, set a MNEMONIC environment variable
// to a valid mnemonic
const MNEMONIC = process.env.MNEMONIC

// If you prefer to be authenticated using a private key, set a PRIVATE_KEY environment variable
const PRIVATE_KEY = process.env.PRIVATE_KEY

const accounts = MNEMONIC
  ? { mnemonic: MNEMONIC }
  : PRIVATE_KEY
    ? [PRIVATE_KEY]
    : undefined

if (accounts == null) {
  console.warn(
    "Could not find MNEMONIC or PRIVATE_KEY environment variables. It will not be possible to execute transactions in your example."
  )
}

module.exports = {
  paths: {
    cache: "cache/hardhat",
  },
  solidity: {
    compilers: [
      {
        version: "0.8.23",
        settings: {
          viaIR: true,
          optimizer: {
            enabled: true,
            runs: 100,
          },
        },
        // debug: {
        //   revertStrings: "strip",
        // },
      },
    ],
  },
  networks: {
    "base-mainnet": {
      url: process.env.RPC_URL_BASE_MAINNET,
      accounts,
    },
    "base-testnet": {
      url: process.env.RPC_URL_BASE_TESTNET,
      accounts,
    },
    "zora-testnet": {
      url: process.env.RPC_URL_ZORA_TESTNET,
      accounts,
    },
    testnet: {
      url: process.env.RPC_URL_TESTNET,
      accounts,
    },
  },
  namedAccounts: {
    deployer: {
      default: 0, // wallet address of index[0], of the mnemonic in .env
    },
  },
}
