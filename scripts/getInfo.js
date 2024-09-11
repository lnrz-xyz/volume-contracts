/* eslint-disable no-undef */
async function main() {
  const contract = await ethers.getContractAt(
    "VolumeToken",
    "0xfd2c11bee1288fb59d8d747ae99d325845ead36e"
  )

  const split = await contract.split()
  const owner = await contract.owner()

  console.log("Split:", split)
  console.log("Owner:", owner)
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
