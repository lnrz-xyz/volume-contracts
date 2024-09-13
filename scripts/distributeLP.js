/* eslint-disable no-undef */
async function main() {
  const contract = await ethers.getContractAt(
    "VolumeToken",
    "0x973a47B56cAa47587213a75e327641bF3Af7787B"
  )

  const split = await contract.split()
  console.log("Split: ", split)

  // await contract.distributeLP(true)
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
