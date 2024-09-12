/* eslint-disable no-undef */
async function main() {
  const contract = await ethers.getContractAt(
    "VolumeConfiguration",
    "0x45E34a9C78e611EE760BD510cC92fa86f1dB598E"
  )

  // await contract.setMinimumWETH(ethers.utils.parseEther("0.01"))
  // await contract.setLiquidityPoolVolumeThreshold(
  //   ethers.utils.parseEther("0.05")
  // )
  // Set Uniswap V3 Factory address
  await contract.setUniswapFactory("0x33128a8fC17869897dcE68Ed026d694621f6FDfD")

  // Set Uniswap V3 NonfungiblePositionManager address
  await contract.setUniswapPositionManager(
    "0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1"
  )
  // set splits factory
  await contract.setSplitFactory("0xaDC87646f736d6A82e9a6539cddC488b2aA07f38")

  console.log("Config updated successfully")
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
