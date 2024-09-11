/* eslint-disable no-undef */
async function main() {
  const contract = await ethers.getContractAt(
    "VolumeToken",
    "0xfd2c11bee1288fb59d8d747ae99d325845ead36e"
  )

  console.log(
    "Market Stats Fees: ",
    ethers.utils.formatEther(await contract.marketPurchaseValue())
  )
  console.log(ethers.utils.formatEther(await contract.feesEarned()))
  await contract.claimFees()
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
