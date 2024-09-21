/* eslint-disable no-undef */
async function main() {
  const factory = await ethers.getContractAt(
    "VolumeFactory",
    "0x62364815Ddf88dB883829c003C36B4FE92fE96B7"
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
