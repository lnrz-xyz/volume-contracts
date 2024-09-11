/* eslint-disable no-undef */
async function main() {
  const contract = await ethers.getContractAt(
    "VolumeToken",
    "0xf1a64a66a096fb81e9cca93840a9f03ea6bd28ef"
  )

  await contract.testWithdrawRemoveBeforeProd()
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
