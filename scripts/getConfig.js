/* eslint-disable no-undef */
async function main() {
  const contract = await ethers.getContractAt(
    "VolumeFactory",
    "0xE8EB3F19326D2F42Cf3Af525F63A3266181ab1cC"
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
