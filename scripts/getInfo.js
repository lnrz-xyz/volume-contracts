/* eslint-disable no-undef */
async function main() {
  const contract = await ethers.getContractAt(
    "VolumeToken",
    "0x8E4d0F85e71a6e924F51376115FD1B7169beafaD"
  )

  const volume = await contract.volume()
  const curBalance = await contract.balanceOf(
    "0x8E4d0F85e71a6e924F51376115FD1B7169beafaD"
  )

  const amount0ToDistribute = await contract.amount0ToDistribute()
  const amount1ToDistribute = await contract.amount1ToDistribute()
  console.log("Volume:", ethers.utils.formatEther(volume))
  console.log("Cur Balance:", ethers.utils.formatEther(curBalance))
  console.log(
    "Amount0ToDistribute:",
    ethers.utils.formatEther(amount0ToDistribute)
  )
  console.log(
    "Amount1ToDistribute:",
    ethers.utils.formatEther(amount1ToDistribute)
  )
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
