/* eslint-disable no-undef */
async function main() {
  const contract = await ethers.getContractAt(
    "VolumeToken",
    "0x343c1e311a120e826a64011356506cd8435c0e2c"
  )

  await contract.ejectLP()

  console.log("Ejected LP successfully")
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
