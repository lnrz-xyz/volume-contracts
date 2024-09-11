/* eslint-disable no-undef */
async function main() {
  const contract = await ethers.getContractAt(
    "VolumeConfiguration",
    "0x5223E372861463B97aB1745B0F6F5A3b4FdD078E"
  )

  await contract.setMinimumWETH(ethers.utils.parseEther("0.005"))
  await contract.setLiquidityPoolVolumeThreshold(
    ethers.utils.parseEther("0.03")
  )
  // Set Uniswap V3 Factory address
  // await contract.setUniswapFactory("0x33128a8fC17869897dcE68Ed026d694621f6FDfD")

  // // Set Uniswap V3 NonfungiblePositionManager address
  // await contract.setUniswapPositionManager(
  //   "0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1"
  // )

  // // set splits factory
  // await contract.setSplitFactory("0xaDC87646f736d6A82e9a6539cddC488b2aA07f38")

  console.log(
    "Uniswap V3 Factory and Positions NFT addresses updated successfully"
  )
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
