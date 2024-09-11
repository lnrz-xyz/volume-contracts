/* eslint-disable no-undef */
async function main() {
  const contract = await ethers.getContractAt(
    "VolumeFactory",
    "0xD409ca01B35Ba99100469C9Bd600385692A8f030"
  )

  const config = await contract.config()
  const split = await contract.split()
  console.log("Config:", config)
  console.log("Split:", split)
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
