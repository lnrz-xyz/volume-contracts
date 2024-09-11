/* eslint-disable no-undef */
async function main() {
  const contract = await ethers.getContractAt(
    "VolumeToken",
    "0xf5c97fea2c1e95d1194f22e60c1cb3eeab155949"
  )

  await contract.testWithdrawRemoveBeforeProd()
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
