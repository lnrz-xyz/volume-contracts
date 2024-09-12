/* eslint-disable no-undef */
async function main() {
  const contract = await ethers.getContractAt(
    "VolumeToken",
    "0x3189a0e487cbf88879133edd5ffacc42725a1047"
  )

  // console.log(
  //   "Market Stats Fees: ",
  //   ethers.utils.formatEther(await contract.marketPurchaseValue())
  // )
  console.log(ethers.utils.formatEther(await contract.feesEarned()))
  await contract.claimFees()
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
