/* eslint-disable no-undef */
async function main() {
  const contract = await ethers.getContractAt(
    "VolumeFactory",
    "0x439b9341471E5D8e6b3d33ea7482e6d944DbAac3"
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
