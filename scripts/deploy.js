/* eslint-disable no-undef */
async function main() {
  const factory = await ethers.getContractAt(
    "VolumeFactory",
    "0x6bBA1744a6dE420f0BAb461d845276fFBe207A94"
  )

  const tx = await factory.createVolumeToken(
    "Please Work",
    "PLZ",
    "https://streamz.xyz",
    {
      value: ethers.utils.parseEther("0.0004"),
    }
  )

  const res = await tx.wait()

  console.log("Res: ", res.transactionHash)
  // print the address of the first log
  console.log("First log: ", res.logs[0].address)
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
