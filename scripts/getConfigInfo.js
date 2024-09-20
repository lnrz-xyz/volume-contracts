/* eslint-disable no-undef */
async function main() {
  const contract = await ethers.getContractAt(
    "VolumeConfiguration",
    "0x4c37E0Cf03E3c0F261F6ea299e0E286771481BC1"
  )

  const liq = await contract.liquidityPoolVolumeThreshold()
  console.log("Liquidity Pool Volume Threshold:", liq)
  const minWETH = await contract.minimumWETH()
  console.log("Minimum WETH:", minWETH)
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
