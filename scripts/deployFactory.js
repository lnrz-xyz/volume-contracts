/* eslint-disable no-undef */
async function main() {
  const Contract = await ethers.getContractFactory("VolumeFactory")

  const contract = await Contract.deploy(
    ethers.utils.parseEther("0.0004"),
    process.env.UNISWAP_FACTORY,
    process.env.UNISWAP_POSITIONS,
    process.env.WETH,
    process.env.SPLITS_FACTORY,
    "0x853F3b97215d0CbeB84f5201586f9ff11169524b"
  )

  console.log("Contract deployed to address:", contract.address)
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
