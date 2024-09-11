/* eslint-disable no-undef */
async function main() {
  const contract = await ethers.getContractAt(
    "VolumeFactory",
    "0xb5E7674682A89412828b033018e8dBc7D6eCd3DA"
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
