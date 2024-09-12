/* eslint-disable no-undef */
async function main() {
  const contract = await ethers.getContractAt(
    "VolumeFactory",
    "0xB3E601dE2352BC1E26728886467f552A1210CC95"
  )

  const config = await contract.config()

  console.log("Config:", config)
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
